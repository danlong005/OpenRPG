#!/usr/bin/env python3
"""Renders the complete IBM i compatibility page.

Output is the whole document, ready to publish: generated statistics from the
baseline plus the authored portability guidance below. Keeping both here means
one command regenerates the page rather than leaving half of it to drift in a
wiki nobody re-checks against the data.

Answers one question for a given release: how much of the test corpus does
IBM's own ILE RPG compiler accept? The raw accepted count alone is misleading,
because a rejection can be the CORRECT outcome -- negative tests exist to be
rejected -- so the summary also breaks the rejections down by cause.

Reads the committed baseline (or a fresh transcript) and writes Markdown.

Usage:
  conformance-summary.py [--baseline F] [--transcript F] [--out F] [--release TAG]
"""
import sys, os, json, glob, argparse, collections, datetime

PORTABILITY = r"""## Portability notes

If you want source that compiles under *both* OpenRPG and IBM ILE RPG, these
are the rules OpenRPG now enforces because IBM does. Each was found by putting
real source through both compilers.

### Fixed-format column rules

- **Numeric entries must be right-adjusted** in their field. `10I0` is wrong;
  `10I 0` is right — the decimal-positions entry lives in columns 41-42 and the
  digit belongs in 42. IBM reports `RNF0263` at severity 20.
- **A standalone field needs `S` in columns 24-25.** A blank definition type
  means *subfield of the enclosing data structure*; with no data structure open,
  IBM rejects it (`RNF3703`).
- **A non-blank definition type ends an open `DS` group.** An `S` field declared
  after a data structure is a new standalone, not another subfield.
- **F-specs need a File-Type (17) and File-Format (22)**, and input/update files
  need a File-Designation (18).
- **Specification order is H, F, D, I, C, O** — output specs come after the
  calculations, not before them.

### Free-format inside fixed-format source

Code in a `/FREE` block must start at **position 8 or later**. Columns 1-5 are
the sequence-number area and 6-7 the form type and comment flag, so a two-space
indent puts your statement in the wrong columns entirely.

`**FREE` is a **file-level** declaration. A `/COPY` member is its own file: if
its content is free-format it needs its own `**FREE` line, even when the file
including it has one.

### Calculation specs

Built-in functions are **expressions**, so they are only legal in *extended*
Factor 2. This is rejected:

```rpg
C     %CHAR(count)  DSPLY
```

Assign to a field first:

```rpg
C                   EVAL      msg = %CHAR(count)
C     msg           DSPLY
```

### Record-level access

On IBM i, `WRITE`, `UPDATE` and `DELETE` against an externally-described file
name the record **format**, not the file:

```rpg
C                   WRITE     CUSTFL146R
```

OpenRPG names the file. Record formats are an IBM i concept: DB2 for i tables
are native file objects carrying a format name, while the SQL databases OpenRPG
runs against — SQLite, PostgreSQL, DB2 LUW — have no such layer, so a format
name would denote nothing.

This is a deliberate boundary rather than a gap. **Display files are the
exception and do use record formats**, because a display file genuinely is a
set of named formats and `EXFMT` must name one:

```rpg
EXFMT MAINMENU;
```

So: database access names the file, display access names the format. Source
doing record-level access on externally-described database files needs the
format name replaced with the file name to move between the two.

### Other limits worth knowing

- **`DSPLY` caps at 52 characters**, enforced at *compile* time against the
  declared length — not the value. A `CHAR(100)` field cannot be displayed even
  if it holds three characters.
- **Object names cap at 10 characters** on IBM i, including data area names.
- **`EXTDESC('name')` is case-sensitive** and IBM i object names are uppercase,
  so a lowercase literal never resolves.

## OpenRPG extensions

Some things OpenRPG accepts are deliberate extensions that IBM will reject.
These are features, not bugs — but source using them is not portable:

- **Free-format without the `**FREE` directive.** OpenRPG detects the format
  from the source; IBM requires the directive.
- **Free-format DDS** for display files (OpenDSPF), where IBM accepts only
  column-based DDS.
"""

DEP    = {'RNF2120','RNF7030','RNF7503','RNF2121','RNF2109','RNF7080'}
STRUCT = {'RNF7023','RNF0257','RNF0724','RNF0256','RNF0258','RNF1501','RNF1502','RNF1508'}
LENIENT= {'RNF0372','RNF5261','RNF5347','RNF5014','RNF5375','RNF5001','RNF2093','RNF2367',
          'RNF0263','RNF2003','RNF2006','RNF4008','RNF4071','RNF6005','RNF0289','RNF5005',
          'RNF7016','RNF0637','RNF5377','RNF0622','RNF3308'}

def classify(name, codes, tests):
    """Why did IBM reject a source that OpenRPG accepted?

    Callers only pass sources OpenRPG ACCEPTED, so there is deliberately no
    "negative test" outcome here: whether a rejection was expected is decided
    by the other compiler's verdict, not by the filename. Three tests named
    *_err were previously miscounted as expected failures when OpenRPG was in
    fact accepting them.
    """
    p = os.path.join(tests, name)
    body = open(p, encoding='utf-8', errors='replace').read().upper() if os.path.exists(p) else ''
    cs = set(codes)
    if not cs and 'EXEC SQL' in body:
        return 'embedded SQL precompile'
    if cs & DEP and any(k in body for k in ('DTAARA(', 'EXTDESC(', 'DCL-F ', 'WORKSTN')):
        return 'references IBM i objects'
    if cs & STRUCT:
        return 'not a standalone program'
    if cs & LENIENT:
        return 'fixed-format or language rule'
    return 'other language difference'

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
    if not any("rpgc" in r for r in files.values()):
        print("baseline has no rpgc verdicts; run: conformance-baseline.py rpgc",
              file=sys.stderr)
        return 2
    total = len(files)

    def ibm(r):  return r["verdict"] == "accept"
    def own(r):  return r.get("rpgc") == "accept"
    both_a = [n for n, r in files.items() if ibm(r) and own(r)]
    both_r = [n for n, r in files.items() if not ibm(r) and not own(r)]
    over   = [n for n, r in files.items() if not ibm(r) and own(r)]
    under  = [n for n, r in files.items() if ibm(r) and not own(r)]
    agree  = len(both_a) + len(both_r)

    # why do the over-acceptances differ? environment or language?
    causes = collections.Counter()
    for n in over:
        causes[classify(n, files[n]["codes"], a.tests)] += 1
    env = (causes["embedded SQL precompile"] + causes["references IBM i objects"]
           + causes["not a standalone program"])
    lang = len(over) - env

    L = []
    title = f"IBM i Compatibility — {a.release}" if a.release else "IBM i Compatibility"
    L += [f"# {title}", ""]
    L += ["Every test source is compiled by **IBM's own ILE RPG compiler** on IBM i 7.5,",
          "and its verdict compared with OpenRPG's. This is the independent check on the",
          "compiler: `tests/expected_output` is regenerated from OpenRPG's own output, so",
          "the local suite can only ever confirm what OpenRPG already does.", ""]
    L += [f"## {100.0*agree/total:.0f}% agreement", ""]
    L += [f"**On {agree} of {total} test sources, OpenRPG and IBM's compiler reach the same",
          f"verdict.** Agreement counts both directions: source both compilers accept, and",
          f"source both compilers reject. A shared rejection is a success — it means",
          f"OpenRPG refuses the same invalid RPG that IBM does.", ""]
    L += ["| | IBM accepts | IBM rejects |",
          "|---|---|---|",
          f"| **OpenRPG accepts** | {len(both_a)} &nbsp;✅ | {len(over)} |",
          f"| **OpenRPG rejects** | {len(under)} | {len(both_r)} &nbsp;✅ |", ""]
    L += [f"- **{len(both_a)}** valid programs both compile.",
          f"- **{len(both_r)}** invalid programs both reject — these are the negative tests,",
          f"  confirmed against a second compiler rather than trusted on their filename.",
          f"- **{len(over)}** OpenRPG accepts and IBM rejects.",
          f"- **{len(under)}** OpenRPG rejects and IBM accepts.", ""]
    L += ["## What the disagreements are", ""]
    L += [f"Not every disagreement is a language difference. Of the {len(over)} sources",
          "OpenRPG accepts and IBM rejects:", ""]
    L += ["| Cause | Files |", "|---|---|"]
    for k, v in causes.most_common():
        L.append(f"| {k} | {v} |")
    L += ["",
          f"**{env}** of those come from the test environment rather than the language:",
          "sources referencing IBM i files and data areas that exist only on a configured",
          "system, fragments that were never standalone programs, and embedded SQL that",
          "fails to precompile because of the verification job's locale. Setting those",
          f"aside, agreement is **{100.0*agree/(total-env):.0f}%** ({agree} of {total-env}).",
          "",
          f"That leaves **{lang + len(under)}** genuine language divergences: {lang} where",
          f"OpenRPG is more permissive than IBM, and {len(under)} where it is stricter.",
          "Both directions are tracked in `TODO.md`.", ""]

    L += ["", PORTABILITY.rstrip(), ""]
    L.append(f"<sub>Baseline generated {base.get('generated') or 'unknown'} against "
             f"IBM i 7.5. This page is generated by "
             f"`scripts/conformance-summary.py`; edit it there, not in the wiki.</sub>")
    txt = "\n".join(L) + "\n"
    open(a.out, "w").write(txt)
    print(txt)
    return 0

if __name__ == "__main__":
    sys.exit(main())
