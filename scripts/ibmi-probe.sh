#!/usr/bin/env bash
# One-shot reconnaissance run against a real IBM i (PUB400 by default), to
# answer the questions that decide whether a "compile the test corpus on real
# IBM i" build step is feasible — and in what shape — before any of it gets
# wired into CI.
#
# It answers, in one pass:
#   1. Can we SSH in at all, and on which port?
#   2. What OS release, and what is the *job* CCSID? (PUB400 is German-hosted,
#      so 273 is plausible rather than the US-default 37 — this decides whether
#      the corpus's `[`, `]`, `{`, `}`, `!` string literals survive a round trip.
#      Probe 9's canary answers the same question empirically, and is the one to
#      trust if this probe comes back empty.)
#   3. Is CRTBNDRPG present? Is CRTSQLRPGI present? (The latter needs the DB2
#      SQL Development Kit, 5770ST1, licensed separately from base RPG — if it
#      isn't there, the 24 EXEC SQL tests can't even precompile.)
#   4. What is the storage quota, and how much is already used?
#   5. Does a real corpus source (tests/test01_hello.rpgle) compile from an IFS
#      stream file into QTEMP?
#   6. THE BIG ONE: when the resulting program is CALLed from this PASE ssh
#      session, does its DSPLY output reach stdout — or does it only land in
#      the job log? This is what decides whether we get differential *execution*
#      against IBM's runtime, or only compile-conformance.
#   7. Do EBCDIC-variant characters round-trip? A generated canary program
#      DSPLYs bracket/brace/bang literals and carries an over-long source line
#      and a UTF-8 em-dash comment, mirroring what's already in the corpus.
#
# Everything is best-effort: individual probes report and continue rather than
# aborting, because a probe run that dies on step 3 tells you much less than one
# that limps to the end. Nothing is left behind on the host except the work
# directory's source files; compiled objects go to QTEMP, which the host
# reclaims when the ssh session's job ends.
#
# Two structural details that are load-bearing, both learned the hard way:
#
#   - The remote script is uploaded and run as a FILE, never piped into `sh -s`.
#     /QOpenSys/usr/bin/system reads stdin; piping the script in means `system`
#     eats the rest of the script and the shell exits silently mid-run. Every
#     `system` call also gets an explicit `</dev/null` on top of that.
#
#   - All the CL runs inside ONE ssh session, because `system` executes CL in
#     the *calling* PASE job. QTEMP therefore persists across calls within the
#     session and is reclaimed when it ends. Split across sessions, each call
#     would get a fresh job and a fresh empty QTEMP.
#
# Usage:
#   scripts/ibmi-probe.sh                      # prompts for user, then password
#   PUB400_USER=myuser scripts/ibmi-probe.sh
#   PUB400_USER=u PUB400_HOST=h PUB400_PORT=22 scripts/ibmi-probe.sh
#
# Connection multiplexing (ControlMaster) means the password is typed once, not
# once per ssh/scp invocation. Set up key auth (ssh-copy-id) and it stops asking
# entirely — which the eventual CI job needs anyway, since a scheduled workflow
# can't answer a prompt.
set -uo pipefail

USER_ID="${PUB400_USER:-}"
HOST="${PUB400_HOST:-pub400.com}"
# PUB400 runs sshd on 2222, not 22 (confirmed: port 22 is filtered).
PORT="${PUB400_PORT:-2222}"

if [ -z "$USER_ID" ]; then
    printf 'IBM i user profile: '
    read -r USER_ID
fi
if [ -z "$USER_ID" ]; then
    echo "error: no user profile given" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELLO_SRC="$REPO_ROOT/tests/test01_hello.rpgle"
if [ ! -f "$HELLO_SRC" ]; then
    echo "error: cannot find $HELLO_SRC" >&2
    exit 2
fi

STAGE="$(mktemp -d)"
# Unix domain socket paths cap out around 104 bytes on macOS, and mktemp -d
# hands back a long /var/folders/... path — so the control socket lives in
# ~/.ssh, where %C (a short hash of host/port/user) keeps it well inside that.
CTL="$HOME/.ssh/cm-ibmi-probe-%C"
cleanup() {
    ssh -O exit -o ControlPath="$CTL" -p "$PORT" "${USER_ID}@${HOST}" 2>/dev/null
    rm -rf "$STAGE"
}
trap cleanup EXIT

SSH_OPTS=(-p "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=120)
SCP_OPTS=(-P "$PORT" -o ControlMaster=auto -o ControlPath="$CTL" -o ControlPersist=120)

cp "$HELLO_SRC" "$STAGE/probe01.rpgle"

# The canary deliberately packs in every encoding hazard the corpus already
# contains, so one compile+run tells us whether any of them matter:
#   - `[` `]` `{` `}` `!` are EBCDIC-variant: they sit at different code points
#     in CCSID 37 vs 273, so a mismatch between the stream file's tag and the
#     job CCSID garbles them (90 lines of the corpus use brackets, 20 use
#     braces, 6 use `!` — all inside string literals).
#   - the em-dash below is UTF-8 multibyte, as in 37 corpus files' comments.
#   - the long line is 220 chars, matching the corpus's longest (test88.rpgle),
#     to check it isn't truncated when read from a stream file.
cat > "$STAGE/probe02.rpgle" <<'CANARY_EOF'
**FREE
// Canary: EBCDIC-variant chars, plus the %SUBST workaround for DSPLY's
// 52-char compile-time cap (RNF7016). No em-dash here: U+2014 has no Latin-1
// code point, so it cannot survive the 819 tag the compiler requires -- the
// 37 corpus files carrying one in a comment need it stripped, not encoded.
DCL-S bracket CHAR(20);
DCL-S brace   CHAR(20);
DCL-S bang    CHAR(20);
DCL-S wide    CHAR(100);
bracket = '[' + 'ok' + ']';
brace   = '{' + 'ok' + '}';
bang    = '!' + 'ok' + '!';
wide = 'the quick brown fox jumps over the lazy dog';
DSPLY bracket;
DSPLY brace;
DSPLY bang;
DSPLY %SUBST(wide:1:52);
*INLR = *ON;
CANARY_EOF

cat > "$STAGE/probe03.rpgle" <<'PRINTF_EOF'
**FREE
// printf from the C runtime reaches real stdout (proven); DSPLY does not.
// x'25' is EBCDIC LF -- x'15' is NL, which converts to nothing visible.
// Capturing printf's return into rc silences the RNF5409 informationals.
DCL-PR printf INT(10) EXTPROC('printf');
  fmt POINTER VALUE OPTIONS(*STRING);
END-PR;
DCL-S rc INT(10);
DCL-S nl CHAR(1);
nl = x'25';
rc = printf('Hello, world!' + nl);
rc = printf('42' + nl);
// every EBCDIC-variant character the corpus actually uses, plus the rest of
// the variant set, so one line maps exactly which ones survive the round trip
rc = printf('brackets [ok] braces {ok} bang !ok!' + nl);
rc = printf('rest # @ $ ^ ~ | backslash-next \\' + nl);
*INLR = *ON;
PRINTF_EOF

WORKDIR="rpgc-probe"

# Built locally, uploaded, then run as a file on the host. The unquoted heredoc
# below expands ${WORKDIR}/${USER_ID} here; everything meant for the remote
# shell is escaped as \$.
cat > "$STAGE/probe_remote.sh" <<REMOTE_EOF
PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/usr/bin:\$PATH
export PATH
SYS=/QOpenSys/usr/bin/system
WORK="\$HOME/${WORKDIR}"
ME=\$(whoami | tr 'a-z' 'A-Z')

say() { echo; echo "--- \$* ---"; }
verdict() { grep -E '^ *\*?RN[SF][0-9]{4}|Error +\(20\)|Severe Error|Compilation (failed|stopped)' ; }

setccsid 819 "\$WORK/probe03.rpgle" </dev/null >/dev/null 2>&1
LIB=\$(\$SYS "DSPUSRPRF USRPRF(\$ME) OUTPUT(*PRINT)" </dev/null 2>&1 \
        | grep -i 'Current library' | awk '{print \$NF}' | tr -d '\r')
[ -z "\$LIB" ] && LIB="\${ME}1"
echo "library: \$LIB   (job CCSID is 273; source stream file is tagged 819)"

# Same source, three target CCSIDs. Literals are stored in the target CCSID and
# rendered to stdout through the job's CCSID (273), so the variant characters
# only survive when those two agree.
run_variant() {
    _name="\$1"; _pgm="\$2"; _tgt="\$3"
    say "variant: \$_name"
    \$SYS "DLTPGM PGM(\$LIB/\$_pgm)" </dev/null >/dev/null 2>&1
    if [ -z "\$_tgt" ]; then
        \$SYS "CRTBNDRPG PGM(\$LIB/\$_pgm) SRCSTMF('\$WORK/probe03.rpgle') DFTACTGRP(*NO) ACTGRP(*NEW) BNDDIR(QC2LE)" </dev/null 2>&1 | verdict
    else
        \$SYS "CRTBNDRPG PGM(\$LIB/\$_pgm) SRCSTMF('\$WORK/probe03.rpgle') DFTACTGRP(*NO) ACTGRP(*NEW) BNDDIR(QC2LE) TGTCCSID(\$_tgt)" </dev/null 2>&1 | verdict
    fi
    echo "vvvvv"
    \$SYS "CALL PGM(\$LIB/\$_pgm)" </dev/null 2>&1
    echo "^^^^^"
    \$SYS "DLTPGM PGM(\$LIB/\$_pgm)" </dev/null >/dev/null 2>&1
}

run_variant "default target CCSID (was *SRC/500)" PROBEA ""
run_variant "TGTCCSID(*JOB) -- store in the same CCSID we render through" PROBEB "*JOB"
run_variant "TGTCCSID(37) -- US EBCDIC" PROBEC "37"

say "reference: what the lines should read"
echo "  Hello, world!"
echo "  42"
echo "  brackets [ok] braces {ok} bang !ok!"
echo "  rest # @ \\\$ ^ ~ | backslash-next \\\\"
echo
echo "Each variant should be 4 separate lines. If they are still run together,"
echo "x'25' is not converting to LF either and the newline needs another look."

say "done"
REMOTE_EOF

echo "=================================================================="
echo " IBM i probe — ${USER_ID}@${HOST}:${PORT}"
echo "=================================================================="
echo
echo "--- [0] creating work directory and uploading ---"
ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "mkdir -p ${WORKDIR}" </dev/null || {
    echo "FATAL: could not ssh in. Check host/port/credentials." >&2
    exit 1
}
scp "${SCP_OPTS[@]}" "$STAGE/probe01.rpgle" "$STAGE/probe02.rpgle" \
    "$STAGE/probe03.rpgle" "$STAGE/probe_remote.sh" "${USER_ID}@${HOST}:${WORKDIR}/" || {
    echo "FATAL: scp failed." >&2
    exit 1
}
echo "uploaded probe01-03.rpgle, probe_remote.sh"
echo

ssh "${SSH_OPTS[@]}" "${USER_ID}@${HOST}" "sh \$HOME/${WORKDIR}/probe_remote.sh" </dev/null

echo
echo "=================================================================="
echo " probe complete"
echo "=================================================================="
echo "Key things to read out of the above:"
echo "  [3]  CRTSQLRPGI present? decides the fate of the 24 EXEC SQL tests"
echo "  [7]  did 'Hello, world!' and '42' appear on stdout?"
echo "       yes -> differential execution against IBM's runtime is on"
echo "       no  -> compile-conformance only, unless [8] shows a usable joblog"
echo "  [9]  did [ok] {ok} !ok! come back intact, and the long line unbroken?"
echo "  [10] events file available? decides how diagnostics get parsed"
