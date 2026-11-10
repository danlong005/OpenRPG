#!/usr/bin/env bash
# rpgc -g and the VS Code files it writes (issue #31, items 3 and 5):
# .vscode/launch.json gets one configuration per program, added or brought
# up to date next to the others -- it used to be overwritten, so only the
# last program compiled could be debugged -- and .vscode/settings.json gets
# "debug.allowBreakpointsEverywhere": true, without which VS Code refuses
# breakpoints in a .rpgle file. What the user wrote in either is kept.
set -u
cd "$(dirname "$0")/.."
RPGC="${RPGC:-$PWD/rpgc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

printf '**FREE\nDSPLY %s;\n*INLR = *ON;\n' "'A'" > "$WORK/PGMA.rpgle"
printf '**FREE\nDSPLY %s;\n*INLR = *ON;\n' "'B'" > "$WORK/PGMB.rpgle"

# Parses as JSON once // and /* */ comments and trailing commas are taken
# out, as VS Code reads it; skipped where there is no python3.
jsonc_ok() {
    command -v python3 >/dev/null 2>&1 || return 0
    python3 -I - "$1" <<'PY'
import json, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
out, i, n = [], 0, len(t)
while i < n:
    c = t[i]
    if c == '"':
        j = i + 1
        while j < n and t[j] != '"':
            j += 2 if t[j] == '\\' else 1
        out.append(t[i:j+1]); i = j + 1
    elif t.startswith("//", i):
        while i < n and t[i] != "\n": i += 1
    elif t.startswith("/*", i):
        i = t.index("*/", i) + 2
    else:
        out.append(c); i += 1
json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))
PY
}

check() {  # label, condition result (0 = pass)
    printf "%-55s " "vscode: $1"
    if [ "$2" -eq 0 ]; then echo "PASS"; PASS=$((PASS + 1))
    else echo "FAIL"; FAIL=$((FAIL + 1)); [ -n "${3:-}" ] && sed 's/^/    | /' "$3"; fi
}

compile() { (cd "$WORK" && "$RPGC" -g "$1.rpgle" -o "$1" > "$WORK/log" 2>&1); }

L="$WORK/.vscode/launch.json"; S="$WORK/.vscode/settings.json"

# 1. A fresh folder: both files written.
compile PGMA
grep -q '"name": "Debug PGMA"' "$L" && jsonc_ok "$L" && grep -q '"debug.allowBreakpointsEverywhere": true' "$S" && jsonc_ok "$S"
check "fresh folder gets launch.json and settings.json" $? "$L"

# 2. A second program is added next to the first.
compile PGMB
[ "$(grep -c '"name": "Debug PGM[AB]"' "$L")" = 2 ] && jsonc_ok "$L"
check "a second program is added, the first kept" $? "$L"

# 3. Compiling again adds nothing.
compile PGMA
[ "$(grep -c '"name": "Debug PGMA"' "$L")" = 1 ]
check "recompiling does not duplicate its configuration" $? "$L"

# 4. The user's own edits and comments survive; only "program" is updated.
cat > "$L" <<'JSON'
{
    // my notes
    "version": "0.2.0",
    "configurations": [
        {
            "type": "lldb",
            "request": "launch",
            "name": "Debug PGMA",
            "program": "/somewhere/old/PGMA",
            "args": ["--verbose"],
            "cwd": "${workspaceFolder}",
        },
    ]
}
JSON
compile PGMA
grep -q '// my notes' "$L" && grep -q '"--verbose"' "$L" && ! grep -q '/somewhere/old' "$L" &&
    grep -q '"program": ".*PGMA' "$L" && jsonc_ok "$L"
check "user edits kept; only the program path changes" $? "$L"

# 5. An existing settings.json with comments and other settings.
cat > "$S" <<'JSON'
{
    /* team settings */
    "editor.tabSize": 2,
}
JSON
compile PGMA
grep -q 'team settings' "$S" && grep -q '"editor.tabSize": 2' "$S" &&
    grep -q '"debug.allowBreakpointsEverywhere": true' "$S" && jsonc_ok "$S"
check "setting added to an existing settings.json" $? "$S"

# 6. The user's own false is theirs, with a warning.
printf '{ "debug.allowBreakpointsEverywhere": false }\n' > "$S"
compile PGMA
grep -q '"debug.allowBreakpointsEverywhere": false' "$S" && grep -q 'warning:.*false' "$WORK/log"
check "a user's false is kept, and warned about" $? "$WORK/log"

# 7. A file rpgc cannot read is left alone.
printf '{ "configurations": [ oops\n' > "$L"
cp "$L" "$WORK/before"
compile PGMA
cmp -s "$L" "$WORK/before" && grep -q 'warning: .vscode/launch.json' "$WORK/log"
check "unreadable launch.json left as it is" $? "$WORK/log"

echo ""
echo "VS Code files: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
