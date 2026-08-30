#!/usr/bin/env python3
"""Baseline of IBM i conformance verdicts, keyed by source content.

Turns the conformance run from a manual expedition into a build step. The
baseline records, for every test source, the SHA-256 of its content and the
verdict IBM's compiler gave it. That supports two very different checks:

  check   (offline, no network) -- is every source still the exact bytes that
          were verified on IBM i? A changed file has no verified verdict, so it
          is reported as unverified. This is the gate that can run on every
          push and pull request, including from forks, which cannot see the
          SSH secret.

  update  (online) -- merge a fresh run's verdicts in, and report REGRESSIONS:
          a file that IBM accepted before and rejects now. That is the signal
          worth failing a build over; the absolute accepted count is not, since
          it conflates unrelated causes (see TODO.md's bucket triage).

  changed -- list sources whose hash differs from the baseline, so an online
          run can send only those to a shared, free machine rather than all 221.

Usage:
  conformance-baseline.py check   [--baseline F] [--tests D]
  conformance-baseline.py changed [--baseline F] [--tests D]
  conformance-baseline.py update  --transcript F [--baseline F] [--tests D]
"""
import sys, os, json, glob, hashlib, argparse, datetime

def sources(tests):
    out = []
    for p in sorted(glob.glob(os.path.join(tests, '*.rpgle')) +
                    glob.glob(os.path.join(tests, '*.sqlrpgle'))):
        if 'copybook' in os.path.basename(p).lower():
            continue          # includes, not programs -- never compiled alone
        out.append(p)
    return out

def digest(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()

def load(path):
    if not os.path.exists(path):
        return {"generated": None, "files": {}}
    return json.load(open(path))

def parse_transcript(path):
    """{filename: {verdict, codes}} from a conformance run transcript."""
    import re
    MSG = re.compile(r'^\s*\*?(RN[SF]\d{4})\s+(\d+)')
    SEV = re.compile(r'^\s+(Error|Severe Error)\s+\(\d+\+?\).*:\s*([1-9]\d*)')
    out, cur, buf = {}, None, []
    for ln in open(path, errors='replace'):
        ln = ln.rstrip('\n')
        if ln.startswith('@@@FILE '):
            cur, buf = ln[8:].strip(), []
        elif ln.startswith('@@@RC ') and cur:
            rc = int(ln[6:].strip() or 1)
            bad = rc != 0 or any(SEV.match(b) for b in buf)
            codes = sorted({m.group(1) for b in buf
                            for m in [MSG.match(b)] if m and int(m.group(2)) >= 20})
            out[cur] = {"verdict": "reject" if bad else "accept", "codes": codes}
            cur, buf = None, []
        elif cur is not None:
            buf.append(ln)
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["check", "changed", "update"])
    ap.add_argument("--baseline", default="ibmi-conformance-baseline.json")
    ap.add_argument("--tests", default="tests")
    ap.add_argument("--transcript")
    a = ap.parse_args()

    base = load(a.baseline)
    files = base.get("files", {})
    srcs = sources(a.tests)

    if a.action in ("check", "changed"):
        unverified, changed = [], []
        for p in srcs:
            n, d = os.path.basename(p), digest(p)
            rec = files.get(n)
            if rec is None:
                unverified.append((n, "never verified on IBM i"))
                changed.append(n)
            elif rec["sha256"] != d:
                unverified.append((n, f"changed since verification ({rec['verdict']})"))
                changed.append(n)
        stale = [n for n in files if n not in {os.path.basename(p) for p in srcs}]

        if a.action == "changed":
            print("\n".join(changed))
            return 0

        print(f"sources           : {len(srcs)}")
        print(f"verified baseline : {len(files)}"
              f"   (generated {base.get('generated') or 'never'})")
        print(f"unverified        : {len(unverified)}")
        if stale:
            print(f"stale entries     : {len(stale)} (source no longer present)")
        if unverified:
            print("\nThese sources have no verified IBM i verdict:")
            for n, why in unverified:
                print(f"  {n:<48} {why}")
            print("\nRun scripts/ibmi-conformance.sh to verify them and refresh the baseline.")
            return 1
        acc = sum(1 for r in files.values() if r["verdict"] == "accept")
        print(f"\nall sources match their verified verdict "
              f"({acc} accepted, {len(files)-acc} rejected by IBM)")
        return 0

    # update
    if not a.transcript:
        print("update needs --transcript", file=sys.stderr); return 2
    fresh = parse_transcript(a.transcript)
    regressions, improvements, added = [], [], []
    for p in srcs:
        n, d = os.path.basename(p), digest(p)
        new = fresh.get(n)
        if new is None:
            continue                       # not in this run (e.g. --changed-only)
        old = files.get(n)
        if old is None:
            added.append(n)
        elif old["verdict"] == "accept" and new["verdict"] == "reject":
            regressions.append((n, new["codes"][:4]))
        elif old["verdict"] == "reject" and new["verdict"] == "accept":
            improvements.append(n)
        files[n] = {"sha256": d, "verdict": new["verdict"], "codes": new["codes"]}
    for n in [n for n in list(files) if n not in {os.path.basename(p) for p in srcs}]:
        del files[n]                       # source removed

    base["files"] = dict(sorted(files.items()))
    base["generated"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    json.dump(base, open(a.baseline, "w"), indent=1, sort_keys=True)
    open(a.baseline, "a").write("\n")

    acc = sum(1 for r in files.values() if r["verdict"] == "accept")
    print(f"baseline updated: {len(files)} sources, {acc} accepted by IBM")
    if added:        print(f"  newly recorded : {len(added)}")
    if improvements: print(f"  now accepted   : {len(improvements)}")
    for n in improvements[:10]: print(f"     + {n}")
    if regressions:
        print(f"\n  REGRESSIONS (IBM accepted before, rejects now): {len(regressions)}")
        for n, c in regressions:
            print(f"     - {n:<46} {','.join(c)}")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
