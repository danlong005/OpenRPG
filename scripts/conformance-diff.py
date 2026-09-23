#!/usr/bin/env python3
"""Detailed listing of where rpgc and IBM's ILE RPG compiler disagree.

Reads the last conformance transcript (IBM's verdict and messages per source)
and the baseline's rpgc verdicts (scripts/conformance-baseline.py rpgc), and
writes a Markdown report of every disagreement:

  - IBM rejects, rpgc accepts: rpgc is more lenient than IBM. Grouped by IBM
    message, with the source line and text for every file, then bucketed the
    way scripts/triage-conformance.py buckets rejections, so real leniency is
    separated from missing IBM i objects and tests that were never valid
    standalone programs.
  - IBM accepts, rpgc rejects: valid RPG that rpgc refuses. Each file is
    recompiled with rpgc here to capture its first error.

Usage:
  scripts/conformance-diff.py [--transcript F] [--baseline F] [--out F]
"""
import argparse, collections, json, os, re, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--transcript", default="ibmi-conformance-transcript.txt")
ap.add_argument("--baseline", default="ibmi-conformance-baseline.json")
ap.add_argument("--tests", default="tests")
ap.add_argument("--rpgc", default="./rpgc")
ap.add_argument("--out", default="ibmi-conformance-differences.md")
a = ap.parse_args()

# ---- IBM: per-file messages from the transcript -----------------------------
# "*RNF7030 30     23 000023  text" (statement, then source line) or, for a
# message tied to a column marker, "*RNF0622 20 a      000004  text" (marker
# letter, then source line, no statement number).
RNF = re.compile(r'^\s*\*?(RN[FS]\d{4})\s+(\d+)\s+(?:[a-z]\s+|\d+\s+)?(?:(\d{6})\s+)?(.*)$')
SQL = re.compile(r'^(SQL\d{4})\s+(\d+)\s+(\d+)\s+(.*)$')
OTHER = re.compile(r'^\s*((?:CP[FD]|MCH)\w{4})[: ]\s*(.*)$')

ibm = {}
cur, buf = None, []
for ln in open(a.transcript, errors="replace").read().split("\n"):
    if ln.startswith("@@@FILE "):
        cur, buf = os.path.basename(ln[8:].strip()), []
    elif ln.startswith("@@@RC ") and cur:
        ibm[cur] = buf
        cur = None
    elif cur is not None:
        buf.append(ln)

def ibm_messages(lines):
    """(code, severity, source line or None, text) for severity >= 20, de-duplicated."""
    seen, out = set(), []
    for ln in lines:
        m = RNF.match(ln)
        if m and int(m.group(2)) >= 20:
            code, sev, seq, text = m.group(1), int(m.group(2)), m.group(3), m.group(4).strip()
            line = int(seq) if seq else None
        else:
            m = SQL.match(ln)
            if m and int(m.group(2)) >= 30:
                code, sev, line, text = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4).strip()
            else:
                m = OTHER.match(ln)
                if not m or m.group(1).startswith("CPF0") and False:
                    continue
                if not m:
                    continue
                code, sev, line, text = m.group(1), 30, None, m.group(2).strip()
        key = (code, line, text)
        if key in seen or not text:
            continue
        seen.add(key)
        out.append((code, sev, line, text))
    # Prefer lines that carry a source line: those are the findings. Message
    # repeats without one (the listing's summary section) add nothing.
    with_line = [m for m in out if m[2] is not None]
    return with_line or out

def source_line(name, n):
    p = os.path.join(a.tests, name)
    if n is None or not os.path.exists(p):
        return ""
    lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
    return lines[n - 1].rstrip() if 0 < n <= len(lines) else ""

# ---- root cause of an IBM rejection -----------------------------------------
# RNF7030 "name not defined" and RNF7503 "operand not defined" are almost
# always consequences: IBM rejected a declaration earlier, and every use of the
# name then fails. The cause is found three ways, in order.
FOLLOW_ON = {"RNF7030", "RNF7503", "RNF7031"}
DECL = re.compile(r'^\s*(DCL-(S|DS|C|PR|PI|F|ENUM)|END-(DS|PR|PI))\b', re.I)

def decl_after_calc(name):
    """Line of the first declaration that follows an executable statement in
    free-form source, or None. IBM (the release verified against) rejects
    this; rpgc accepts declarations anywhere."""
    lines = open(os.path.join(a.tests, name), encoding="utf-8", errors="replace").read().split("\n")
    if not lines or not lines[0].strip().upper().startswith("**FREE"):
        return None
    depth, seen_exec = 0, False
    for i, l in enumerate(lines, 1):
        t = l.strip()
        if not t or t.startswith("//") or t.upper().startswith(("**FREE", "CTL-OPT", "/")):
            continue
        u = t.upper()
        if u.startswith(("DCL-PROC", "END-PROC")):
            return None          # stop at the first procedure: its own scope
        # END-xx first: DECL matches it too, and it must close the group.
        if u.startswith(("END-DS", "END-PR", "END-PI", "END-ENUM")):
            depth = max(0, depth - 1); continue
        if DECL.match(t):
            if seen_exec:
                return i
            if re.match(r'^DCL-(DS|PR|PI|ENUM)\b', u) and not re.search(r'LIKEDS|END-DS', u):
                depth += 1
            continue
        if depth:                # a subfield or parameter line
            continue
        seen_exec = True
    return None

def root_cause(name, ms):
    """(category, detail) for a file IBM rejected."""
    line = decl_after_calc(name)
    if line:
        return ("Declaration after calculations",
                f"line {line}: `{source_line(name, line).strip()[:80]}`")
    for code, sev, ln, text in sorted(ms, key=lambda m: (m[2] or 10**9)):
        if code == "RNF3529":
            return ("PREFIX on a program-described DS (only valid with EXTNAME/LIKEREC)",
                    f"line {ln}: `{source_line(name, ln).strip()[:80]}`")
        src = source_line(name, ln)
        if code == "RNF7030" and ln and re.search(r'DTAARA\(\s*[A-Za-z*]', src, re.I):
            return ("Unquoted data-area name in DTAARA (IBM reads it as a variable holding the name)",
                    f"line {ln}: `{src.strip()[:80]}`")
        if code == "RNF7030" and ln and re.search(r'\bLIKE\(\s*[A-Za-z_]\w*\s*\)', src, re.I):
            return ("LIKE naming a sibling subfield without its DS qualifier",
                    f"line {ln}: `{src.strip()[:80]}`")
        if code == "RNF7030" and ln and re.search(r'[A-Za-z_]\w*\.[A-Za-z_]', src):
            return ("Qualified reference (ds.field) to a DS that is not QUALIFIED",
                    f"line {ln}: `{src.strip()[:80]}`")
    real = [m for m in ms if m[0] not in FOLLOW_ON]
    if real:
        code, sev, ln, text = sorted(real, key=lambda m: (m[2] or 10**9))[0]
        # The category is the rule, not the instance: "Display length 100
        # greater than..." and "...length 60..." are one finding. The file's
        # own values stay in the detail, with its source line.
        rule = re.sub(r'\b\d+\b', 'n', text)
        return (f"{code}: {rule}",
                f"line {ln}: {text} — `{source_line(name, ln).strip()[:80]}`" if ln else text)
    if ms:
        code, sev, ln, text = sorted(ms, key=lambda m: (m[2] or 10**9))[0]
        return (f"Undefined name, cause not reported by IBM ({code})",
                f"line {ln}: {text}" if ln else text)
    return ("Rejected with no diagnostic (return code only)", "")

# ---- rpgc: first error for the files only rpgc rejects ----------------------
def rpgc_error(name):
    src = os.path.join(a.tests, name)
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run([a.rpgc, src, "-o", os.path.join(d, "x")],
                           capture_output=True, text=True, timeout=120)
    text = (r.stderr + r.stdout).strip().split("\n")
    errs = [t for t in text if re.search(r'rror', t) and "error(s) found" not in t]
    return errs[:3] or text[:3]

# ---- triage buckets, as in scripts/triage-conformance.py --------------------
DEP     = {'RNF2120','RNF7030','RNF7503','RNF2121','RNF2109','RNF7080'}
STRUCT  = {'RNF7023','RNF0257','RNF0724','RNF0256','RNF0258','RNF1501','RNF1502','RNF1508','RNF7031'}
LENIENT = {'RNF0372','RNF5261','RNF5347','RNF5014','RNF5375','RNF5001','RNF2093','RNF2367',
           'RNF0263','RNF2003','RNF2006','RNF4008','RNF4071','RNF6005','RNF0289','RNF5005',
           'RNF7016','RNF0637','RNF5377','RNF0622','RNF3308','RNF0592','RNF0597','RNF5343'}

def bucket(name, codes):
    body = open(os.path.join(a.tests, name), encoding="utf-8", errors="replace").read().upper()
    if any(c.startswith("SQL") for c in codes) or (not codes & (DEP | STRUCT | LENIENT) and "EXEC SQL" in body):
        return "E. SQL environment (connection model / precompiler)"
    if codes & LENIENT:
        return "B. rpgc leniency — the work queue"
    if codes & DEP and any(k in body for k in ("DTAARA(", "EXTDESC(", "DCL-F ", "WORKSTN")):
        return "A. needs IBM i objects"
    if codes & STRUCT:
        return "C. not a valid standalone program"
    return "F. needs individual review"

# ---- assemble -------------------------------------------------------------
files = json.load(open(a.baseline))["files"]
quad = collections.defaultdict(list)
for name, rec in sorted(files.items()):
    quad[(rec.get("verdict"), rec.get("rpgc"))].append(name)

lenient = quad[("reject", "accept")]
gaps = quad[("accept", "reject")]
total = len(files)
agree = len(quad[("accept", "accept")]) + len(quad[("reject", "reject")])

out = []
w = out.append
w("# rpgc vs IBM ILE RPG — where the two compilers disagree\n")
w(f"Generated by `scripts/conformance-diff.py` from `{a.transcript}` and `{a.baseline}`.\n")
w("|  | rpgc accepts | rpgc rejects |")
w("|---|---|---|")
w(f"| **IBM accepts** | {len(quad[('accept','accept')])} | {len(gaps)} |")
w(f"| **IBM rejects** | {len(lenient)} | {len(quad[('reject','reject')])} |\n")
w(f"**Agreement: {agree} of {total} ({100*agree/total:.0f}%).** A shared rejection counts as "
  "agreement: it is a negative test working as designed.\n")

# IBM rejects, rpgc accepts -------------------------------------------------
msgs = {n: ibm_messages(ibm.get(n, [])) for n in lenient}
buckets = collections.OrderedDict((k, []) for k in [
    "B. rpgc leniency — the work queue", "A. needs IBM i objects",
    "C. not a valid standalone program", "E. SQL environment (connection model / precompiler)",
    "F. needs individual review"])
for n in lenient:
    buckets[bucket(n, {m[0] for m in msgs[n]})].append(n)

w(f"## IBM rejects, rpgc accepts — {len(lenient)} files\n")
w("rpgc compiles these; IBM's compiler refuses them. Only bucket B is rpgc being "
  "more lenient than RPG; the rest are environment or test-validity causes.\n")
w("| Bucket | Files |")
w("|---|---|")
for k, v in buckets.items():
    w(f"| {k} | {len(v)} |")
w("")

causes = collections.defaultdict(list)
for n in lenient:
    cat, detail = root_cause(n, msgs[n])
    causes[cat].append((n, detail))
w("### By root cause\n")
w("The first cause IBM's listing points at, with follow-on \"not defined\" "
  "messages (RNF7030/RNF7503) traced back to what made the name undefined.\n")
w("| Root cause | Files |")
w("|---|---|")
for cat, ns in sorted(causes.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    w(f"| {cat.replace('|', '/')} | {len(ns)} |")
w("")
for cat, ns in sorted(causes.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    w(f"**{cat}** ({len(ns)})\n")
    for n, detail in ns:
        w(f"- `{n}` — {detail}" if detail else f"- `{n}`")
    w("")

by_code = collections.defaultdict(set)
text_of = {}
for n in lenient:
    for code, sev, line, text in msgs[n]:
        by_code[code].add(n)
        text_of.setdefault(code, text)
w("### By IBM message\n")
w("| Message | Files | IBM's text (first occurrence) |")
w("|---|---|---|")
for code, ns in sorted(by_code.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    w(f"| {code} | {len(ns)} | {text_of[code].replace('|', '/')} |")
w("")

for k, ns in buckets.items():
    if not ns:
        continue
    w(f"### {k} ({len(ns)})\n")
    for n in ns:
        w(f"#### `{n}`\n")
        ms = msgs[n]
        if not ms:
            w("- (IBM gave no severity-20+ message; rejected on return code)\n")
            continue
        for code, sev, line, text in ms[:8]:
            loc = f"line {line}" if line else "—"
            w(f"- **{code}** (sev {sev}, {loc}): {text}")
            src = source_line(n, line)
            if src.strip():
                w(f"  - `{src.strip()[:110]}`")
        if len(ms) > 8:
            w(f"- … and {len(ms) - 8} more")
        w("")

# IBM accepts, rpgc rejects -------------------------------------------------
w(f"## IBM accepts, rpgc rejects — {len(gaps)} files\n")
w("Valid RPG as far as IBM is concerned, refused by rpgc. Some are link-stage "
  "failures of callee modules compiled standalone rather than language gaps.\n")
for n in gaps:
    w(f"#### `{n}`\n")
    for e in rpgc_error(n):
        w(f"- {e.strip()[:200]}")
    w("")

open(a.out, "w").write("\n".join(out) + "\n")
print(f"agreement {agree}/{total}; IBM-only rejections {len(lenient)}, rpgc-only rejections {len(gaps)}")
for k, v in buckets.items():
    print(f"  {k:<55} {len(v):>3}")
print("root causes:")
for cat, ns in sorted(causes.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    print(f"  {len(ns):>3}  {cat[:90]}")
print(f"report written to {a.out}")
