#!/usr/bin/env python3
"""Renders a release-facing IBM i compatibility summary.

Answers one question for a given release: how much of the test corpus does
IBM's own ILE RPG compiler accept? The raw accepted count alone is misleading,
because a rejection can be the CORRECT outcome -- negative tests exist to be
rejected -- so the summary also breaks the rejections down by cause.

Reads the committed baseline (or a fresh transcript) and writes Markdown.

Usage:
  conformance-summary.py [--baseline F] [--transcript F] [--out F] [--release TAG]
"""
import sys, os, json, glob, argparse, collections, datetime

DEP    = {'RNF2120','RNF7030','RNF7503','RNF2121','RNF2109','RNF7080'}
STRUCT = {'RNF7023','RNF0257','RNF0724','RNF0256','RNF0258','RNF1501','RNF1502','RNF1508'}
LENIENT= {'RNF0372','RNF5261','RNF5347','RNF5014','RNF5375','RNF5001','RNF2093','RNF2367',
          'RNF0263','RNF2003','RNF2006','RNF4008','RNF4071','RNF6005','RNF0289','RNF5005',
          'RNF7016','RNF0637','RNF5377','RNF0622','RNF3308'}

def classify(name, codes, tests):
    p = os.path.join(tests, name)
    body = open(p, encoding='utf-8', errors='replace').read().upper() if os.path.exists(p) else ''
    if not codes and 'EXEC SQL' in body:
        return 'SQL precompile'
    if '_ERR' in name.upper() or name.lower().startswith(('test11a','test11b','test11c','test11d','test11e')):
        return 'negative test (rejection expected)'
    cs = set(codes)
    if cs & LENIENT:                  return 'rpgc accepts what IBM rejects'
    if cs & DEP and any(k in body for k in ('DTAARA(','EXTDESC(','DCL-F ','WORKSTN')):
        return 'needs IBM i objects'
    if cs & STRUCT:                   return 'not a valid standalone program'
    return 'other'

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", default="ibmi-conformance-baseline.json")
    ap.add_argument("--tests", default="tests")
    ap.add_argument("--out", default="ibmi-compatibility.md")
    ap.add_argument("--release", default="")
    a = ap.parse_args()

    if not os.path.exists(a.baseline):
        print(f"no baseline at {a.baseline}", file=sys.stderr); return 2
    base = json.load(open(a.baseline))
    files = base["files"]
    acc = [n for n, r in files.items() if r["verdict"] == "accept"]
    rej = [n for n, r in files.items() if r["verdict"] != "accept"]
    total = len(files)

    buckets = collections.Counter(classify(n, files[n]["codes"], a.tests) for n in rej)
    codes = collections.Counter(c for n in rej for c in files[n]["codes"])

    L = []
    title = f"IBM i compatibility — {a.release}" if a.release else "IBM i compatibility"
    L.append(f"# {title}")
    L.append("")
    L.append(f"Every test source compiled by **IBM's own ILE RPG compiler** on IBM i 7.5, "
             f"using `CRTBNDRPG` / `CRTSQLRPGI`. This is the independent check "
             f"on rpgc: `tests/expected_output` is regenerated from rpgc's own output, so "
             f"the local suite can only verify what rpgc already does.")
    L.append("")
    pct = 100.0 * len(acc) / total if total else 0
    L.append(f"**{len(acc)} of {total} sources ({pct:.0f}%) are accepted by IBM's compiler.**")
    L.append("")
    L.append("A rejection is not automatically a defect — negative tests exist to be")
    L.append("rejected, and some sources reference IBM i objects that only exist on a")
    L.append("configured system. Rejections by cause:")
    L.append("")
    L.append("| Cause | Files |")
    L.append("|-------|-------|")
    for k, v in buckets.most_common():
        L.append(f"| {k} | {v} |")
    L.append("")
    if codes:
        L.append("Most frequent IBM diagnostics among rejections:")
        L.append("")
        L.append("| Code | Files |")
        L.append("|------|-------|")
        for c, n in codes.most_common(8):
            L.append(f"| `{c}` | {n} |")
        L.append("")
    L.append(f"<sub>Baseline generated {base.get('generated') or 'unknown'}. "
             f"See `TODO.md` &rarr; \"IBM i Conformance\" for the findings behind each "
             f"category and the current work queue.</sub>")
    txt = "\n".join(L) + "\n"
    open(a.out, "w").write(txt)
    print(txt)
    return 0

if __name__ == "__main__":
    sys.exit(main())
