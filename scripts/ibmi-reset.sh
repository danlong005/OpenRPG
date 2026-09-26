#!/usr/bin/env bash
# Gives an IBM i run a clean library: clears the profile's current library
# (CLRLIB), removes the harnesses' IFS work folders, then rebuilds the objects
# the corpus references with scripts/ibmi-setup-objects.sh.
#
# The library is shared with other projects (iMoq) that do the same -- each
# project owns it for the length of its run and reloads everything it needs.
# Never keep anything in it that is not reproducible from a repository.
#
# The library is discovered, never assumed (it is LONGDM1 for profile LONGDM,
# not LONGDM), and the clear refuses anything that is not plainly a user
# library: empty, or an IBM Q* system library.
#
# Used by ibmi-conformance.sh and ibmi-execution.sh.
set -uo pipefail

USER_ID="${PUB400_USER:?PUB400_USER is not set}"
HOST="${PUB400_HOST:-pub400.com}"
PORT="${PUB400_PORT:-2222}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "resetting: clearing the library and the IFS work folders"
ssh -p "$PORT" "${USER_ID}@${HOST}" "sh -s" <<'RESET_EOF' | grep -E '^cleared |refusing|failed|CP[FD]' || { echo "reset failed" >&2; exit 1; }
PATH=/QOpenSys/usr/bin:/QOpenSys/usr/sbin:/usr/bin:$PATH
export PATH
SYS=/QOpenSys/usr/bin/system
ME=$(whoami | tr 'a-z' 'A-Z')
LIB=$($SYS "DSPUSRPRF USRPRF($ME) OUTPUT(*PRINT)" </dev/null 2>&1 \
        | grep -i 'Current library' | awk '{print $NF}' | tr -d '\r')
case "$LIB" in
    ""|Q*|\**) echo "refusing to clear library '$LIB'" >&2; exit 1 ;;
esac
out=$($SYS "CLRLIB LIB($LIB)" </dev/null 2>&1); rc=$?
if [ $rc -ne 0 ]; then
    echo "CLRLIB $LIB failed:"; echo "$out" | grep -E 'CP[FDI][0-9A-F]{4}'
    exit 1
fi
left=$($SYS "DSPLIB LIB($LIB) OUTPUT(*PRINT)" </dev/null 2>&1 \
        | grep 'Number of objects' | head -1 | awk '{print $NF}')
echo "cleared $LIB ($left object(s) left)"
rm -rf "$HOME/rpgc-conf" "$HOME/rpgc-setup" "$HOME/rpgc-exec"
RESET_EOF
echo "rebuilding the objects the corpus references"
PUB400_USER="$USER_ID" PUB400_HOST="$HOST" PUB400_PORT="$PORT" \
    "$REPO_ROOT/scripts/ibmi-setup-objects.sh" || { echo "setup failed" >&2; exit 1; }
