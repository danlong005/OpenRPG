#!/usr/bin/env bash
# rpgc -g: breakpoints set on .rpgle lines are hit in the order the program
# runs them (issue #31). Before, the code the compiler adds around the RPG
# statements was credited to whatever RPG line preceded it: a breakpoint on
# the first statement or two stopped in main's set-up before anything ran,
# and an IF, DOU or DCL-PROC was credited to its END line.
#
# Uses lldb, or gdb where there is no lldb; skipped when there is neither.
set -u
cd "$(dirname "$0")/.."
RPGC="${RPGC:-$PWD/rpgc}"
SRC="$PWD/tests/debug/DBGORDER.rpgle"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Breakpoint lines, and the order they must be hit in: the loop body twice,
# the ELSE branch never. (The DCL-PROC line is left out: built by clang it
# stops there on entry, by GCC, which marks no end of prologue, on the
# procedure's first statement. Both are right.)
LINES="8 9 11 13 14 16 18 22 29 19"
EXPECT="8 9 11 11 13 14 29 18 22 19"

printf "%-45s " "debug: breakpoints hit in program order"
if ! "$RPGC" -g "$SRC" -o "$WORK/DBGORDER" >"$WORK/compile.log" 2>&1; then
    echo "FAIL (rpgc -g)"; sed 's/^/    /' "$WORK/compile.log"; exit 1
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        # Which debugger and debug format Windows wants is still open (#31).
        echo "SKIP (Windows)"; exit 0 ;;
esac

run_with_timeout() { perl -e 'alarm(120); exec(@ARGV)' "$@"; }

if command -v lldb >/dev/null 2>&1; then
    {
        for l in $LINES; do echo "breakpoint set -f DBGORDER.rpgle -l $l"; done
        echo "run"
        for _ in $(seq 1 20); do echo "continue"; done
        echo "quit"
    } > "$WORK/cmds"
    run_with_timeout lldb -b -s "$WORK/cmds" "$WORK/DBGORDER" > "$WORK/out" 2>&1
    # "* thread #1, ... stop reason = breakpoint N.1" then "frame #0: ... at DBGORDER.rpgle:L:C"
    GOT=$(awk '/stop reason = breakpoint/ {want=1; next}
               want && /frame #0/ { if (match($0, /DBGORDER\.rpgle:[0-9]+/)) {
                   s = substr($0, RSTART, RLENGTH); sub(/.*:/, "", s); printf "%s ", s }
                   want=0 }' "$WORK/out")
elif command -v gdb >/dev/null 2>&1; then
    args=(-batch -nx)
    for l in $LINES; do args+=(-ex "break DBGORDER.rpgle:$l"); done
    args+=(-ex run)
    for _ in $(seq 1 20); do args+=(-ex continue); done
    run_with_timeout gdb "${args[@]}" "$WORK/DBGORDER" > "$WORK/out" 2>&1
    # "Breakpoint 3, main () at /path/DBGORDER.rpgle:11"
    GOT=$(grep -E '^Breakpoint [0-9]+, ' "$WORK/out" | sed -E 's/.*DBGORDER\.rpgle:([0-9]+).*/\1/' | tr '\n' ' ')
else
    echo "SKIP (no lldb or gdb)"
    exit 0
fi

GOT="${GOT% }"
if [ "$GOT" = "$EXPECT" ]; then
    echo "PASS"
else
    echo "FAIL"
    echo "    expected: $EXPECT"
    echo "    got:      $GOT"
    sed 's/^/    | /' "$WORK/out" | tail -60
    exit 1
fi
