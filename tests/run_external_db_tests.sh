#!/bin/bash
# Runs the rpgc.conf-based SQL/RLA tests (107, 108) against an external
# database via RPGC_DSN. These two fixtures use only standard SQL (CREATE
# TABLE, INSERT, cursors, CHAIN/%FOUND) with the DSN injected through the
# config mechanism rather than hardcoded in source, so they work unmodified
# against any ODBC-reachable database — this validates real connectivity to
# Postgres/MySQL/etc. beyond the SQLite path the main suite exercises.
set -e

if [ -z "$1" ]; then
    echo "usage: $0 <dsn> [label]" >&2
    exit 2
fi
DSN="$1"
LABEL="${2:-external db}"

RPGC="${RPGC:-./rpgc}"
RUNTIME_DIR="${RUNTIME_DIR:-runtime}"
CXX="${CXX:-clang++}"
CXXFLAGS="-std=c++17 -I${RUNTIME_DIR}"
ODBC_FLAGS="${ODBC_FLAGS:--lodbc}"
TESTDIR="tests"
EXPECTED_OUT="$TESTDIR/expected_output"
TMPDIR="/tmp/rpgc_ext_test_$$"
mkdir -p "$TMPDIR"

if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; RED=''; NC=''
fi

PASS=0
FAIL=0

run_one() {
    local testnum="$1" src="$2"
    printf "%-45s " "$LABEL: test${testnum}"

    if ! RPGC_DSN="$DSN" "$RPGC" -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
        echo -e "${RED}FAIL${NC} (transpile failed)"
        cat "$TMPDIR/test${testnum}_err.txt"
        FAIL=$((FAIL + 1))
        return
    fi

    if ! $CXX $CXXFLAGS -o "$TMPDIR/test${testnum}" "$TMPDIR/test${testnum}.cpp" $ODBC_FLAGS 2>"$TMPDIR/test${testnum}_err.txt"; then
        echo -e "${RED}FAIL${NC} (compile failed)"
        cat "$TMPDIR/test${testnum}_err.txt"
        FAIL=$((FAIL + 1))
        return
    fi

    local actual="$TMPDIR/test${testnum}.actual"
    "$TMPDIR/test${testnum}" > "$actual" 2>&1 || true

    local expected="$EXPECTED_OUT/test${testnum}.out"
    if diff -q --strip-trailing-cr "$actual" "$expected" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff --unified=3 --strip-trailing-cr "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

run_one 107 "$TESTDIR/test107_sql_conf.sqlrpgle"
run_one 108 "$TESTDIR/test108_rla_conf.rpgle"

echo ""
echo "$LABEL: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
