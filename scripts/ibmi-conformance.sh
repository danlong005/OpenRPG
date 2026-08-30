#!/usr/bin/env bash
# Compiles OpenRPG's entire test corpus on a real IBM i and reports, per file,
# whether IBM's ILE RPG compiler accepts it -- turning "which of our tests are
# actually valid RPG?" from an assumption into a categorized inventory.
#
# Acceptance only: OPTION(*NOGEN) syntax- and semantic-checks without generating
# a program object, so nothing is created, nothing needs deleting, and no
# storage is consumed on a shared box. Execution is a separate exercise (it
# needs a DSPLY->printf transform; see scripts/ibmi-probe.sh and the notes in
# memory), and is deliberately not attempted here.
#
# The parameters below were established empirically by ibmi-probe.sh; each one
# is load-bearing and none of them is guessable:
#   - source must be tagged CCSID 819 (UTF-8/1208 fails RNS9339 "unable to open")
#   - TGTCCSID(*JOB) or literals containing [ ] { } ! come out as umlauts
#   - compile into the library named by the profile's "Current library"
#     (LONGDM1, not LONGDM); CRTLIB is not authorized on PUB400
#   - listings arrive on stdout, so diagnostics need no spool retrieval
#
# Usage:
#   scripts/ibmi-conformance.sh                 # whole corpus, refresh baseline
#   scripts/ibmi-conformance.sh --changed-only  # only sources whose hash moved
#   scripts/ibmi-conformance.sh --limit 20      # smoke run, first 20 files
#   scripts/ibmi-conformance.sh --no-baseline   # leave the baseline alone
#   PUB400_USER=longdm scripts/ibmi-conformance.sh
#
# The run refreshes ibmi-conformance-baseline.json and FAILS on a regression:
# a source IBM accepted before and rejects now. The absolute accepted count is
# deliberately NOT a gate -- it conflates unrelated causes (see TODO.md's
# bucket triage). For a network-free check on every push, use
# scripts/conformance-baseline.py check.
#
# Load discipline: PUB400 is a free community box. This is a manual/weekly job,
# not a per-PR gate, and it runs serially on purpose.
set -uo pipefail

USER_ID="${PUB400_USER:-}"
HOST="${PUB400_HOST:-pub400.com}"
PORT="${PUB400_PORT:-2222}"
LIMIT=0
CHANGED_ONLY=0
UPDATE_BASELINE=1
BASELINE="ibmi-conformance-baseline.json"
while [ $# -gt 0 ]; do
    case "$1" in
        --limit) LIMIT="${2:-0}"; shift 2 ;;
        --changed-only) CHANGED_ONLY=1; shift ;;
        --no-baseline) UPDATE_BASELINE=0; shift ;;
        --baseline) BASELINE="${2}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$USER_ID" ]; then printf 'IBM i user profile: '; read -r USER_ID; fi
[ -z "$USER_ID" ] && { echo "error: no user profile given" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDIR="$REPO_ROOT/tests"
[ -d "$TESTDIR" ] || { echo "error: no $TESTDIR" >&2; exit 2; }

STAGE="$(mktemp -d)"
CTL="$HOME/.ssh/cm-ibmi-conf-%C"
LOG="$REPO_ROOT/ibmi-conformance-transcript.txt"
cleanup() {
    ssh -O exit -o ControlPath="$CTL" -p "$PORT" "${USER_ID}@${HOST}" 2>/dev/null
    rm -rf "$STAGE"
}
trap cleanup EXIT
SSH_OPTS=(-p "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=300)
SCP_OPTS=(-P "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=300)

WORKDIR="rpgc-conf"

# ---- stage sources -------------------------------------------------------
# Preserve the tests/ prefix: the corpus uses path-style /COPY directives
# ("/COPY tests/copybook1.rpgle"), so the remote compile passes INCDIR pointing
# at the parent and the relative path has a chance to resolve.
mkdir -p "$STAGE/pkg/tests"
if [ "$CHANGED_ONLY" = "1" ]; then
    CONF_ONLY="$(python3 "$REPO_ROOT/scripts/conformance-baseline.py" changed \
                    --baseline "$REPO_ROOT/$BASELINE" --tests "$TESTDIR")"
    export CONF_ONLY
    if [ -z "$CONF_ONLY" ]; then
        echo "no sources changed since the verified baseline; nothing to send"
        exit 0
    fi
    echo "changed since baseline: $(echo "$CONF_ONLY" | wc -l | tr -d ' ') source(s)"
fi
python3 - "$TESTDIR" "$STAGE/pkg/tests" "$LIMIT" <<'PY'
import sys, os, glob, re
src, dst, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
# U+2014 and friends have no Latin-1 code point and cannot survive the CCSID 819
# tag the compiler requires, so they are folded to ASCII before upload. They
# appear only in comments; the count is reported so the transform stays visible.
SUBS = {'—':'-', '–':'-', '‘':"'", '’':"'",
        '“':'"', '”':'"', '…':'...', ' ':' '}
files = sorted(glob.glob(os.path.join(src,'*.rpgle')) + glob.glob(os.path.join(src,'*.sqlrpgle')))
# copybook fragments are includes, not programs -- they are uploaded so /COPY can
# find them, but they are not compiled standalone.
def is_copybook(p): return 'copybook' in os.path.basename(p).lower()
compiled, changed = [], 0
for p in files:
    t = open(p, encoding='utf-8', errors='replace').read()
    o = t
    for k,v in SUBS.items(): t = t.replace(k,v)
    t = t.encode('ascii', errors='replace').decode('ascii')
    if t != o: changed += 1
    open(os.path.join(dst, os.path.basename(p)),'w').write(t)
    if not is_copybook(p): compiled.append(os.path.basename(p))
if limit > 0: compiled = compiled[:limit]
only = os.environ.get("CONF_ONLY")
if only is not None:
    keep = {l.strip() for l in only.split(chr(10)) if l.strip()}
    compiled = [c for c in compiled if c in keep]
open(os.path.join(dst,'MANIFEST'),'w').write('\n'.join(compiled)+'\n')
print(f"staged {len(files)} sources ({changed} had non-ASCII folded to ASCII)")
print(f"will compile {len(compiled)} (copybook fragments excluded)")
PY
[ $? -eq 0 ] || { echo "staging failed" >&2; exit 1; }

( cd "$STAGE/pkg" && tar cf - tests ) | gzip -9 > "$STAGE/corpus.tar.gz"
echo "package: $(wc -c < "$STAGE/corpus.tar.gz" | tr -d ' ') bytes"

# ---- remote driver -------------------------------------------------------
# Quoted heredoc: nothing is interpolated locally, so there is no $-escaping to
# get wrong. Everything user-specific is discovered on the far side.
cat > "$STAGE/conf_remote.sh" <<'REMOTE_EOF'
PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/usr/bin:$PATH
export PATH
SYS=/QOpenSys/usr/bin/system
WORK="$HOME/rpgc-conf"
ME=$(whoami | tr 'a-z' 'A-Z')

cd "$WORK" || exit 1
gzip -dc corpus.tar.gz | tar xf - || exit 1

LIB=$($SYS "DSPUSRPRF USRPRF($ME) OUTPUT(*PRINT)" </dev/null 2>&1 \
        | grep -i 'Current library' | awk '{print $NF}' | tr -d '\r')
[ -z "$LIB" ] && LIB="${ME}1"
echo "@@@LIB $LIB"

# CRTBNDRPG cannot open a 1208 stream file; 819 is required.
for f in tests/*.rpgle tests/*.sqlrpgle; do
    [ -f "$f" ] && setccsid 819 "$f" </dev/null >/dev/null 2>&1
done

# Keep only verdict-bearing lines for a clean compile. Message lines sit at the
# margin (RNS9304:) or start with a severity marker (*RNF7016 20 ...); source
# listing lines begin with a line number, so anchoring stops a diagnostic id
# quoted inside a source comment from matching itself. The severity totals are
# the authoritative accept/reject signal.
verdict() { grep -E '^ *\*?RN[SF][0-9]{4}|^ +(Error|Severe Error|Warning|Information) ' ; }

while IFS= read -r f; do
    [ -z "$f" ] && continue
    src="$WORK/tests/$f"
    echo "@@@FILE $f"
    # Route by CONTENT, not extension: several .rpgle files carry embedded
    # EXEC SQL and must go through the SQL precompiler too. Routing on the
    # filename made CRTBNDRPG parse "EXEC SQL ..." as an EVAL statement
    # (RNF5347 "assignment operator is expected"), which looked like a language
    # finding and was purely a harness bug.
    if grep -iE 'EXEC +SQL' "$src" >/dev/null 2>&1; then kind=sql; else kind=rpg; fi
    case "$kind" in
      sql)
        # No COMPILEOPT: nesting quotes inside a CL string inside a shell string
        # is what broke every .sqlrpgle last run. Nothing here needs INCDIR (no
        # .sqlrpgle uses /COPY) and TGTCCSID does not affect acceptance.
        out=$($SYS "CRTSQLRPGI OBJ($LIB/CONFTMP) SRCSTMF('$src') OBJTYPE(*PGM) COMMIT(*NONE)" </dev/null 2>&1)
        rc=$?
        ;;
      rpg)
        # Deliberately NOT OPTION(*NOGEN): with nothing to create, the compiler
        # appears not to signal failure through its exit status, which silently
        # scored invalid sources as accepted. A real compile gives a trustworthy
        # status plus the severity totals; the object is deleted immediately.
        #
        # DFTACTGRP(*NO) is required for prototypes, subprocedures and ON-EXIT
        # -- compiling under the default *YES produced RNF3788/RNF1520/RNF5446
        # on ~19 files, which were harness artifacts rather than real findings.
        # NOMAIN sources cannot go through CRTBNDRPG at all (RNF1304); they are
        # modules, so they compile with CRTRPGMOD instead.
        if grep -i 'nomain' "$src" >/dev/null 2>&1; then
            out=$($SYS "CRTRPGMOD MODULE($LIB/CONFTMP) SRCSTMF('$src') TGTCCSID(*JOB) INCDIR('$WORK')" </dev/null 2>&1)
            rc=$?
            $SYS "DLTMOD MODULE($LIB/CONFTMP)" </dev/null >/dev/null 2>&1
        else
            out=$($SYS "CRTBNDRPG PGM($LIB/CONFTMP) SRCSTMF('$src') TGTCCSID(*JOB) INCDIR('$WORK') DFTACTGRP(*NO) ACTGRP(*NEW)" </dev/null 2>&1)
            rc=$?
        fi
        ;;
    esac
    $SYS "DLTPGM PGM($LIB/CONFTMP)" </dev/null >/dev/null 2>&1
    if [ $rc -eq 0 ]; then
        echo "$out" | verdict
    else
        # Failures keep everything: CPD/CPF/SQL messages carry no RN prefix and
        # were discarded by the filter last run, leaving 12 files unexplained.
        echo "@@@RAW"
        echo "$out"
        echo "@@@ENDRAW"
    fi
    echo "@@@RC $rc"
done < "$WORK/tests/MANIFEST"

echo "@@@DONE"
REMOTE_EOF

echo
echo "=================================================================="
echo " IBM i conformance run -- ${USER_ID}@${HOST}:${PORT}"
echo "=================================================================="
ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "mkdir -p ${WORKDIR}" </dev/null || exit 1
scp "${SCP_OPTS[@]}" "$STAGE/corpus.tar.gz" "$STAGE/conf_remote.sh" \
    "${USER_ID}@${HOST}:${WORKDIR}/" || exit 1
echo "uploaded; compiling (this runs serially -- expect a few minutes)"
echo

ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "sh \$HOME/${WORKDIR}/conf_remote.sh" </dev/null \
    | tee "$LOG" | grep -E '^@@@(FILE|LIB|DONE)' | sed 's/^@@@FILE /  compiling /'

# ---- report --------------------------------------------------------------
echo
python3 - "$LOG" "$REPO_ROOT/ibmi-conformance-report.txt" <<'PY'
import sys, re, collections
log, out = sys.argv[1], sys.argv[2]
lines = open(log, errors='replace').read().splitlines()

results, cur, buf = [], None, []
for ln in lines:
    if ln.startswith('@@@FILE '):
        if cur: results.append((cur, buf, 1))
        cur, buf = ln[8:].strip(), []
    elif ln.startswith('@@@RC '):
        if cur: results.append((cur, buf, int(ln[6:].strip() or 1))); cur, buf = None, []
    elif cur is not None:
        buf.append(ln)
if cur: results.append((cur, buf, 1))

MSG = re.compile(r'^\s*\*?(RN[SF]\d{4})\s+(\d+)?\s*(.*)$')
SEV = re.compile(r'^\s+(Error|Severe Error)\s+\(\d+\+?\)\s*[. ]*:\s*(\d+)')

rows, bycode = [], collections.defaultdict(list)
for name, out_lines, rc in results:
    codes, worst, texts = set(), 0, {}
    for ln in out_lines:
        m = SEV.match(ln)
        if m and int(m.group(2)) > 0:
            worst = max(worst, 20 if m.group(1) == 'Error' else 30)
        m = MSG.match(ln)
        if m:
            code, sev, txt = m.group(1), int(m.group(2) or 0), m.group(3).strip()
            if sev >= 20 or code.startswith('RNS93'):
                codes.add(code); texts[code] = txt[:70]
                worst = max(worst, sev)
    # Both signals: a nonzero status, or any Error(20)/Severe(30+) in the
    # totals. Relying on status alone is what produced the bogus 208 last run.
    ok = (rc == 0 and worst < 20)
    rows.append((name, ok, sorted(codes), worst))
    for c in codes:
        if not ok: bycode[c].append((name, texts.get(c,'')))
    if not ok and not codes: bycode['(no RPG diagnostic - see transcript)'].append((name,''))

acc = [r for r in rows if r[1]]
rej = [r for r in rows if not r[1]]
L = []
L.append("IBM i conformance -- acceptance of the OpenRPG test corpus")
L.append("=" * 62)
L.append(f"compiled : {len(rows)}")
L.append(f"accepted : {len(acc)}")
L.append(f"rejected : {len(rej)}")
L.append("")
L.append("REJECTIONS GROUPED BY DIAGNOSTIC")
L.append("-" * 62)
for code, files in sorted(bycode.items(), key=lambda kv: -len(kv[1])):
    L.append(f"{code}  x{len(files)}   {files[0][1]}")
    for n, _ in files[:6]:
        L.append(f"      {n}")
    if len(files) > 6:
        L.append(f"      ... and {len(files)-6} more")
    L.append("")
L.append("REJECTED FILES")
L.append("-" * 62)
for n, ok, codes, worst in rej:
    L.append(f"  {n:<45} {','.join(codes)}")
if not rej:
    L.append("  (none)")
txt = "\n".join(L)
print(txt)
open(out, 'w').write(txt + "\n")
print(f"\nfull transcript parsed; report written to {out}")
PY

if [ "$UPDATE_BASELINE" = "1" ]; then
    echo
    echo "=================================================================="
    if ! python3 "$REPO_ROOT/scripts/conformance-baseline.py" update \
            --transcript "$LOG" --baseline "$REPO_ROOT/$BASELINE" --tests "$TESTDIR"; then
        echo
        echo "FAILING: a source IBM accepted before is rejected now." >&2
        exit 1
    fi
fi
