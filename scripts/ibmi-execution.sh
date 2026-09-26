#!/usr/bin/env bash
# Differential EXECUTION on a real IBM i: runs the corpus's "run" tests on
# PUB400 with IBM's own compiler and runtime, and compares what each program
# displays with tests/expected_output/ -- which rpgc generated itself.
#
# ibmi-conformance.sh asks "does IBM compile it?". That cannot catch a program
# both compilers accept but run differently, and tests/expected_output/ cannot
# either: `run_tests.sh --update` writes it from rpgc's own output. IBM's
# runtime is the independent oracle for behaviour.
#
# How output is captured (all verified on PUB400 2026-09-26):
#   - DSPLY normally posts to the job's external message queue, which dies with
#     the job. Every DSPLY is given a second operand naming a message queue in
#     the current library (scripts/exec_transform.py); that is the only change
#     made to a source, so what comes back is IBM's own DSPLY formatting.
#     A marker message separates one test's output from the next, and the whole
#     queue is read once, in order, at the end (QSYS2.MESSAGE_QUEUE_INFO).
#   - The job's INQMSGRPY is *RQD: an unhandled runtime error sends an inquiry
#     message to the system operator and the job waits for a reply, forever.
#     Each program is therefore called through a CL driver (RPGCDRV) that sets
#     INQMSGRPY(*DFT) first, so the error ends the program instead, and the
#     driver reports it as "RPGCRUN-ERROR <msgid> <text>".
#   - A watchdog ends a program still running after $RUN_LIMIT seconds. The
#     driver records its own job in a data area so the watchdog can ENDJOB it.
#   - Program-described files keep their records between runs on IBM i, so each
#     file a test names is cleared (CLRPFM) before the test runs.
#
# Usage:
#   scripts/ibmi-execution.sh                  # every eligible run test
#   scripts/ibmi-execution.sh --only test05_if.rpgle,test06_loops.rpgle
#   scripts/ibmi-execution.sh --limit 10       # smoke run
#   scripts/ibmi-execution.sh --no-reset       # keep the library as it is
#
# Writes ibmi-execution-transcript.txt, then scripts/execution-diff.py writes
# ibmi-execution-differences.md and ibmi-execution-baseline.json.
#
# Load discipline: PUB400 is a free community box. Manual runs only, serial.
# Every run that contacts the machine first resets the library
# (scripts/ibmi-reset.sh) unless --no-reset is given; the library is shared
# with other projects that take turns, so check nothing else is using it.
set -uo pipefail

USER_ID="${PUB400_USER:-}"
HOST="${PUB400_HOST:-pub400.com}"
PORT="${PUB400_PORT:-2222}"
LIMIT=0
ONLY=""
RESET=1
RUN_LIMIT="${RUN_LIMIT:-60}"
while [ $# -gt 0 ]; do
    case "$1" in
        --limit) LIMIT="${2:-0}"; shift 2 ;;
        --only) ONLY="${2:-}"; shift 2 ;;
        --no-reset) RESET=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$USER_ID" ]; then printf 'IBM i user profile: '; read -r USER_ID; fi
[ -z "$USER_ID" ] && { echo "error: no user profile given" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDIR="$REPO_ROOT/tests"
STAGE="$(mktemp -d)"
CTL="$HOME/.ssh/cm-ibmi-exec-%C"
LOG="$REPO_ROOT/ibmi-execution-transcript.txt"
cleanup() {
    ssh -O exit -o ControlPath="$CTL" -p "$PORT" "${USER_ID}@${HOST}" 2>/dev/null
    rm -rf "$STAGE"
}
trap cleanup EXIT
SSH_OPTS=(-p "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=300)
SCP_OPTS=(-P "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=300)
WORKDIR="rpgc-exec"

# ---- stage sources -------------------------------------------------------
mkdir -p "$STAGE/pkg/tests"
python3 - "$REPO_ROOT" "$STAGE/pkg/tests" "$LIMIT" "$ONLY" <<'PY' || { echo "staging failed" >&2; exit 1; }
import sys, os, glob, re, json
root, dst, limit, only = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
sys.path.insert(0, os.path.join(root, 'scripts'))
from exec_transform import route_dsply
from conformance_lib import run_tests
tests = os.path.join(root, 'tests')

# Same folding as ibmi-conformance.sh: CCSID 819 cannot hold U+2014 and friends.
SUBS = {'—':'-', '–':'-', '‘':"'", '’':"'",
        '“':'"', '”':'"', '…':'...', ' ':' '}
problems = {}
for p in sorted(glob.glob(os.path.join(tests, '*.rpgle')) + glob.glob(os.path.join(tests, '*.sqlrpgle'))):
    t = open(p, encoding='utf-8', errors='replace').read()
    for k, v in SUBS.items(): t = t.replace(k, v)
    t = t.encode('ascii', errors='replace').decode('ascii')
    t, n, probs = route_dsply(t)
    if probs: problems[os.path.basename(p)] = probs
    open(os.path.join(dst, os.path.basename(p)), 'w').write(t)

baseline = json.load(open(os.path.join(root, 'ibmi-conformance-baseline.json')))['files']
wanted = {s.strip() for s in only.split(',') if s.strip()}
manifest, skipped = [], []
for num, src, mode, extra in run_tests(tests):
    name = os.path.basename(src)
    if wanted and name not in wanted: continue
    if mode != 'run': continue
    if extra:
        skipped.append((name, 'links a second object; not run standalone')); continue
    if baseline.get(name, {}).get('verdict') != 'accept':
        skipped.append((name, 'IBM i does not compile it')); continue
    if name in problems:
        skipped.append((name, 'DSPLY not routable: ' + '; '.join(problems[name]))); continue
    text = open(os.path.join(dst, name)).read()
    if re.search(r'\bWORKSTN\b', text, re.I):
        skipped.append((name, 'interactive (WORKSTN)')); continue
    # Files to clear before the run: fixed F-spec names (positions 7-16) and
    # free-form DCL-F names, for DISK files only.
    files = set()
    for line in text.splitlines():
        if len(line) > 6 and line[5] in 'Ff' and line[6] != '*' and line[6:16].strip():
            if 'DISK' in line[35:42].upper():
                files.add(line[6:16].strip().upper())
        m = re.match(r'\s*DCL-F\s+(\w+)(.*)', line, re.I)
        if m and not re.search(r'\b(PRINTER|WORKSTN|SPECIAL|SEQ)\b', m.group(2), re.I):
            files.add(m.group(1).upper())
    manifest.append((name, num, ','.join(sorted(files)) or '-'))
if limit > 0: manifest = manifest[:limit]
with open(os.path.join(dst, 'MANIFEST'), 'w') as f:
    for name, num, files in manifest: f.write(f"{name} {num} {files}\n")
with open(os.path.join(dst, 'SKIPPED'), 'w') as f:
    for name, why in skipped: f.write(f"{name}\t{why}\n")
print(f"will run {len(manifest)} program(s); {len(skipped)} run test(s) skipped")
PY
cp "$STAGE/pkg/tests/SKIPPED" "$STAGE/skipped.txt"

# The CL driver: inquiry messages get their default reply instead of waiting
# for an operator, a runtime error comes back as one marked line, and the
# driver's own job is recorded for the watchdog.
cat > "$STAGE/pkg/tests/rpgcdrv.clle" <<'CL_EOF'
PGM PARM(&LIB &PGM)
  DCL VAR(&LIB) TYPE(*CHAR) LEN(10)
  DCL VAR(&PGM) TYPE(*CHAR) LEN(10)
  DCL VAR(&JOB) TYPE(*CHAR) LEN(10)
  DCL VAR(&USR) TYPE(*CHAR) LEN(10)
  DCL VAR(&NBR) TYPE(*CHAR) LEN(6)
  DCL VAR(&MSGID) TYPE(*CHAR) LEN(7)
  DCL VAR(&MSG) TYPE(*CHAR) LEN(200)
  RTVJOBA JOB(&JOB) USER(&USR) NBR(&NBR)
  CHGDTAARA DTAARA(&LIB/RPGCJOB) VALUE(&NBR *TCAT '/' *TCAT &USR *TCAT '/' *TCAT &JOB)
  CHGJOB INQMSGRPY(*DFT)
  CALL PGM(&LIB/&PGM)
  MONMSG MSGID(CPF0000 RNX0000 CEE0000 MCH0000) EXEC(DO)
    RCVMSG MSGTYPE(*EXCP) MSGID(&MSGID) MSG(&MSG)
    MONMSG MSGID(CPF0000)
    DLTSPLF FILE(QPPGMDMP) SPLNBR(*LAST)
    MONMSG MSGID(CPF0000)
    SNDPGMMSG MSGID(CPF9898) MSGF(QCPFMSG) MSGDTA('RPGCRUN-ERROR ' *CAT &MSGID +
                *BCAT &MSG) MSGTYPE(*ESCAPE)
  ENDDO
ENDPGM
CL_EOF

( cd "$STAGE/pkg" && tar cf - tests ) | gzip -9 > "$STAGE/corpus.tar.gz"

# ---- remote driver -------------------------------------------------------
cat > "$STAGE/exec_remote.sh" <<'REMOTE_EOF'
PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/usr/bin:$PATH
export PATH
SYS=/QOpenSys/usr/bin/system
WORK="$HOME/rpgc-exec"
RUN_LIMIT="${1:-60}"
ME=$(whoami | tr 'a-z' 'A-Z')
db2q() { /QOpenSys/usr/bin/qsh -c "db2 \"$1\"" </dev/null 2>&1; }

cd "$WORK" || exit 1
gzip -dc corpus.tar.gz | tar xf - || exit 1
LIB=$($SYS "DSPUSRPRF USRPRF($ME) OUTPUT(*PRINT)" </dev/null 2>&1 \
        | grep -i 'Current library' | awk '{print $NF}' | tr -d '\r')
[ -z "$LIB" ] && LIB="${ME}1"
echo "@@@LIB $LIB"
for f in tests/*.rpgle tests/*.sqlrpgle tests/*.clle; do
    [ -f "$f" ] && setccsid 819 "$f" </dev/null >/dev/null 2>&1
done
STARTED=$(date '+%Y-%m-%d-%H.%M.%S')

$SYS "DLTMSGQ MSGQ($LIB/RPGCOUT)" </dev/null >/dev/null 2>&1
$SYS "CRTMSGQ MSGQ($LIB/RPGCOUT) SIZE(64 16 *NOMAX)" </dev/null >/dev/null 2>&1 \
    || { echo "@@@FATAL CRTMSGQ failed"; exit 1; }
$SYS "DLTDTAARA DTAARA($LIB/RPGCJOB)" </dev/null >/dev/null 2>&1
$SYS "CRTDTAARA DTAARA($LIB/RPGCJOB) TYPE(*CHAR) LEN(28)" </dev/null >/dev/null 2>&1
out=$($SYS "CRTBNDCL PGM($LIB/RPGCDRV) SRCSTMF('$WORK/tests/rpgcdrv.clle')" </dev/null 2>&1) \
    || { echo "@@@FATAL CRTBNDCL failed"; echo "$out"; exit 1; }

# Compile listings are filtered as in ibmi-conformance.sh.
verdict() { grep -E '^ *\*?RN[SF][0-9]{4}|^ +(Error|Severe Error) ' ; }

while read -r f num files; do
    [ -z "$f" ] && continue
    src="$WORK/tests/$f"
    echo "@@@FILE $f $num"
    $SYS "SNDMSG MSG('RPGCTEST $f') TOMSGQ($LIB/RPGCOUT)" </dev/null >/dev/null 2>&1
    $SYS "DLTPGM PGM($LIB/RPGCXRUN)" </dev/null >/dev/null 2>&1
    out=$($SYS "CRTBNDRPG PGM($LIB/RPGCXRUN) SRCSTMF('$src') TGTCCSID(*JOB) INCDIR('$WORK') DFTACTGRP(*NO) ACTGRP(*NEW)" </dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "@@@COMPILE-FAILED"
        echo "$out" | verdict
        continue
    fi
    if [ "$files" != "-" ]; then
        for pf in $(echo "$files" | tr ',' ' '); do
            $SYS "CLRPFM FILE($LIB/$pf)" </dev/null >/dev/null 2>&1
        done
    fi
    echo "$f" > "$WORK/running"
    (
        sleep "$RUN_LIMIT"
        if [ "$(cat "$WORK/running" 2>/dev/null)" = "$f" ]; then
            job=$(db2q "SELECT 'J|' CONCAT TRIM(DATA_AREA_VALUE) FROM QSYS2.DATA_AREA_INFO WHERE DATA_AREA_LIBRARY = '$LIB' AND DATA_AREA_NAME = 'RPGCJOB'" \
                    | sed -n 's/^J|//p' | tr -d ' ')
            echo "@@@TIMEOUT $f after ${RUN_LIMIT}s, ending job $job"
            [ -n "$job" ] && $SYS "ENDJOB JOB($job) OPTION(*IMMED)" </dev/null >/dev/null 2>&1
        fi
    ) &
    wd=$!
    echo "@@@RUN"
    $SYS "CALL PGM($LIB/RPGCDRV) PARM('$LIB' 'RPGCXRUN')" </dev/null 2>&1
    echo "@@@ENDRUN"
    rm -f "$WORK/running"
    kill "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    $SYS "DLTPGM PGM($LIB/RPGCXRUN)" </dev/null >/dev/null 2>&1
done < "$WORK/tests/MANIFEST"

# Everything the programs displayed, in the order it was displayed.
echo "@@@QUEUE"
db2q "SELECT 'Q|' CONCAT CAST(MESSAGE_TEXT AS VARCHAR(512)) FROM QSYS2.MESSAGE_QUEUE_INFO WHERE MESSAGE_QUEUE_LIBRARY = '$LIB' AND MESSAGE_QUEUE_NAME = 'RPGCOUT' ORDER BY MESSAGE_KEY" \
    | grep '^Q|'
echo "@@@ENDQUEUE"

# Spooled files the run's own driver jobs (QUSER/QP0ZSPWT) left behind are
# REPORTED, never deleted: the driver already deletes the dump an error
# produces, and anything else under this profile may belong to another
# project using the machine at the same time (a first version of this
# cleanup deleted other jobs' job logs, 2026-09-26).
db2q "SELECT 'S|' CONCAT TRIM(SPOOLED_FILE_NAME) CONCAT ' ' CONCAT TRIM(JOB_NAME) FROM QSYS2.OUTPUT_QUEUE_ENTRIES_BASIC WHERE USER_NAME = '$ME' AND JOB_NAME LIKE '%/QUSER/QP0ZSPWT' AND SPOOLED_FILE_NAME <> 'QPJOBLOG' AND CREATE_TIMESTAMP >= '$STARTED'" \
    | sed -n 's/^S|/@@@SPOOL left /p'

$SYS "DLTPGM PGM($LIB/RPGCDRV)" </dev/null >/dev/null 2>&1
$SYS "DLTMSGQ MSGQ($LIB/RPGCOUT)" </dev/null >/dev/null 2>&1
$SYS "DLTDTAARA DTAARA($LIB/RPGCJOB)" </dev/null >/dev/null 2>&1
echo "@@@DONE"
REMOTE_EOF

echo
echo "=================================================================="
echo " IBM i execution run -- ${USER_ID}@${HOST}:${PORT}"
echo "=================================================================="
if [ "$RESET" = "1" ]; then
    PUB400_USER="$USER_ID" PUB400_HOST="$HOST" PUB400_PORT="$PORT" \
        "$REPO_ROOT/scripts/ibmi-reset.sh" || exit 1
    echo
fi

ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "rm -rf ${WORKDIR}; mkdir -p ${WORKDIR}" </dev/null || exit 1
scp "${SCP_OPTS[@]}" "$STAGE/corpus.tar.gz" "$STAGE/exec_remote.sh" \
    "${USER_ID}@${HOST}:${WORKDIR}/" || exit 1
echo "uploaded; running (serial -- expect several minutes)"
echo

ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "sh \$HOME/${WORKDIR}/exec_remote.sh ${RUN_LIMIT}" </dev/null \
    | tee "$LOG" | grep --line-buffered -E '^@@@(FILE|TIMEOUT|FATAL|DONE)' | sed 's/^@@@FILE /  running /'
ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "rm -rf ${WORKDIR}" </dev/null

echo
python3 "$REPO_ROOT/scripts/execution-diff.py" --transcript "$LOG" \
    --skipped "$STAGE/skipped.txt" --tests "$TESTDIR" --out "$REPO_ROOT"
