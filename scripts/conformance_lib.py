"""Shared by the IBM i conformance scripts: reading a run's transcript,
extracting IBM's messages for a source, and tracing a rejection to its root
cause. Used by conformance-baseline.py (which stores each rejection's reason
in the baseline), conformance-diff.py and conformance-wiki.py.

Set TESTS to the test-corpus directory before calling anything that reads
source (it defaults to "tests", relative to the repository root).
"""
import os, re

TESTS = "tests"

# ---- IBM: per-file messages from the transcript -----------------------------
# "*RNF7030 30     23 000023  text" (statement, then source line) or, for a
# message tied to a column marker, "*RNF0622 20 a      000004  text" (marker
# letter, then source line, no statement number).
RNF = re.compile(r'^\s*\*?(RN[FS]\d{4})\s+(\d+)\s+(?:[a-z]\s+|\d+\s+)?(?:(\d{6})\s+)?(.*)$')
SQL = re.compile(r'^(SQL\d{4})\s+(\d+)\s+(\d+)\s+(.*)$')
OTHER = re.compile(r'^\s*((?:CP[FD]|MCH)\w{4})[: ]\s*(.*)$')

def load_transcript(path):
    """{source basename: listing lines} for every source the run compiled."""
    ibm, cur, buf = {}, None, []
    for ln in open(path, errors="replace").read().split("\n"):
        if ln.startswith("@@@FILE "):
            cur, buf = os.path.basename(ln[8:].strip()), []
        elif ln.startswith("@@@RC ") and cur:
            ibm[cur] = buf
            cur = None
        elif cur is not None:
            buf.append(ln)
    return ibm

# A long message wraps onto following lines, indented well past the listing's
# line-number column: "*RNF3529 20 a  000008  Keyword is not allowed for a
# program-described data" then "        structure; keyword is ignored."
CONT = re.compile(r'^\s{20,}(\S.*)$')

def ibm_messages(lines):
    """(code, severity, source line or None, text) for severity >= 20,
    de-duplicated, with wrapped message text joined back together."""
    raw, last = [], None
    for ln in lines:
        m = RNF.match(ln)
        if m:
            last = [m.group(1), int(m.group(2)), int(m.group(3)) if m.group(3) else None,
                    m.group(4).strip()]
            raw.append(last); continue
        m = SQL.match(ln)
        if m:
            last = [m.group(1), int(m.group(2)), int(m.group(3)), m.group(4).strip()]
            raw.append(last); continue
        m = OTHER.match(ln)
        if m:
            last = [m.group(1), 30, None, m.group(2).strip()]
            raw.append(last); continue
        c = CONT.match(ln)
        # The listing's own section headings are indented just as deeply:
        # "Message Summary" followed an SQL message and was glued onto it.
        if c and re.match(r'(Message Summary|\* \* \*|Total\b)', c.group(1).strip()):
            c = None
        if c and last is not None and not re.match(r'^\s*\d', ln):
            last[3] = (last[3] + " " + c.group(1).strip()).strip()
            continue
        last = None
    seen, out = set(), []
    for code, sev, line, text in raw:
        # The machine's page-header banner (-=* ... *=-) can land on a
        # wrapped message line; it is not part of IBM's message.
        text = re.sub(r"\s*-=\*.*?\*=-\s*", " ", text).strip()
        if code.startswith("RN") and sev < 20: continue
        if code.startswith("SQL") and sev < 30: continue
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
    p = os.path.join(TESTS, name)
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
    lines = open(os.path.join(TESTS, name), encoding="utf-8", errors="replace").read().split("\n")
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

