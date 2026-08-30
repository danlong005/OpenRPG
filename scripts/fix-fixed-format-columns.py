#!/usr/bin/env python3
"""Corrects fixed-format RPG test sources to what IBM's compiler actually requires.

Two transforms, both driven by diagnostics IBM emitted against this corpus:

  1. Right-adjusts numeric column entries (RNF0263).
  2. Supplies the missing Definition-Type entry on standalone D-specs (RNF3703).
  3. Supplies the missing F-spec File-Type and File-Format entries
     (RNF2003 / RNF2006) and right-adjusts the F-spec Record-Length.
  4. Supplies the I-spec Sequence entry and the O-spec record Type entry
     (RNF4008 / RNF6005), which IBM requires and this corpus left blank.

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
import sys, os, glob, argparse

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
            continue
        lines, n_dt = fix_deftype(lines)
        lines, n_fs = fix_fspec_entries(lines)
        lines, n_ri = fix_recid_entries(lines)
        newlines, n, infree = [], n_dt + n_fs + n_ri, False
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
