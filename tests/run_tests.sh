#!/bin/bash
# RPG Compiler Test Runner
# Validates runtime output against expected output

set -e

UPDATE_MODE=false
if [ "$1" = "--update" ]; then
    UPDATE_MODE=true
fi

RPGC="${RPGC:-./rpgc}"
RUNTIME_DIR="${RUNTIME_DIR:-runtime}"
CXX="${CXX:-clang++}"
# timeout is GNU coreutils (not available on macOS by default; gtimeout is the Homebrew alias)
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout 30"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout 30"
fi
# Arrays, not strings — RUNTIME_DIR can contain a space (e.g. the default
# Windows install path "C:\Program Files\openrpg\runtime"), and a plain
# string later expanded unquoted (needed so -std=c++17 and -I... land as
# separate argv entries) would let that space split -I<path> into two
# words, same bug this test harness exists to catch in rpgc itself.
CXXFLAGS=(-std=c++17 "-I${RUNTIME_DIR}")
ODBC_FLAGS="${ODBC_FLAGS:--I/opt/homebrew/include -L/opt/homebrew/lib -lodbc}"
# ODBC_FLAGS appended AFTER the source file so -l flags follow the object (GNU ld ordering)
CXXFLAGS_SQL=(-std=c++17 "-I${RUNTIME_DIR}")
TESTDIR="tests"
EXPECTED_OUT="$TESTDIR/expected_output"
TMPDIR="/tmp/rpgc_test"

PASS=0
FAIL=0
SKIP=0
FAILURES=""

# SKIP_SQL=1 skips every ODBC-dependent test (run-sql / run-sql-conf modes)
# instead of failing them — for platforms with no ODBC driver available,
# e.g. Windows ARM64, where no upstream SQLite ODBC build exists.

mkdir -p "$TMPDIR"

# Colors (if terminal supports it)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

run_test() {
    local testnum="$1"
    local label="$2"
    local src="$3"
    local mode="$4"  # "run", "compile-only", "parse-only", "error"
    local extra="$5" # extra compile args (e.g., /tmp/rpgc_test/test48.o)

    printf "Test %s: %-35s " "$testnum" "$label"

    if [ "$SKIP_SQL" = "1" ] && [ "${mode#run-sql}" != "$mode" ]; then
        echo -e "${YELLOW}SKIP${NC} (no ODBC driver on this platform)"
        SKIP=$((SKIP + 1))
        return
    fi

    case "$mode" in
        error)
            if $RPGC "$src" -o /dev/null 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (should have failed)"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi
            echo -e "${GREEN}PASS${NC}"
            PASS=$((PASS + 1))
            ;;
        parse-only)
            if ! $RPGC -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi
            echo -e "${GREEN}PASS${NC}"
            PASS=$((PASS + 1))
            ;;
        compile-only)
            if ! $RPGC -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi
            if ! "$CXX" "${CXXFLAGS[@]}" -c -o "$TMPDIR/test${testnum}.o" "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi
            echo -e "${GREEN}PASS${NC}"
            PASS=$((PASS + 1))
            ;;
        run)
            # Transpile
            if ! $RPGC -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            # Compile
            if ! "$CXX" "${CXXFLAGS[@]}" -o "$TMPDIR/test${testnum}" "$TMPDIR/test${testnum}.cpp" $extra 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            # Run and check output
            local actual="$TMPDIR/test${testnum}.actual"
            $TIMEOUT_CMD "$TMPDIR/test${testnum}" > "$actual" 2>&1 || true

            local expected="$EXPECTED_OUT/test${testnum}.out"
            if $UPDATE_MODE; then
                cp "$actual" "$expected"
                echo -e "${YELLOW}UPDATED${NC}"
                PASS=$((PASS + 1))
            elif [ -f "$expected" ]; then
                if diff -q --strip-trailing-cr "$actual" "$expected" > /dev/null 2>&1; then
                    echo -e "${GREEN}PASS${NC}"
                    PASS=$((PASS + 1))
                else
                    echo -e "${RED}FAIL${NC} (output mismatch)"
                    diff --unified=3 --strip-trailing-cr "$expected" "$actual" | head -20
                    FAIL=$((FAIL + 1))
                    FAILURES="$FAILURES\n  Test $testnum ($label)"
                fi
            else
                # No expected output file — just verify it ran
                echo -e "${GREEN}PASS${NC} (no output check)"
                PASS=$((PASS + 1))
            fi
            ;;
        run-sql)
            # Clean up any previous test database
            rm -f "/tmp/rpgc_test${testnum}.sqlite"

            # Transpile
            if ! $RPGC -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            # On Windows (MSYS2), the ODBC driver uses native Windows paths, not MSYS2 /tmp.
            # Translate the SQLite path in the generated .cpp so both the driver and cleanup agree.
            # NOTE: this matches the literal "Database=/tmp/", so a test that builds its
            # connection string by concatenation must never split it across that token —
            # the rewrite silently fails to match and the test then passes on Unix while
            # quietly reading the wrong (nonexistent) database on Windows.
            if command -v cygpath >/dev/null 2>&1; then
                WIN_TMP=$(cygpath -m /tmp)
                sed -i "s|Database=/tmp/|Database=${WIN_TMP}/|g" "$TMPDIR/test${testnum}.cpp"
            fi

            # Compile with ODBC flags
            if ! "$CXX" "${CXXFLAGS_SQL[@]}" -o "$TMPDIR/test${testnum}" "$TMPDIR/test${testnum}.cpp" $extra $ODBC_FLAGS 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            # Run and check output
            local actual="$TMPDIR/test${testnum}.actual"
            $TIMEOUT_CMD "$TMPDIR/test${testnum}" > "$actual" 2>&1 || true

            # Clean up temp database
            rm -f "/tmp/rpgc_test${testnum}.sqlite"

            local expected="$EXPECTED_OUT/test${testnum}.out"
            if $UPDATE_MODE; then
                cp "$actual" "$expected"
                echo -e "${YELLOW}UPDATED${NC}"
                PASS=$((PASS + 1))
            elif [ -f "$expected" ]; then
                if diff -q --strip-trailing-cr "$actual" "$expected" > /dev/null 2>&1; then
                    echo -e "${GREEN}PASS${NC}"
                    PASS=$((PASS + 1))
                else
                    echo -e "${RED}FAIL${NC} (output mismatch)"
                    diff --unified=3 --strip-trailing-cr "$expected" "$actual" | head -20
                    FAIL=$((FAIL + 1))
                    FAILURES="$FAILURES\n  Test $testnum ($label)"
                fi
            else
                # No expected output file — just verify it ran
                echo -e "${GREEN}PASS${NC} (no output check)"
                PASS=$((PASS + 1))
            fi
            ;;
        run-sql-conf)
            # Like run-sql, but injects DB_DSN via RPGC_DSN env var instead of EXEC SQL CONNECT
            rm -f "/tmp/rpgc_test${testnum}.sqlite"
            # On Windows (MSYS2), convert the SQLite path to a native Windows path so the ODBC
            # driver can open the same file that MSYS2's /tmp cleanup will remove.
            local _db_path="/tmp/rpgc_test${testnum}.sqlite"
            if command -v cygpath >/dev/null 2>&1; then
                _db_path="$(cygpath -m /tmp)/rpgc_test${testnum}.sqlite"
            fi
            local dsn="Driver={SQLite3};Database=${_db_path};"

            if ! RPGC_DSN="$dsn" $RPGC -S "$src" -o "$TMPDIR/test${testnum}.cpp" 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            if ! "$CXX" "${CXXFLAGS_SQL[@]}" -o "$TMPDIR/test${testnum}" "$TMPDIR/test${testnum}.cpp" $extra $ODBC_FLAGS 2>"$TMPDIR/test${testnum}_err.txt"; then
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$TMPDIR/test${testnum}_err.txt"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Test $testnum ($label)"
                return
            fi

            local actual="$TMPDIR/test${testnum}.actual"
            $TIMEOUT_CMD "$TMPDIR/test${testnum}" > "$actual" 2>&1 || true
            rm -f "/tmp/rpgc_test${testnum}.sqlite"

            local expected="$EXPECTED_OUT/test${testnum}.out"
            if $UPDATE_MODE; then
                cp "$actual" "$expected"
                echo -e "${YELLOW}UPDATED${NC}"
                PASS=$((PASS + 1))
            elif [ -f "$expected" ]; then
                if diff -q --strip-trailing-cr "$actual" "$expected" > /dev/null 2>&1; then
                    echo -e "${GREEN}PASS${NC}"
                    PASS=$((PASS + 1))
                else
                    echo -e "${RED}FAIL${NC} (output mismatch)"
                    diff --unified=3 --strip-trailing-cr "$expected" "$actual" | head -20
                    FAIL=$((FAIL + 1))
                    FAILURES="$FAILURES\n  Test $testnum ($label)"
                fi
            else
                echo -e "${GREEN}PASS${NC} (no output check)"
                PASS=$((PASS + 1))
            fi
            ;;
    esac
}

echo "========================================"
echo "  RPG Compiler Test Suite"
echo "========================================"
echo ""

# Standalone unit check for src/fixed_columns.h's extractCol() — not an
# RPG program, compiled and run directly (bypasses rpgc entirely, since
# this tests a compiler-internals header). Catches column-number
# transcription bugs before any fixed-format parsing logic depends on
# them; see tests/test_fixed_columns.cpp for what it checks.
printf "%-45s " "fixed_columns: extractCol() column data"
if "$CXX" -std=c++17 -Isrc -o "$TMPDIR/test_fixed_columns" tests/test_fixed_columns.cpp 2>"$TMPDIR/fixed_columns_err.txt" \
    && "$TMPDIR/test_fixed_columns" >"$TMPDIR/fixed_columns_out.txt" 2>&1; then
    echo -e "\033[0;32mPASS\033[0m"
    PASS=$((PASS + 1))
else
    echo -e "\033[0;31mFAIL\033[0m"
    cat "$TMPDIR/fixed_columns_err.txt" "$TMPDIR/fixed_columns_out.txt" 2>/dev/null | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAILURES="$FAILURES\n  fixed_columns: extractCol() column data"
fi

# Tests 01-10: Core language
run_test "01" "Hello World" "$TESTDIR/test01_hello.rpgle" "run"
run_test "02" "Arithmetic" "$TESTDIR/test02_arithmetic.rpgle" "run"
run_test "03" "Types" "$TESTDIR/test03_types.rpgle" "run"
run_test "04" "BIFs" "$TESTDIR/test04_bifs.rpgle" "run"
run_test "05" "IF" "$TESTDIR/test05_if.rpgle" "run"
run_test "06" "Loops" "$TESTDIR/test06_loops.rpgle" "run"
run_test "07" "Select" "$TESTDIR/test07_select.rpgle" "run"
run_test "08" "Procedures" "$TESTDIR/test08_procedures.rpgle" "run"
run_test "09" "Data Structures" "$TESTDIR/test09_datastructs.rpgle" "run"
run_test "10" "Expanded BIFs" "$TESTDIR/test10_bifs_expanded.rpgle" "run"

# Test 11: Error reporting (multiple sub-tests)
for errfile in $TESTDIR/test11[a-z]*.rpgle; do
    name=$(basename "$errfile" .rpgle)
    run_test "${name#test}" "$name" "$errfile" "error"
done

# Tests 12-76: Language features
run_test "12" "Monitor" "$TESTDIR/test12_monitor.rpgle" "run"
run_test "13" "Subroutines" "$TESTDIR/test13_subroutines.rpgle" "run"
run_test "14" "Indicators" "$TESTDIR/test14_indicators.rpgle" "run"
run_test "15" "DOU Loop" "$TESTDIR/test15_dou.rpgle" "run"
run_test "16" "/COPY Include" "$TESTDIR/test16_copy.rpgle" "run"
run_test "17" "Named Constants" "$TESTDIR/test17_constants.rpgle" "run"
run_test "18" "Date/Time" "$TESTDIR/test18_datetime.rpgle" "run"
run_test "19" "Math BIFs" "$TESTDIR/test19_math_bifs.rpgle" "run"
run_test "20" "Memory BIFs" "$TESTDIR/test20_memory_bifs.rpgle" "run"
run_test "21" "%PARMS" "$TESTDIR/test21_parms.rpgle" "run"
run_test "22" "%STATUS/%ERROR" "$TESTDIR/test22_status_error.rpgle" "run"
run_test "23" "RESET/CLEAR" "$TESTDIR/test23_reset_clear.rpgle" "run"
run_test "24" "%MAX/%MIN" "$TESTDIR/test24_max_min.rpgle" "run"
run_test "25" "DCL-F" "$TESTDIR/test25_dclf.rpgle" "run"
run_test "26" "Pointers" "$TESTDIR/test26_pointers.rpgle" "run"
run_test "27" "Arrays" "$TESTDIR/test27_arrays.rpgle" "run"
run_test "28" "Conditional Compilation" "$TESTDIR/test28_conditional.rpgle" "run"
run_test "29" "DCL-SUBF/DCL-PARM" "$TESTDIR/test29_dclsubf_parm.rpgle" "run"
run_test "30" "LIKE" "$TESTDIR/test30_like.rpgle" "run"
run_test "31" "LOOKUP and SORTA" "$TESTDIR/test31_lookup_sorta.rpgle" "run"
run_test "32" "EDITC/EDITW" "$TESTDIR/test32_editc_editw.rpgle" "run"
run_test "33" "REPLACE" "$TESTDIR/test33_replace.rpgle" "run"
run_test "34" "CHECK/CHECKR" "$TESTDIR/test34_check.rpgle" "run"
run_test "35" "EVAL-CORR" "$TESTDIR/test35_evalcorr.rpgle" "run"
run_test "36" "DS Params" "$TESTDIR/test36_ds_params.rpgle" "run"
run_test "37" "*INZSR" "$TESTDIR/test37_inzsr.rpgle" "run"
run_test "38" "CTL-OPT" "$TESTDIR/test38_ctlopt.rpgle" "run"
run_test "39" "Figurative Constants" "$TESTDIR/test39_figconst.rpgle" "run"
run_test "40" "EVALR/LEAVESR" "$TESTDIR/test40_evalr_leavesr.rpgle" "run"
run_test "41" "String/Math BIFs" "$TESTDIR/test41_string_bifs.rpgle" "run"
run_test "42" "ON-EXIT" "$TESTDIR/test42_onexit.rpgle" "run"
run_test "43" "STATIC" "$TESTDIR/test43_static.rpgle" "run"
run_test "44" "ALLOC/DEALLOC" "$TESTDIR/test44_alloc.rpgle" "run"
run_test "45" "Array BIFs" "$TESTDIR/test45_array_bifs.rpgle" "run"
run_test "46" "OPTIONS(*NOPASS)" "$TESTDIR/test46_options.rpgle" "run"
run_test "47" "TEST Opcode" "$TESTDIR/test47_test.rpgle" "run"
run_test "48" "NOMAIN Module" "$TESTDIR/test48_nomain.rpgle" "compile-only"
run_test "49" "EXTPROC/IMPORT" "$TESTDIR/test49_extproc.rpgle" "run" "$TMPDIR/test48.o"
run_test "50" "Numeric BIFs" "$TESTDIR/test50_numeric_bifs.rpgle" "run"
run_test "51" "String BIFs" "$TESTDIR/test51_string_bifs.rpgle" "run"
run_test "52" "Array BIFs" "$TESTDIR/test52_array_bifs.rpgle" "run"
run_test "53" "Date/Time BIFs" "$TESTDIR/test53_datetime_bifs.rpgle" "run"
run_test "54" "Memory/Pointer BIFs" "$TESTDIR/test54_memory_bifs.rpgle" "run"
run_test "55" "Figurative Constants" "$TESTDIR/test55_figconst.rpgle" "run"
run_test "56" "MAIN(procname)" "$TESTDIR/test56_ctlopt_main.rpgle" "run"
run_test "57" "DATFMT/TIMFMT" "$TESTDIR/test57_datfmt.rpgle" "run"
run_test "58" "FOR-EACH and IN" "$TESTDIR/test58_foreach_in.rpgle" "run"
run_test "59" "%PASSED/%OMITTED" "$TESTDIR/test59_passed_omitted.rpgle" "run"
run_test "60" "Data Types" "$TESTDIR/test60_datatypes.rpgle" "run"
run_test "61" "No **FREE" "$TESTDIR/test61_no_free.rpgle" "run"
run_test "62" "OVERLAY/POS" "$TESTDIR/test62_overlay_pos.rpgle" "run"
run_test "63" "PREFIX" "$TESTDIR/test63_prefix.rpgle" "run"
run_test "64" "OPTIONS(*OMIT)" "$TESTDIR/test64_omit.rpgle" "run"
run_test "65" "DFTACTGRP/ACTGRP" "$TESTDIR/test65_actgrp.rpgle" "run"
run_test "66" "*PSSR" "$TESTDIR/test66_pssr.rpgle" "run"
run_test "67" "*PSSR Error" "$TESTDIR/test67_pssr_error.rpgle" "run"
run_test "68" "Bitwise & Power" "$TESTDIR/test68_bitwise_power.rpgle" "run"
run_test "69" "%SCANR" "$TESTDIR/test69_scanr.rpgle" "run"
run_test "70" "%EDITFLT & %UNSH" "$TESTDIR/test70_editflt_unsh.rpgle" "run"
run_test "71" "Enum & Boolean" "$TESTDIR/test71_enum_boolean.rpgle" "run"
run_test "72" "DIM(*VAR)" "$TESTDIR/test72_dim_var.rpgle" "run"
run_test "73" "Date Formats" "$TESTDIR/test73_date_formats.rpgle" "run"
run_test "74" "%CONCAT" "$TESTDIR/test74_concat.rpgle" "run"
run_test "75" "%TLOOKUP & %ELEM" "$TESTDIR/test75_tlookup_elem.rpgle" "run"
run_test "76" "DS DIM(*VAR)" "$TESTDIR/test76_ds_dim_var.rpgle" "run"

# SQL tests (compile + run with SQLite)
run_test "77" "Embedded SQL" "$TESTDIR/test77_exec_sql.sqlrpgle" "run-sql"
run_test "78" "SQL in Procedures" "$TESTDIR/test78_exec_sql_proc.sqlrpgle" "run-sql"
run_test "79" "SQL Core Statements" "$TESTDIR/test79_sql_core.sqlrpgle" "run-sql"
run_test "80" "SQL Cursors" "$TESTDIR/test80_sql_cursors.sqlrpgle" "run-sql"
run_test "81" "Dynamic SQL" "$TESTDIR/test81_sql_dynamic.sqlrpgle" "run-sql"
run_test "82" "SQL Advanced" "$TESTDIR/test82_sql_advanced.sqlrpgle" "run-sql"
run_test "83" "SQL Multi-row" "$TESTDIR/test83_sql_multirow.sqlrpgle" "run-sql"
run_test "84" "SQL Connect" "$TESTDIR/test84_sql_connect.sqlrpgle" "run-sql"

# Test 85: %GETENV (run but no output check — env-dependent)
run_test "85" "%%GETENV" "$TESTDIR/test85_getenv.rpgle" "run"

# Test 86: SQL end-to-end
run_test "86" "SQL End-to-End" "$TESTDIR/test86.sqlrpgle" "run-sql"

# Tests 87-89: XML-INTO
run_test "87" "XML-INTO" "$TESTDIR/test87.rpgle" "run"
run_test "88" "XML-INTO Array DS" "$TESTDIR/test88.rpgle" "run"
run_test "89" "XML-INTO Path+Nested" "$TESTDIR/test89.rpgle" "run"

# Tests 90-91: PSDS
run_test "90" "PSDS Basic" "$TESTDIR/test90_psds_basic.rpgle" "run"
run_test "91" "PSDS + MONITOR" "$TESTDIR/test91_psds_monitor.rpgle" "run"

# Tests 92-93: Data Areas
run_test "92" "Data Area *LDA round-trip" "$TESTDIR/test92_data_area_lda.rpgle" "run"
run_test "93" "Data Area named" "$TESTDIR/test93_data_area_named.rpgle" "run"

# Tests 94-95: Operation Extenders
run_test "94" "Extender (H) Half-Adjust" "$TESTDIR/test94_extender_h.rpgle" "run"
run_test "95" "Extender (E) Error" "$TESTDIR/test95_extender_e.rpgle" "run"

# Tests 96-98: Data Area %STATUS codes
_DA_DIR="$HOME/.rpgc/da"
mkdir -p "$_DA_DIR"

# 96: status 401 — data area file must not exist
rm -f "$_DA_DIR/NOSUCHDA96"
run_test "96" "DA Status 401 (not found)" "$TESTDIR/test96_da_status401.rpgle" "run"

# 97: status 415 — file exists but no read permission
# Skip when running as root (chmod 000 has no effect) or on Windows (chmod is a no-op on NTFS)
printf '%-10s' 'TESTDATA' > "$_DA_DIR/RPGCTEST97DA"
chmod 000 "$_DA_DIR/RPGCTEST97DA"
if [ -r "$_DA_DIR/RPGCTEST97DA" ]; then
    printf "Test %s: %-35s " "97" "DA Status 415 (cannot read)"
    echo -e "${YELLOW}SKIP${NC} (cannot restrict permissions in this environment)"
    PASS=$((PASS + 1))
else
    run_test "97" "DA Status 415 (cannot read)" "$TESTDIR/test97_da_status415.rpgle" "run"
fi
chmod 644 "$_DA_DIR/RPGCTEST97DA" 2>/dev/null; rm -f "$_DA_DIR/RPGCTEST97DA"

# 98: status 413 — file exists but no write permission
# Skip when running as root (chmod 444 has no effect) or on Windows
printf '%-10s' 'TESTDATA' > "$_DA_DIR/RPGCTEST98DA"
chmod 444 "$_DA_DIR/RPGCTEST98DA"
if [ -w "$_DA_DIR/RPGCTEST98DA" ]; then
    printf "Test %s: %-35s " "98" "DA Status 413 (cannot write)"
    echo -e "${YELLOW}SKIP${NC} (cannot restrict permissions in this environment)"
    PASS=$((PASS + 1))
else
    run_test "98" "DA Status 413 (cannot write)" "$TESTDIR/test98_da_status413.rpgle" "run"
fi
chmod 644 "$_DA_DIR/RPGCTEST98DA" 2>/dev/null; rm -f "$_DA_DIR/RPGCTEST98DA"

# 99: DATA-INTO — parse JSON into DS
run_test "99" "DATA-INTO JSON parsing" "$TESTDIR/test99_data_into.rpgle" "run"

# 100: DATA-GEN — generate JSON from DS
run_test "100" "DATA-GEN JSON generation" "$TESTDIR/test100_data_gen.rpgle" "run"

# 101: *USER figurative constant
run_test "101" "*USER figurative constant" "$TESTDIR/test101_user.rpgle" "run"

# 102: SND-MSG
run_test "102" "SND-MSG" "$TESTDIR/test102_snd_msg.rpgle" "run"

# 103-106: Record Level Access (RLA) — file I/O opcodes via ODBC
run_test "103" "RLA CHAIN / %FOUND" "$TESTDIR/test103_rla_chain.rpgle" "run-sql"
run_test "104" "RLA READ sequential" "$TESTDIR/test104_rla_read.rpgle" "run-sql"
run_test "105" "RLA WRITE/UPDATE/DELETE" "$TESTDIR/test105_rla_write_upd_del.rpgle" "run-sql"
run_test "106" "RLA SETLL/READE" "$TESTDIR/test106_rla_setll_reade.rpgle" "run-sql"

# 107-108: rpgc.conf implicit connection (no EXEC SQL CONNECT in source)
run_test "107" "SQL via rpgc.conf (no CONNECT)" "$TESTDIR/test107_sql_conf.sqlrpgle" "run-sql-conf"
run_test "108" "RLA via rpgc.conf (no CONNECT)" "$TESTDIR/test108_rla_conf.rpgle" "run-sql-conf"

# 109: SQL indicator variables
run_test "109" "SQL indicator variables" "$TESTDIR/test109_sql_indicator.sqlrpgle" "run-sql"

# 110: OVERLOAD — procedure overloading
run_test "110" "OVERLOAD procedures" "$TESTDIR/test110_overload.rpgle" "run"

# 111: %ELEM(*ALLOC) / %ELEM(*KEEP) — varying array capacity control
run_test "111" "%ELEM(*ALLOC)/%ELEM(*KEEP)" "$TESTDIR/test111_elem_alloc.rpgle" "run"

# 112: DATA-INTO with %PARSER('CSV')
run_test "112" "DATA-INTO CSV parsing" "$TESTDIR/test112_data_into_csv.rpgle" "run"

# 113: DATA-GEN with %PARSER('CSV')
run_test "113" "DATA-GEN CSV generation" "$TESTDIR/test113_data_gen_csv.rpgle" "run"

# 114: DATA-INTO / DATA-GEN with explicit %PARSER('JSON')
run_test "114" "DATA-INTO/GEN %PARSER('JSON')" "$TESTDIR/test114_data_into_json_parser.rpgle" "run"

# 115: DUMP opcode
run_test "115" "DUMP opcode" "$TESTDIR/test115_dump.rpgle" "run"

# ── Fixed-format frontend (Phase 1: H/F/D + /free-bridge C-spec) ─────────
# 116: H+D specs only, no I/O, no C-spec — confirms sniff→dispatch→AST
# construction→codegen→link before the /free bridge is involved at all.
# Also exercises the comment-line skip (col 7 = '*') mid D-spec block.
run_test "116" "Fixed-format H+D only" "$TESTDIR/test116_fixed_hd.rpgle" "run"

# 117: H+D+C(/free) — direct fixed-format analogue of test01_hello.rpgle;
# first test exercising the /free bridge end-to-end with real DSPLY output.
run_test "117" "Fixed-format H+D+C(/free) hello" "$TESTDIR/test117_fixed_free_hello.rpgle" "run"

# 118: H+F+D+C full Phase 1 milestone — fixed F-spec DISK file with
# keyword-tail continuation, D-spec name continuation ("..."), CHAIN/
# %FOUND inside a /free block.
run_test "118" "Fixed-format H+F+D+C DISK CHAIN" "$TESTDIR/test118_fixed_rla_chain.rpgle" "run-sql-conf"

# 119: deliberate syntax error inside a fixed-format /free block — confirms
# get_parse_error_count() + main.cpp's error gate work identically for the
# fixed-format frontend.
run_test "119" "Fixed-format /free syntax error" "$TESTDIR/test119_fixed_free_error.rpgle" "error"

# ── Fixed-format frontend Phase 2: D-spec depth (VARCHAR, DS DIM, OVERLAY) ──
# 120: VARYING on a standalone field — VARCHAR starts empty (%LEN=0),
# plain CHAR starts space-padded to its declared length (%LEN=length).
run_test "120" "Fixed-format VARCHAR standalone" "$TESTDIR/test120_fixed_varchar.rpgle" "run"

# 121: VARYING on a DS subfield — round-trip assign/read-back check (DS
# subfield CHAR/VARCHAR have no differentiated codegen behavior currently,
# true for free-format too, so this confirms parsing + usability only).
run_test "121" "Fixed-format VARCHAR DS subfield" "$TESTDIR/test121_fixed_varchar_subfield.rpgle" "run"

# 122: DISK CHAIN with a real VARCHAR key field — closes the loop on the
# gap Phase 1's test118 worked around with an integer key.
run_test "122" "Fixed-format VARCHAR DISK CHAIN key" "$TESTDIR/test122_fixed_rla_chain_varchar.rpgle" "run-sql-conf"

# 123: DIM(n) array of DS on a fixed-format D-spec DS line.
run_test "123" "Fixed-format DIM(n) array of DS" "$TESTDIR/test123_fixed_ds_dim.rpgle" "run"

# 124: per-subfield OVERLAY(field)/OVERLAY(field:pos) and POS(n) — fixed-
# format analogue of test62_overlay_pos.rpgle (identical C-spec logic).
run_test "124" "Fixed-format subfield OVERLAY/POS" "$TESTDIR/test124_fixed_overlay.rpgle" "run"

# ── Fixed-format frontend: traditional/extended-factor-2 C-spec ──────────
# Native column-based C-spec (Factor1/Opcode/Factor2/Result and Extended
# Factor 2), transpiled line-by-line into free-form-equivalent text and
# bridged through the same parse_free_block() explicit /free blocks use
# (see src/fixed_cspec.h/.cpp) — see TODO.md "Fixed-Format Source Support
# — Next Steps" item #1.
run_test "125" "Fixed C-spec: IF/ELSEIF/ELSE/ENDIF" "$TESTDIR/test125_fixed_cspec_if.rpgle" "run"
run_test "126" "Fixed C-spec: DOW/DOU/ENDDO" "$TESTDIR/test126_fixed_cspec_dow_dou.rpgle" "run"
run_test "127" "Fixed C-spec: FOR/ENDFOR (TO/DOWNTO/BY)" "$TESTDIR/test127_fixed_cspec_for.rpgle" "run"
run_test "128" "Fixed C-spec: SELECT/WHEN/OTHER/ENDSL" "$TESTDIR/test128_fixed_cspec_select.rpgle" "run"
run_test "129" "Fixed C-spec: BEGSR/EXSR/ENDSR" "$TESTDIR/test129_fixed_cspec_subr.rpgle" "run"
run_test "130" "Fixed C-spec: EVAL/EVALR/CALLP/LEAVE/ITER" "$TESTDIR/test130_fixed_cspec_eval_callp.rpgle" "run"
run_test "131" "Fixed C-spec: CLEAR/RESET/DSPLY/SORTA" "$TESTDIR/test131_fixed_cspec_clear_sorta.rpgle" "run"
run_test "132" "Fixed C-spec: MONITOR/ON-ERROR/ENDMON" "$TESTDIR/test132_fixed_cspec_monitor.rpgle" "run"
run_test "133" "Fixed C-spec: Extended-Factor-2 continuation" "$TESTDIR/test133_fixed_cspec_continuation.rpgle" "run"
run_test "134" "Fixed C-spec: mixed with explicit /free block" "$TESTDIR/test134_fixed_cspec_mixed_free.rpgle" "run"
run_test "135" "Fixed C-spec: reject non-blank control level" "$TESTDIR/test135_fixed_cspec_err_ctllevel.rpgle" "error"
run_test "136" "Fixed C-spec: reject misaligned cond indicator" "$TESTDIR/test136_fixed_cspec_err_indicator.rpgle" "error"
run_test "137" "Fixed C-spec: reject deferred opcode (XML-SAX)" "$TESTDIR/test137_fixed_cspec_err_deferred.rpgle" "error"
run_test "138" "Fixed C-spec: reject legacy opcode (COMP)" "$TESTDIR/test138_fixed_cspec_err_legacy.rpgle" "error"

# ── Fixed-format frontend: /COPY and /INCLUDE ─────────────────────────────
# Native /COPY/INCLUDE support outside /free blocks — a recursive,
# depth-limited line-splicing pass that runs once before spec-type
# dispatch begins (see expandCopyDirectives() in src/fixed_reader.cpp),
# matching the free-format lexer's own /COPY convention exactly (literal
# filename, opened relative to CWD). Lines inside an explicit /free block
# are left untouched — parse_free_block() re-invokes the real free-format
# lexer there, which already handles /COPY itself. See TODO.md "Fixed-
# Format Source Support — Next Steps" item #2.
run_test "139" "Fixed-format /COPY: D-spec copybook" "$TESTDIR/test139_fixed_copy_dspec.rpgle" "run"
run_test "140" "Fixed-format /INCLUDE: C-spec copybook mid-run" "$TESTDIR/test140_fixed_copy_cspec.rpgle" "run"
run_test "141" "Fixed-format /COPY: nested copybooks" "$TESTDIR/test141_fixed_copy_nested.rpgle" "run"
run_test "142" "Fixed-format /COPY inside an explicit /free block" "$TESTDIR/test142_fixed_copy_in_free.rpgle" "run"
run_test "143" "Fixed-format /COPY: missing file rejected" "$TESTDIR/test143_fixed_copy_err_missing.rpgle" "error"

# ── Fixed-format frontend: native C-spec RLA opcodes (item 1b) ───────────
# CHAIN/READ/READP/READE/READPE/WRITE/UPDATE/DELETE/SETLL/SETGT in native
# column-based C-spec — same transpile-and-bridge mechanism as item #1,
# just extending the TRADITIONAL-shape opcode table in src/fixed_cspec.cpp.
# Direct fixed-format analogues of tests 103-106. See TODO.md "Fixed-
# Format Source Support — Next Steps" item #1b.
run_test "144" "Fixed C-spec: CHAIN by key, %FOUND" "$TESTDIR/test144_fixed_cspec_chain.rpgle" "run-sql-conf"
run_test "145" "Fixed C-spec: READ sequential, %EOF" "$TESTDIR/test145_fixed_cspec_read.rpgle" "run-sql-conf"
run_test "146" "Fixed C-spec: WRITE/UPDATE/DELETE" "$TESTDIR/test146_fixed_cspec_write_upd_del.rpgle" "run-sql-conf"
run_test "147" "Fixed C-spec: SETLL/READE" "$TESTDIR/test147_fixed_cspec_setll_reade.rpgle" "run-sql-conf"

# ── Fixed-format frontend: traditional legacy opcodes (item #3 V1) ───────
# GOTO/TAG (new AST + parser.y grammar, gated by g_allow_goto_tag — see
# free_bridge.h — since SC09-2508 explicitly has no free-form syntax for
# either) plus ADD/SUB/MULT/DIV/Z-ADD/Z-SUB (transpiled to the EVAL
# equivalent the manual itself prescribes). See TODO.md "Fixed-Format
# Source Support — Next Steps" item #3.
run_test "148" "Fixed C-spec: GOTO/TAG backward loop + forward skip" "$TESTDIR/test148_fixed_cspec_goto_tag.rpgle" "run"
run_test "149" "Fixed C-spec: GOTO/TAG inside BEGSR" "$TESTDIR/test149_fixed_cspec_goto_in_begsr.rpgle" "run"
run_test "150" "Fixed C-spec: ADD/SUB/MULT/DIV (both Factor 1 forms)" "$TESTDIR/test150_fixed_cspec_arith.rpgle" "run"
run_test "151" "Fixed C-spec: Z-ADD/Z-SUB" "$TESTDIR/test151_fixed_cspec_zadd_zsub.rpgle" "run"
run_test "152" "Fixed C-spec: reject GOTO inside explicit /free block" "$TESTDIR/test152_fixed_cspec_err_goto_in_free.rpgle" "error"
run_test "153" "Fixed C-spec: reject deferred legacy opcode (CALL)" "$TESTDIR/test153_fixed_cspec_err_call_deferred.rpgle" "error"

# ── Fixed-format frontend: program-described I-spec/O-spec (item #4) ─────
# Program-described (byte-position) file I/O — an entirely new raw
# fixed-length-record runtime (src/rpg_flatfile_runtime.h), separate from
# RLA's SQL/ODBC-backed CHAIN/READ/WRITE/etc. The flat-file runtime opens
# paths relative to CWD ("<lowercased-DCL-F-name>.txt"), and this script
# never cds, so these land at the repo root — rm -f first for a clean
# slate each run (the runtime appends rather than truncating, so a stale
# file from a previous run would otherwise leak extra records in). See
# TODO.md "Fixed-Format Source Support — Next Steps" item #4.
rm -f "$TESTDIR/../testfl154.txt"
run_test "154" "Fixed I-spec: single record type, sequential READ" "$TESTDIR/test154_fixed_ispec_single.rpgle" "run"
rm -f "$TESTDIR/../testfl155.txt"
run_test "155" "Fixed I-spec: multi record type dispatch" "$TESTDIR/test155_fixed_ispec_multi.rpgle" "run"
rm -f "$TESTDIR/../testfl156.txt"
run_test "156" "Fixed I-spec: field indicators (plus/minus/zero)" "$TESTDIR/test156_fixed_ispec_field_ind.rpgle" "run"
rm -f "$TESTDIR/../testfl157.txt"
run_test "157" "Fixed I-spec: UPDATE rewrites record in place" "$TESTDIR/test157_fixed_ispec_update.rpgle" "run"
rm -f "$TESTDIR/../testfl158.txt"
run_test "158" "Fixed O-spec: field placement + edit code" "$TESTDIR/test158_fixed_ospec_editcode.rpgle" "run"
run_test "159" "Fixed I-spec: reject zone record-ID test" "$TESTDIR/test159_fixed_ispec_err_zone.rpgle" "error"
run_test "160" "Fixed I-spec: reject matching fields (M1)" "$TESTDIR/test160_fixed_ispec_err_matching.rpgle" "error"

# ── Fixed-format frontend: per-subfield LIKE/DIM (item #5) ───────────────
# See TODO.md "Fixed-Format Source Support — Next Steps" item #5. Test 163
# is free-format — it's the one that actually exercises the new ds_field
# grammar productions (declaring LIKE/DIM on a subfield); the fixed-format
# D-spec reader builds DSField structs directly in C++, bypassing the
# bison grammar entirely, so 161/162 only exercise the ds.field(idx) /
# LIKE-resolution *codegen* path, not the new parser.y productions.
run_test "161" "Fixed D-spec: per-subfield DIM(n)" "$TESTDIR/test161_fixed_subf_dim.rpgle" "run"
run_test "162" "Fixed D-spec: per-subfield LIKE(field)" "$TESTDIR/test162_fixed_subf_like.rpgle" "run"
run_test "163" "Free-format: per-subfield LIKE/DIM declaration + access" "$TESTDIR/test163_subfield_like_dim.rpgle" "run"

# ── Fixed C-spec: conditioning indicators (positions 9-11) ───────────────
# See TODO.md "Fixed C-spec — Deferred Fast-Follow" item #1. Each
# conditioned statement is transpiled into an IF/ENDIF wrapper, so only
# self-contained statements can carry one — 165 pins the block-structure
# rejection, 166 the indicators this compiler has no representation for,
# and 136 (above) the column-misalignment case.
run_test "164" "Fixed C-spec: conditioning indicators" "$TESTDIR/test164_fixed_cspec_cond_ind.rpgle" "run"
run_test "165" "Fixed C-spec: reject cond ind on block opcode" "$TESTDIR/test165_fixed_cspec_err_cond_block.rpgle" "error"
run_test "166" "Fixed C-spec: reject unsupported cond indicator" "$TESTDIR/test166_fixed_cspec_err_cond_ind_name.rpgle" "error"
run_test "167" "Fixed C-spec: AN/OR indicator groups" "$TESTDIR/test167_fixed_cspec_cond_anor.rpgle" "run"
run_test "168" "Fixed C-spec: reject orphan AN line" "$TESTDIR/test168_fixed_cspec_err_anor_orphan.rpgle" "error"
run_test "169" "Fixed C-spec: reject dangling cond ind line" "$TESTDIR/test169_fixed_cspec_err_anor_dangling.rpgle" "error"

# ── Fixed C-spec: MOVE/MOVEL ─────────────────────────────────────────────
# 170 is the character-to-character move; 191-196 the numeric forms (see
# the block further down). The rejections here are the ones that survive:
# 171 a date result field and 172 the factor-1 date/time-format form (both
# still deferred, see TODO.md), 173 that MOVE has no free-format syntax at
# all. 171 also pins that the check happens in codegen — the transpiler has
# no symbol table, so only codegen can see an operand's declared type.
run_test "170" "Fixed C-spec: MOVE/MOVEL character move" "$TESTDIR/test170_fixed_cspec_move.rpgle" "run"
run_test "171" "Fixed C-spec: reject MOVE to date field" "$TESTDIR/test171_fixed_cspec_err_move_date.rpgle" "error"
run_test "172" "Fixed C-spec: reject MOVE date/time format" "$TESTDIR/test172_fixed_cspec_err_move_datefmt.rpgle" "error"
run_test "173" "Free-format: reject MOVE (fixed-format only)" "$TESTDIR/test173_move_err_free_format.rpgle" "error"

# ── Fixed C-spec: CALL/PLIST/PARM ────────────────────────────────────────
# See TODO.md "Fixed C-spec — Deferred Fast-Follow" item #3. A traditional
# CALL has no prototype, so codegen synthesizes the callee's signature
# from the PARM operands' declared types; 174 is the module it links
# against (same pattern as tests 48/49), and 197-198 link against it too.
# 176 pins that a PLIST must declare at least one parameter.
run_test "174" "CALL callee module (NOMAIN)" "$TESTDIR/test174_call_callee_module.rpgle" "compile-only"
run_test "175" "Fixed C-spec: CALL/PARM program call" "$TESTDIR/test175_fixed_cspec_call_parm.rpgle" "run" "$TMPDIR/test174.o"
run_test "176" "Fixed C-spec: reject PLIST with no PARM" "$TESTDIR/test176_fixed_cspec_err_plist.rpgle" "error"
run_test "177" "Fixed C-spec: reject dynamic CALL name" "$TESTDIR/test177_fixed_cspec_err_call_dynamic.rpgle" "error"
run_test "178" "Fixed C-spec: reject PARM without CALL" "$TESTDIR/test178_fixed_cspec_err_parm_orphan.rpgle" "error"
run_test "179" "Free-format: reject CALL (fixed-format only)" "$TESTDIR/test179_call_err_free_format.rpgle" "error"

# ── Fixed C-spec: modern opcodes reachable from native columns ───────────
# XML-INTO / DATA-INTO / DATA-GEN / SND-MSG are extended-factor-2 shaped,
# so columns 36-80 (plus continuation) carry their %XML/%DATA/%PARSER
# expression straight through to the free-format parser — all four share
# that one code path with no per-opcode logic, so 180 covers it with
# DATA-INTO (continued across a line) and SND-MSG. 181 pins ON-EXIT,
# which fixed columns can never reach: it is valid only inside a
# DCL-PROC, and fixed-format source has no P-spec to declare one.
run_test "180" "Fixed C-spec: DATA-INTO / SND-MSG" "$TESTDIR/test180_fixed_cspec_modern_opcodes.rpgle" "run"
run_test "181" "Fixed C-spec: reject ON-EXIT (proc-only)" "$TESTDIR/test181_fixed_cspec_err_on_exit.rpgle" "error"

# ── Fixed C-spec: CASxx / CABxx ──────────────────────────────────────────
# CASxx lines chain like SELECT/WHEN, so a group transpiles to one
# IF/ELSEIF/ELSE closed by ENDCS; CABxx is self-contained (a comparison
# guarding a GOTO). 183-185 pin the orphan ENDCS, the unclosed group, and
# an unrecognized comparison mnemonic.
run_test "182" "Fixed C-spec: CASxx chain + CABxx branch" "$TESTDIR/test182_fixed_cspec_cas_cab.rpgle" "run"
run_test "183" "Fixed C-spec: reject orphan ENDCS" "$TESTDIR/test183_fixed_cspec_err_endcs_orphan.rpgle" "error"
run_test "184" "Fixed C-spec: reject unclosed CASxx group" "$TESTDIR/test184_fixed_cspec_err_cas_unclosed.rpgle" "error"
run_test "185" "Fixed C-spec: reject bad CASxx mnemonic" "$TESTDIR/test185_fixed_cspec_err_cas_mnemonic.rpgle" "error"

# ── Fixed C-spec: COMP ───────────────────────────────────────────────────
# The one opcode allowed to fill the resulting-indicator columns (71-76),
# because unlike everywhere else those indicators ARE its whole effect and
# *INnn is an assignable target here. 186 reads the results back through
# conditioning indicators; 187 rejects a COMP that sets nothing.
run_test "186" "Fixed C-spec: COMP resulting indicators" "$TESTDIR/test186_fixed_cspec_comp.rpgle" "run"
run_test "187" "Fixed C-spec: reject COMP with no indicators" "$TESTDIR/test187_fixed_cspec_err_comp_noind.rpgle" "error"

# ── Fixed C-spec: embedded SQL in fixed columns ──────────────────────────
# C/EXEC SQL ... C+ ... C/END-EXEC. The gathered text is emitted as one
# free-form `EXEC SQL ...;`, so the lexer's existing <SQL> start condition
# captures it exactly as it does for free-format source — no SQL parsing
# was added. 189/190 pin the orphan C/END-EXEC and the unterminated block.
run_test "188" "Fixed C-spec: embedded SQL (C/EXEC SQL)" "$TESTDIR/test188_fixed_cspec_exec_sql.sqlrpgle" "run-sql"
run_test "189" "Fixed C-spec: reject orphan C/END-EXEC" "$TESTDIR/test189_fixed_cspec_err_endexec_orphan.sqlrpgle" "error"
run_test "190" "Fixed C-spec: reject unterminated EXEC SQL" "$TESTDIR/test190_fixed_cspec_err_sql_unterminated.sqlrpgle" "error"

# ── Fixed C-spec: MOVE/MOVEL with a numeric operand ──────────────────────
# TODO.md "Fixed C-spec — Deferred Fast-Follow" item #1. A numeric MOVE is
# a DIGIT move against declared digit counts, with both operands' decimal
# positions ignored (SC09-2508 p.633) — so these tests are written as
# digit-alignment checks, not arithmetic ones. 191 numeric-to-numeric
# (including the manual's own 1.00 -> 10.0 example), 192 character-to-
# numeric, 193 numeric-to-character, 196 the invalid-digit data exception.
# 194-195 pin the two operands that stay refused: float (the manual
# disallows it) and a decimal literal (its digit count is unrecoverable).
run_test "191" "Fixed C-spec: MOVE numeric to numeric" "$TESTDIR/test191_fixed_cspec_move_num.rpgle" "run"
run_test "192" "Fixed C-spec: MOVE character to numeric" "$TESTDIR/test192_fixed_cspec_move_char_to_num.rpgle" "run"
run_test "193" "Fixed C-spec: MOVE numeric to character" "$TESTDIR/test193_fixed_cspec_move_num_to_char.rpgle" "run"
run_test "194" "Fixed C-spec: reject MOVE on float field" "$TESTDIR/test194_fixed_cspec_err_move_float.rpgle" "error"
run_test "195" "Fixed C-spec: reject MOVE decimal literal" "$TESTDIR/test195_fixed_cspec_err_move_declit.rpgle" "error"
run_test "196" "Fixed C-spec: MOVE invalid digit -> 907" "$TESTDIR/test196_fixed_cspec_move_data_exc.rpgle" "run"

# ── Fixed C-spec: named PLIST and PARM factor 1/2 ────────────────────────
# The rest of TODO.md's deferred item #2. 197 covers a PLIST defined AFTER
# both CALLs that name it — the case that forces the collect-then-
# substitute pass, since a linear transpiler cannot resolve it in line
# order. 198 covers PARM's optional move-in/move-out operands, and
# 199-202 the rejections that keep a mistake from compiling into a
# silently different call.
run_test "197" "Fixed C-spec: named PLIST" "$TESTDIR/test197_fixed_cspec_plist.rpgle" "run" "$TMPDIR/test174.o"
run_test "198" "Fixed C-spec: PARM factor 1/factor 2" "$TESTDIR/test198_fixed_cspec_parm_f1f2.rpgle" "run" "$TMPDIR/test174.o"
run_test "199" "Fixed C-spec: reject *ENTRY with NOMAIN" "$TESTDIR/test199_fixed_cspec_err_entry_nomain.rpgle" "error"
run_test "200" "Fixed C-spec: reject undefined PLIST name" "$TESTDIR/test200_fixed_cspec_err_plist_undef.rpgle" "error"
run_test "201" "Fixed C-spec: reject duplicate PLIST name" "$TESTDIR/test201_fixed_cspec_err_plist_dup.rpgle" "error"
run_test "202" "Fixed C-spec: reject literal PARM result" "$TESTDIR/test202_fixed_cspec_err_parm_literal.rpgle" "error"

# ── Fixed C-spec: *ENTRY PLIST ───────────────────────────────────────────
# A member with an *ENTRY PLIST compiles to a function named after its own
# FILE — which is why the callee here is tests/ADDTWO.rpgle and not a
# testNNN name: the file name is the program name a caller spells in CALL.
# 204 calls it both ways (inline PARMs and a named PLIST defined after the
# call), so the two halves of this work meet end to end.
run_test "203" "*ENTRY callee module (ADDTWO)" "$TESTDIR/ADDTWO.rpgle" "compile-only"
run_test "204" "Fixed C-spec: *ENTRY PLIST call" "$TESTDIR/test204_fixed_cspec_entry_caller.rpgle" "run" "$TMPDIR/test203.o"
run_test "205" "Fixed C-spec: reject *ENTRY PARM factor 2" "$TESTDIR/test205_fixed_cspec_err_entry_f2.rpgle" "error"
run_test "206" "Fixed C-spec: reject undeclared *ENTRY parm" "$TESTDIR/test206_fixed_cspec_err_entry_undecl.rpgle" "error"
run_test "207" "Fixed C-spec: reject CALL naming *ENTRY" "$TESTDIR/test207_fixed_cspec_err_call_entry.rpgle" "error"

# ── Customer / drop-in tests ─────────────────────────────────────────────
# Drop any .rpgle or .sqlrpgle file into tests/customer/ and it will be
# compile-tested automatically — no registration or expected output needed.
CUSTOMER_DIR="$TESTDIR/customer"
if [ -d "$CUSTOMER_DIR" ]; then
    customer_found=false
    for src in "$CUSTOMER_DIR"/*.rpgle "$CUSTOMER_DIR"/*.sqlrpgle; do
        [ -f "$src" ] || continue
        customer_found=true
        base=$(basename "$src")
        printf "Customer: %-35s " "$base"
        if [[ "$src" == *.sqlrpgle ]]; then
            _err="$TMPDIR/customer_${base}_err.txt"
            if ! $RPGC -S "$src" -o "$TMPDIR/customer_${base}.cpp" 2>"$_err"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$_err"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Customer: $base"
                continue
            fi
            if "$CXX" "${CXXFLAGS_SQL[@]}" -c -o "$TMPDIR/customer_${base}.o" \
                    "$TMPDIR/customer_${base}.cpp" $ODBC_FLAGS 2>"$_err"; then
                echo -e "${GREEN}PASS${NC}"
                PASS=$((PASS + 1))
            else
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$_err"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Customer: $base"
            fi
        else
            _err="$TMPDIR/customer_${base}_err.txt"
            if ! $RPGC -S "$src" -o "$TMPDIR/customer_${base}.cpp" 2>"$_err"; then
                echo -e "${RED}FAIL${NC} (transpile failed)"
                cat "$_err"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Customer: $base"
                continue
            fi
            if "$CXX" "${CXXFLAGS[@]}" -c -o "$TMPDIR/customer_${base}.o" \
                    "$TMPDIR/customer_${base}.cpp" 2>"$_err"; then
                echo -e "${GREEN}PASS${NC}"
                PASS=$((PASS + 1))
            else
                echo -e "${RED}FAIL${NC} (compile failed)"
                cat "$_err"
                FAIL=$((FAIL + 1))
                FAILURES="$FAILURES\n  Customer: $base"
            fi
        fi
    done
    if [ "$customer_found" = false ]; then
        echo "(no files in tests/customer/)"
    fi
fi

echo ""
echo "========================================"
if [ $SKIP -gt 0 ]; then
    echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC}"
else
    echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
fi
echo "========================================"

if [ $FAIL -gt 0 ]; then
    echo -e "\nFailed tests:${FAILURES}"
    exit 1
fi
