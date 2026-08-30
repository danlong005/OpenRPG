#!/usr/bin/env bash
# Creates the IBM i objects the test corpus references, so conformance runs
# fail on the LANGUAGE rather than on missing dependencies.
#
# Before this script, 17 files were rejected for reasons that say nothing about
# whether rpgc is compatible with real RPG: RNF2120 "External description not
# found", RNF7030 on data-area names. Those are scaffolding, not findings.
#
# Everything is DERIVED, not hardcoded:
#   - externally-described files come from tests/*.extdesc (those sidecars ARE
#     the schema rpgc itself generated)
#   - program-described file record lengths are read out of the F-specs
#     (positions 7-16 name, 23-27 record length)
#   - data area names and lengths come from the DTAARA() keywords
#
# Two things learned the hard way on PUB400, both encoded below:
#   - RUNSQL gives only "SQL9010 command failed"; RUNSQLSTM with OUTPUT(*PRINT)
#     puts the real SQLnnnn diagnostics on stdout.
#   - DECIMAL(9,2) is a PARSE ERROR on this box. The job is German-locale, so
#     "9,2" lexes as the number 9.2 rather than two arguments. Spaces around
#     the comma -- DECIMAL(9 , 2) -- parse correctly. Do not "tidy" them away.
#
# NOSUCHDA96 is deliberately NOT created: test96_da_status401 asserts the
# data-area-not-found status, so creating it would silently break that test.
#
# Idempotent: drops and recreates, so it can be re-run after schema changes.
set -uo pipefail

USER_ID="${PUB400_USER:-longdm}"
HOST="${PUB400_HOST:-pub400.com}"
PORT="${PUB400_PORT:-2222}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

python3 - "$REPO_ROOT/tests" "$STAGE" <<'PY'
import sys, os, glob, re
tests, stage = sys.argv[1], sys.argv[2]

# ---- externally-described files, from the .extdesc sidecars ---------------
def sqltype(cpp, kind):
    m = re.match(r'std::string\((\d+)\)', cpp)
    # VARCHAR, not CHAR: the .extdesc sidecar records both as std::string(N),
    # but the tests' own EXEC SQL CREATE TABLE declares VARCHAR, and IBM
    # enforces the distinction on a keyed CHAIN (RNF7080 "Factor 1 field is
    # not the same type as first key field"). The sidecar format cannot
    # express the difference -- see TODO.md finding on the descriptor model.
    if m: return f"VARCHAR({m.group(1)})"
    m = re.match(r'double\((\d+):(\d+)\)', cpp)
    # spaces around the comma are REQUIRED -- see header note on decimal comma
    if m: return f"DECIMAL({m.group(1)} , {m.group(2)})"
    if cpp == 'long': return "INTEGER"
    return "CHAR(10)"

ddl = []
for p in sorted(glob.glob(os.path.join(tests, '*.extdesc'))):
    name, cols = None, []
    for ln in open(p, encoding='utf-8', errors='replace'):
        ln = ln.rstrip('\n')
        if ln.startswith('#') or not ln.strip(): continue
        if ln.startswith('table='):
            name = ln.split('=', 1)[1].strip().upper(); continue
        parts = ln.split()
        if len(parts) >= 2:
            cols.append((parts[0].upper(), sqltype(parts[1], parts[2] if len(parts) > 2 else '')))
    if not name or not cols: continue
    defs = [f"{c} {t}" + (" NOT NULL" if i == 0 else "") for i, (c, t) in enumerate(cols)]
    defs.append(f"PRIMARY KEY({cols[0][0]})")   # first column is the key
    # RCDFMT is required: SQL names the record format after the table, and RPG
    # rejects a format whose name matches the file (RNF2121 "already defined" +
    # RNF2109). Record format names cap at 10 chars, so truncate before adding R.
    fmt = (name[:9] + 'R')
    ddl.append(f"DROP TABLE LONGDM1.{name};")
    ddl.append(f"CREATE TABLE LONGDM1.{name} ({', '.join(defs)}) RCDFMT {fmt};")

# CUSTFILE has no sidecar -- test25_dclf declares it purely as a parse stub
ddl.append("DROP TABLE LONGDM1.CUSTFILE;")
ddl.append("CREATE TABLE LONGDM1.CUSTFILE (CUSTNO CHAR(10) NOT NULL, CUSTNAME CHAR(50), PRIMARY KEY(CUSTNO)) RCDFMT CUSTFILER;")
open(os.path.join(stage, 'setup.sql'), 'w').write('\n'.join(ddl) + '\n')

# ---- program-described files, from the F-specs ---------------------------
# fixed-format F-spec: position 6 'F', 7-16 file name, 23-27 record length
pf = {}
for p in glob.glob(os.path.join(tests, '*.rpgle')):
    text = open(p, encoding='utf-8', errors='replace').read()
    # Column 6 is meaningless in free-format, so a line like
    #   MyConfig = 'VERSION=1.0'
    # has 'f' there and parses as an F-spec named "IG = 'VERS". Skip wholly
    # free-format sources and lines inside embedded /FREE blocks.
    first = next((l for l in text.split('\n') if l.strip()), '')
    if first.strip().upper().startswith('**FREE'): continue
    infree = False
    for ln in text.split('\n'):
        u = ln.strip().upper()
        if u.startswith('/FREE'): infree = True; continue
        if u.startswith('/END-FREE'): infree = False; continue
        if infree: continue
        r = ln.rstrip('\n').ljust(100)
        if r[5:6].upper() != 'F' or r[6:7] == '*': continue
        nm, rl = r[6:16].strip().upper(), r[22:27].strip()
        # a real object name: letters/digits, max 10, and a usable record length
        if nm and rl.isdigit() and int(rl) > 0 and re.fullmatch(r'[A-Z][A-Z0-9_#$@]{0,9}', nm):
            pf[nm] = int(rl)

# ---- data areas, from DTAARA() keywords ----------------------------------
da = {}
for p in glob.glob(os.path.join(tests, '*.rpgle')) + glob.glob(os.path.join(tests, '*.sqlrpgle')):
    txt = open(p, encoding='utf-8', errors='replace').read()
    for m in re.finditer(r'DCL-S\s+\w+\s+CHAR\((\d+)\)\s+DTAARA\((\w+)\)', txt, re.I):
        ln_, nm = int(m.group(1)), m.group(2).upper()
        if nm.startswith('*'): continue
        da[nm] = max(da.get(nm, 0), ln_)
# test96 asserts the not-found status; creating this would break it
da.pop('NOSUCHDA96', None)

cl = []
for nm, rl in sorted(pf.items()):
    cl.append(f"DLTF FILE(LONGDM1/{nm})")
    cl.append(f"CRTPF FILE(LONGDM1/{nm}) RCDLEN({rl})")
too_long = sorted(n for n in da if len(n) > 10)   # IBM i object names cap at 10
for nm, ln_ in sorted(da.items()):
    if len(nm) > 10: continue
    cl.append(f"DLTDTAARA DTAARA(LONGDM1/{nm})")
    cl.append(f"CRTDTAARA DTAARA(LONGDM1/{nm}) TYPE(*CHAR) LEN({ln_}) VALUE('X')")
cl.append("DLTF FILE(LONGDM1/RPTFILE)")
cl.append("CRTPRTF FILE(LONGDM1/RPTFILE)")
open(os.path.join(stage, 'setup.cl'), 'w').write('\n'.join(cl) + '\n')

print(f"  tables      : {len([l for l in ddl if l.startswith('CREATE')])}")
print(f"  program PFs : {len(pf)}  {sorted(pf.items())}")
print(f"  data areas  : {len([n for n in da if len(n) <= 10])}  "
      f"{sorted((n, l) for n, l in da.items() if len(n) <= 10)}   (NOSUCHDA96 deliberately omitted)")
if too_long:
    print(f"  SKIPPED (name > 10 chars, cannot exist on IBM i -- FINDING): {too_long}")
PY
[ $? -eq 0 ] || { echo "generation failed" >&2; exit 1; }

cat > "$STAGE/setup_remote.sh" <<'REMOTE'
PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/usr/bin:$PATH
export PATH
SYS=/QOpenSys/usr/bin/system
W="$HOME/rpgc-setup"
setccsid 819 "$W/setup.sql" </dev/null >/dev/null 2>&1

echo "=== tables (RUNSQLSTM) ==="
out=$("$SYS" "RUNSQLSTM SRCSTMF('$W/setup.sql') COMMIT(*NONE) ERRLVL(30) OUTPUT(*PRINT)" </dev/null 2>&1)
# SQL0204 (drop of a nonexistent table) and SQL7905 (created, not journaled)
# are expected noise on a clean or re-run; anything else is worth seeing.
echo "$out" | grep -E 'SQL[0-9]{4}' | grep -vE 'SQL0204|SQL7905' | head -12
echo "  created: $(echo "$out" | grep -c 'SQL7905') table(s)"
if echo "$out" | grep -qE 'SQL9010'; then
    echo "  RUNSQLSTM reported failure; diagnostics:"
    echo "$out" | grep -E 'SQL[0-9]{4}' | grep -vE 'SQL0204|SQL7905' | head -8 | sed 's/^/     /'
fi

echo "=== program-described files, data areas, printer file ==="
while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    out=$("$SYS" "$cmd" </dev/null 2>&1); rc=$?
    case "$cmd" in
      DLT*) : ;;                                   # deleting a nonexistent object is fine
      *) if [ $rc -eq 0 ]; then echo "  ok   $cmd"
         else echo "  FAIL $cmd"; echo "$out" | head -2 | sed 's/^/         /'; fi ;;
    esac
done < "$W/setup.cl"
REMOTE

echo
echo "uploading and creating objects on ${USER_ID}@${HOST}..."
SSH=(-p "$PORT" -o BatchMode=yes)
ssh "${SSH[@]}" "${USER_ID}@${HOST}" "mkdir -p rpgc-setup" </dev/null || exit 1
scp -q -P "$PORT" -o BatchMode=yes "$STAGE/setup.sql" "$STAGE/setup.cl" "$STAGE/setup_remote.sh" \
    "${USER_ID}@${HOST}:rpgc-setup/" || exit 1
ssh "${SSH[@]}" "${USER_ID}@${HOST}" 'sh $HOME/rpgc-setup/setup_remote.sh' </dev/null 2>&1 \
  | grep -v 'WELCOME\|access is logged\|be polite\|other users\|limited support\|see https\|Enter your password\|^\*\*\*\|^\* '
