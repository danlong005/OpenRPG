#!/usr/bin/env python3
"""Corrects fixed-format RPG test sources to what IBM's compiler actually requires.

Two transforms, both driven by diagnostics IBM emitted against this corpus:

  1. Right-adjusts numeric column entries (RNF0263).
  2. Supplies the missing Definition-Type entry on standalone D-specs (RNF3703).
  3. Supplies the missing F-spec File-Type and File-Format entries
     (RNF2003 / RNF2006) and right-adjusts the F-spec Record-Length.
  4. Supplies the I-spec Sequence entry and the O-spec record Type entry
     (RNF4008 / RNF6005), which IBM requires and this corpus left blank.
  5. Shifts /FREE block bodies into the positions 8-80 code area (RNF0257).
  6. Reorders specifications into IBM's required sequence: O-specs last, and
     main-procedure calculations before subprocedure definitions (RNF0257 /
     RNF0256).
  7. Lifts built-in functions out of traditional-syntax C-spec factors into a
     preceding EVAL (RNF0372).

IBM's ILE RPG compiler requires numeric entries in fixed-format specifications
to be right-adjusted within their column range, and reports RNF0263 ("Entry not
right-adjusted") at *severity 20* when they are not -- the program is not
created. rpgc never noticed because fixed_columns.h's extractCol() trims both
ends of every field, so "0 " and " 0" are indistinguishable to it. The corpus
accumulated 89 malformed D-specs across 67 files as a result.

The column ranges below are taken from src/fixed_columns.h, which is itself
verified line-by-line against IBM SC09-2508. The specific fields corrected here
were not guessed: they are exactly the ones the IBM compiler's own caret lines
pointed at in ibmi-conformance-transcript.txt.

Only entries that are entirely digits are touched, and only within their own
field width -- every other column on the line is preserved byte for byte.

Usage:
  scripts/fix-fixed-format-columns.py --dry-run tests/
  scripts/fix-fixed-format-columns.py tests/
"""
import sys, os, glob, argparse, re

# (start, end) 1-based inclusive, matching src/fixed_columns.h
DSPEC = [("FromPos", 26, 32), ("ToLen", 33, 39), ("Decimals", 41, 42)]
DEFTYPE = (24, 25)   # D-spec Definition-Type: blank/S/C/DS/PR/PI, LEFT-adjusted
ISPEC = [("FromPos", 37, 41), ("ToPos", 42, 46), ("Decimals", 47, 48)]
OSPEC = [("EndPos", 47, 51)]
FSPEC = [("RecordLen", 23, 27), ("KeyFieldLen", 29, 33)]
# I-spec record-identification lines carry three code-set position entries
ISPEC_RECID = [("Set1Position", 23, 27), ("Set2Position", 31, 35), ("Set3Position", 39, 43)]

def get(line, s, e):
    """1-based inclusive slice of a line padded to 100 columns."""
    return line.ljust(100)[s-1:e]

def put(line, s, e, value):
    r = line.ljust(100)
    return (r[:s-1] + value.rjust(e - s + 1) + r[e:]).rstrip()

def is_free_format(text):
    """True for a wholly free-format source (**FREE on the first substantive line).

    Column position 6 carries no meaning in free-format, so a line whose 6th
    character happens to be D, I or O would otherwise be mangled -- a `//` comment
    mentioning "dspfc" is enough to look like a D-spec.
    """
    for ln in text.split("\n"):
        if ln.strip():
            return ln.strip().upper().startswith("**FREE")
    return False


def fields_for(line):
    """Which numeric fields apply to this line, or None to skip it."""
    if len(line) < 6:
        return None
    spec = line[5:6].upper()
    if get(line, 7, 7) == '*':          # position 7 '*' = comment line
        return None
    if spec == 'D':
        return DSPEC
    # I- and O-specs each have two line shapes. Record-identification lines
    # carry the file name in 7-16 and use those same columns for entirely
    # different purposes (record-ID codes, space/skip); only field-description
    # lines, which leave 7-16 blank, have the numeric fields below.
    if spec in ('I', 'O') and get(line, 7, 16).strip() == '':
        return ISPEC if spec == 'I' else OSPEC
    # I-spec record-identification lines DO carry a file name in 7-16, and use
    # those same columns for record-ID code sets rather than field locations.
    if spec == 'I':
        return ISPEC_RECID
    if spec == 'F':
        return FSPEC
    return None

def fix_line(line):
    specs = fields_for(line)
    if not specs:
        return line, []
    changes, out = [], line
    for name, s, e in specs:
        raw = get(out, s, e)
        val = raw.strip()
        if not val or not val.isdigit():
            continue                    # only numeric entries are adjusted
        if raw == val.rjust(e - s + 1):
            continue                    # already right-adjusted
        out = put(out, s, e, val)
        changes.append(f"{name}({s}-{e}): {raw!r} -> {val.rjust(e-s+1)!r}")
    return out, changes

def fixed_only(lines):
    """Yields (index, line) for genuine fixed-format lines only.

    Column 6 carries no meaning inside a /FREE block, so a line such as
    "  record.id = 1;" has 'o' there and looks exactly like an O-spec. Every
    transform must skip those; centralised here because getting it wrong
    silently corrupts source (it has happened three times during development).
    """
    infree = False
    for i, ln in enumerate(lines):
        u = ln.strip().upper()
        if u.startswith('/FREE'):     infree = True;  continue
        if u.startswith('/END-FREE'): infree = False; continue
        if infree: continue
        yield i, ln


def fix_deftype(lines):
    """Adds 'S' to standalone D-specs whose Definition-Type (24-25) is blank.

    IBM reads a blank definition type as "subfield of the enclosing data
    structure"; with no enclosing group that is RNF3703 at severity 20. rpgc
    infers "standalone" instead, so 94 such declarations accumulated unnoticed.

    Blank IS correct for a real subfield, so group state is tracked: DS/PR/PI
    open a group, any other non-blank definition type closes it, and so does
    any non-D specification. Lines inside a group are left alone.
    """
    out, changes, grouped, infree = [], 0, False, False
    for ln in lines:
        u = ln.strip().upper()
        if u.startswith("/FREE"):
            infree = True; out.append(ln); continue
        if u.startswith("/END-FREE"):
            infree = False; out.append(ln); continue
        if infree:
            out.append(ln); continue
        if len(ln) < 6:
            out.append(ln); continue
        spec = ln[5:6].upper()
        if spec != 'D':
            if spec in 'HFICOP':
                grouped = False
            out.append(ln); continue
        if get(ln, 7, 7) == '*':
            out.append(ln); continue
        dt = get(ln, DEFTYPE[0], DEFTYPE[1]).strip().upper()
        if dt:
            grouped = dt in ('DS', 'PR', 'PI')
            out.append(ln); continue
        if grouped:
            out.append(ln); continue        # legitimate subfield -- leave it
        r = ln.ljust(100)
        out.append((r[:DEFTYPE[0]-1] + 'S ' + r[DEFTYPE[1]:]).rstrip())
        changes += 1
    return out, changes


def fix_fspec_entries(lines):
    """Supplies the F-spec File-Type (17), File-Designation (18) and
    File-Format (22) entries that IBM requires and this corpus omits.

    IBM rejects a blank File-Type with RNF2003, a blank File-Format with
    RNF2006, and a blank File-Designation on an input/update/combined file
    with RNF2093 -- all at severity 20. None of the values are arbitrary:

      File-Type, when position 17 is blank, from what the source does:
        I-specs only        -> I (input)
        O-specs only        -> O (output)
        both                -> U (update), plus A (add) in position 20 so a
                               WRITE of a new record is legal
      File-Designation: F (full procedural) for I/U/C -- these programs drive
        I/O with explicit opcodes rather than the RPG cycle. MUST stay blank
        for an output file.
      File-Format: F (program-described) whenever the F-spec carries a record
        length, which is what makes it program-described.

    A file whose File-Type is already present still gets its designation
    filled, so externally-described F-specs (EXTDESC, no I/O-specs) are
    covered too.
    """
    has_i = any(len(l) > 5 and l[5:6].upper() == 'I' for _, l in fixed_only(lines))
    has_o = any(len(l) > 5 and l[5:6].upper() == 'O' for _, l in fixed_only(lines))
    if has_i and has_o:   derived, add = 'U', 'A'
    elif has_o:           derived, add = 'O', ' '
    elif has_i:           derived, add = 'I', ' '
    else:                 derived, add = '',  ' '

    out, changes = list(lines), 0
    for i, ln in fixed_only(lines):
        if len(ln) < 6 or ln[5:6].upper() != 'F' or get(ln, 7, 7) == '*' \
           or not get(ln, 7, 16).strip():
            continue
        r = list(ln.ljust(100))
        before = ''.join(r).rstrip()
        ftype = get(ln, 17, 17).strip().upper() or derived
        if not ftype:
            continue                       # nothing to infer from; leave alone
        if not get(ln, 17, 17).strip():
            r[16] = ftype
        if not get(ln, 18, 18).strip():
            r[17] = ' ' if ftype == 'O' else 'F'
        if add != ' ' and ftype == 'U' and not get(ln, 20, 20).strip():
            r[19] = add
        if not get(ln, 22, 22).strip() and get(ln, 23, 27).strip():
            r[21] = 'F'
        after = ''.join(r).rstrip()
        if after != before: changes += 1
        out[i] = after
    return out, changes


def fix_recid_entries(lines):
    """Supplies I-spec Sequence (17-18) and O-spec record Type (17).

    IBM requires both and reports RNF4008 / RNF6005 at severity 20 when they
    are blank. The values chosen are the ones that mean "ordinary": an
    ALPHABETIC sequence entry means no sequence checking, and 'D' is a detail
    record -- precisely the semantics rpgc implements. The numeric-sequence and
    H/T/E record types, which need machinery rpgc lacks, are left alone.

    Only record-identification / record lines carry these; they are the ones
    with a file name in positions 7-16.
    """
    out, changes = list(lines), 0
    for i, ln in fixed_only(lines):
        if len(ln) < 6 or get(ln, 7, 7) == '*' or not get(ln, 7, 16).strip():
            continue
        spec = ln[5:6].upper()
        r = list(ln.ljust(100))
        before = ''.join(r).rstrip()
        if spec == 'I' and not get(ln, 17, 18).strip():
            r[16], r[17] = 'A', 'A'
        elif spec == 'O' and not get(ln, 17, 17).strip():
            r[16] = 'D'
        after = ''.join(r).rstrip()
        if after != before: changes += 1
        out[i] = after
    return out, changes


def fix_free_block_indent(lines):
    """Shifts /FREE block bodies so code starts at position 8.

    Inside a fixed-format source, positions 1-5 are the sequence-number area
    and 6-7 are the form type and comment flag; free-format code lives in
    8-80. This corpus indents /FREE bodies by two spaces, so "  NAME = 'x';"
    puts NAM in the sequence area and E in the form-type column -- IBM reads
    it as a malformed specification and reports RNF0257 ("Form-Type entry for
    main procedure not valid or out of sequence") at severity 30.

    The whole block is shifted by one amount so relative indentation (nested
    IF/DO bodies) is preserved. Blocks already at or past position 8 are left
    alone. Verified against the corpus: the longest resulting line is 62
    columns, well inside the 80-column limit.
    """
    out = list(lines)
    infree, block_idx = False, []
    total = 0

    def flush(idxs):
        nonlocal total
        body = [out[i] for i in idxs if out[i].strip()]
        if not body: return
        shift = max(0, 7 - min(len(l) - len(l.lstrip()) for l in body))
        if not shift: return
        for i in idxs:
            if out[i].strip():
                out[i] = ' ' * shift + out[i]
                total += 1

    for i, ln in enumerate(lines):
        u = ln.strip().upper()
        if u.startswith('/FREE'):
            infree, block_idx = True, []; continue
        if u.startswith('/END-FREE'):
            if infree: flush(block_idx)
            infree, block_idx = False, []; continue
        if infree: block_idx.append(i)
    if infree: flush(block_idx)
    return out, total


def fix_ospec_order(lines):
    """Moves O-specs after the calculations.

    RPG requires specifications in H, F, D, I, C, O order. This corpus places
    the O-specs immediately after the I-specs, ahead of the calculations, so
    IBM reports RNF0257 ("Form-Type entry ... out of sequence") and then cannot
    work out how the program ends (RNF7023) because the trailing C-specs are
    misparsed. Only the relative position changes; the O-specs keep their own
    order.
    """
    idx = [i for i, l in fixed_only(lines)
           if len(l) > 5 and l[5:6].upper() == 'O' and get(l, 7, 7) != '*']
    if not idx: return lines, 0
    calc = [i for i, l in fixed_only(lines)
            if len(l) > 5 and l[5:6].upper() == 'C' and get(l, 7, 7) != '*']
    free_end = [i for i, l in enumerate(lines) if l.strip().upper().startswith('/END-FREE')]
    last_calc = max(calc + free_end) if (calc or free_end) else -1
    if last_calc < 0 or max(idx) > last_calc:
        return lines, 0                      # already after the calculations
    ospecs = [lines[i] for i in idx]
    out = [l for i, l in enumerate(lines) if i not in set(idx)]
    shift = sum(1 for i in idx if i < last_calc)
    at = last_calc - shift + 1
    return out[:at] + ospecs + out[at:], len(ospecs)


def fix_proc_order(lines):
    """Moves main-procedure calculations ahead of subprocedure definitions.

    In RPG the cycle-main calculations must precede any DCL-PROC; statements
    that follow END-PROC are "between procedures" and IBM rejects them with
    RNF0256 at severity 30, then reports RNF7023 because it can no longer see
    how the main procedure ends. Declarations (DCL-PR prototypes and the like)
    may legitimately stay where they are -- only executable lines move.
    """
    up = [l.strip().upper() for l in lines]
    first_proc = next((i for i, u in enumerate(up) if u.startswith('DCL-PROC')), None)
    last_end   = next((i for i in range(len(up) - 1, -1, -1) if up[i].startswith('END-PROC')), None)
    if first_proc is None or last_end is None or last_end < first_proc:
        return lines, 0
    tail = list(range(last_end + 1, len(lines)))
    movable = [i for i in tail
               if lines[i].strip() and not lines[i].strip().startswith('//')
               and not lines[i].strip().startswith('/')          # compiler directives stay put
               and not up[i].startswith(('DCL-PR', 'DCL-DS', 'DCL-S', 'DCL-C', 'END-'))]
    if not movable: return lines, 0
    block = [lines[i] for i in range(min(movable), len(lines))]
    rest  = lines[:first_proc]
    procs = lines[first_proc:min(movable)]
    return rest + block + procs, len(movable)


BIF_RE = re.compile(r"%[A-Za-z]")
TMP = "TMPDSP"          # verified absent from the corpus before adoption

def fix_bif_in_factor(lines, declare=True):
    """Lifts a built-in out of DSPLY's Factor 1 into a preceding EVAL.

    Traditional-syntax factors take a field, literal or constant -- never an
    expression -- so IBM rejects `C  %CHAR(n)  DSPLY` with RNF0372 at severity
    20. Confirmed on IBM i 7.5: the same built-in in EXTENDED Factor 2 (EVAL)
    compiles, which is what makes this rewrite the right shape:

        C     %CHAR(n)      DSPLY
    becomes
        C                   EVAL      TMPDSP = %CHAR(n)
        C     TMPDSP        DSPLY

    `declare` is False for copybook fragments: they are spliced into a parent
    that declares the work field itself, and a second declaration would be a
    redefinition.

    A single CHAR(52) work field per file suffices: every built-in used in the
    corpus (%CHAR, %TRIM) returns character, and DSPLY caps at 52 characters
    anyway. None of the affected sites carries a conditioning indicator, so
    there is no condition to duplicate onto the EVAL -- the transform bails out
    if that ever stops being true.
    """
    sites = []
    infree = False
    for i, ln in enumerate(lines):
        u = ln.strip().upper()
        if u.startswith('/FREE'): infree = True; continue
        if u.startswith('/END-FREE'): infree = False; continue
        if infree or len(ln) < 6 or ln[5:6].upper() != 'C' or get(ln, 7, 7) == '*':
            continue
        r = ln.ljust(100)
        if r[25:35].strip().upper() != 'DSPLY': continue
        f1 = r[11:25].strip()
        if not BIF_RE.search(f1): continue
        if r[6:11].strip():
            return lines, 0          # conditioning indicator: needs a human
        sites.append((i, f1))
    if not sites: return lines, 0

    def cline(f1, op, rest=""):
        r = [' '] * 80
        r[5] = 'C'
        for k, c in enumerate(f1):   r[11 + k] = c
        for k, c in enumerate(op):   r[25 + k] = c
        for k, c in enumerate(rest): r[35 + k] = c
        return ''.join(r).rstrip()

    out = []
    repl = dict(sites)
    for i, ln in enumerate(lines):
        if i in repl:
            out.append(cline("", "EVAL", f"{TMP} = {repl[i]}"))
            out.append(cline(TMP, "DSPLY"))
        else:
            out.append(ln)

    if not declare:
        return out, len(sites)
    # declare the work field after the last D-spec, or before the first C-spec
    dspec = [i for i, l in enumerate(out)
             if len(l) > 5 and l[5:6].upper() == 'D' and get(l, 7, 7) != '*']
    if dspec:
        at = max(dspec) + 1
    else:
        cs = [i for i, l in enumerate(out) if len(l) > 5 and l[5:6].upper() in 'CIO']
        at = min(cs) if cs else len(out)
    decl = [' '] * 80
    decl[5] = 'D'
    for k, c in enumerate(TMP):  decl[6 + k] = c
    decl[23] = 'S'
    for k, c in enumerate("52"): decl[37 + k] = c
    decl[39] = 'A'
    out.insert(at, ''.join(decl).rstrip())
    return out, len(sites)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", help="directory of .rpgle/.sqlrpgle sources")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--show", type=int, default=6, help="example lines to print")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.target, "*.rpgle")) +
                   glob.glob(os.path.join(a.target, "*.sqlrpgle")))
    total_lines, total_files, shown = 0, 0, 0
    for p in files:
        text = open(p, encoding="utf-8", errors="surrogateescape").read()
        nl = "\r\n" if "\r\n" in text else "\n"
        lines = text.split(nl)
        if is_free_format(text):
            # Wholly free-format: no column rules apply, but IBM still requires
            # main-procedure calculations before any subprocedure definition.
            lines, n_po = fix_proc_order(lines)
            if n_po and not a.dry_run:
                open(p, "w", encoding="utf-8", errors="surrogateescape").write(nl.join(lines))
            if n_po:
                total_files += 1; total_lines += n_po
            continue
        lines, n_dt = fix_deftype(lines)
        lines, n_fs = fix_fspec_entries(lines)
        lines, n_ri = fix_recid_entries(lines)
        lines, n_fb = fix_free_block_indent(lines)
        lines, n_oo = fix_ospec_order(lines)
        lines, n_bf = fix_bif_in_factor(
            lines, declare='copybook' not in os.path.basename(p).lower())
        newlines, n, infree = [], n_dt + n_fs + n_ri + n_fb + n_oo + n_bf, False
        for ln in lines:
            u = ln.strip().upper()
            # a mixed source embeds free-format between /FREE and /END-FREE;
            # those lines are not column-positional either
            if u.startswith("/FREE"):
                infree = True
            elif u.startswith("/END-FREE"):
                infree = False
            if infree or u.startswith("/FREE") or u.startswith("/END-FREE"):
                newlines.append(ln)
                continue
            fixed, changes = fix_line(ln)
            if changes:
                n += 1
                if shown < a.show:
                    shown += 1
                    print(f"{os.path.basename(p)}")
                    print(f"  before: {ln!r}")
                    print(f"  after : {fixed!r}")
                    for c in changes:
                        print(f"          {c}")
            newlines.append(fixed)
        if n:
            total_files += 1
            total_lines += n
            if not a.dry_run:
                open(p, "w", encoding="utf-8", errors="surrogateescape").write(nl.join(newlines))
    verb = "would fix" if a.dry_run else "fixed"
    print(f"\n{verb} {total_lines} lines across {total_files} files "
          f"(of {len(files)} scanned)")

if __name__ == "__main__":
    main()
