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

  rpgc    -- record what THIS compiler makes of each source, alongside IBM's
          verdict. That turns the baseline into a two-compiler record, which is
          what lets a negative test be classified by evidence rather than by its
          filename: a test named *_err is only "correctly rejected" when BOTH
          compilers reject it. Three tests were previously miscounted as
          expected failures when rpgc was in fact accepting them.

Usage:
  conformance-baseline.py check   [--baseline F] [--tests D]
  conformance-baseline.py changed [--baseline F] [--tests D]
  conformance-baseline.py update  --transcript F [--baseline F] [--tests D]
"""
import sys, os, json, glob, hashlib, argparse, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import conformance_lib as L

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
    ap.add_argument("action", choices=["check", "changed", "update", "rpgc"])
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
            # an entry holding only an rpgc verdict (the rpgc action ran
            # before IBM ever compiled the source) is not verified either
            if rec is None or "verdict" not in rec:
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

    if a.action == "rpgc":
        import subprocess, tempfile
        exe = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(a.baseline))), "rpgc")
        exe = exe if os.path.exists(exe) else "./rpgc"
        if not os.path.exists(exe):
            print("no rpgc binary; build it first (make)", file=sys.stderr); return 2
        n_acc = 0
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "o")
            for pth in srcs:
                nm = os.path.basename(pth)
                # -c: compile, don't link. IBM compiles each source on its
                # own, so this is the like-for-like verdict. Linking made the
                # callers and callees of multi-program tests "fail" alone —
                # ten of them, all compiling fine.
                ok = subprocess.run([exe, "-c", pth, "-o", out],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL).returncode == 0
                files.setdefault(nm, {})["rpgc"] = "accept" if ok else "reject"
                n_acc += ok
        base["files"] = dict(sorted(files.items()))
        json.dump(base, open(a.baseline, "w"), indent=1, sort_keys=True)
        open(a.baseline, "a").write("\n")
        print(f"recorded rpgc verdicts for {len(srcs)} sources ({n_acc} accepted)")
        return 0

    # update
    if not a.transcript:
        print("update needs --transcript", file=sys.stderr); return 2
    fresh = parse_transcript(a.transcript)
    # Why IBM rejected each source, kept with its verdict so that anything
    # rendered from the baseline (conformance-wiki.py) can explain every
    # rejection, including sources a --changed-only run did not re-send.
    L.TESTS = a.tests
    listings = L.load_transcript(a.transcript)
    regressions, improvements, added = [], [], []
    for p in srcs:
        n, d = os.path.basename(p), digest(p)
        new = fresh.get(n)
        if new is None:
            continue                       # not in this run (e.g. --changed-only)
        old = files.get(n)
        if old is None or "verdict" not in old:     # new, or only an rpgc verdict so far
            added.append(n)
        elif old["verdict"] == "accept" and new["verdict"] == "reject":
            regressions.append((n, new["codes"][:4]))
        elif old["verdict"] == "reject" and new["verdict"] == "accept":
            improvements.append(n)
        keep = files.get(n, {}).get("rpgc")
        files[n] = {"sha256": d, "verdict": new["verdict"], "codes": new["codes"],
                    # when IBM last compiled this source; a --changed-only run
                    # leaves the others' dates alone
                    "verified": datetime.datetime.now(datetime.timezone.utc).date().isoformat()}
        if new["verdict"] == "reject" and n in listings:
            ms = L.ibm_messages(listings[n])
            cause, detail = L.root_cause(n, ms)
            files[n]["reason"] = cause
            if detail: files[n]["reason_detail"] = detail
            files[n]["messages"] = [
                {"code": c, "severity": sev, "line": ln, "text": t}
                for c, sev, ln, t in sorted(ms, key=lambda m: (m[2] or 10**9))[:5]]
        if keep: files[n]["rpgc"] = keep
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
