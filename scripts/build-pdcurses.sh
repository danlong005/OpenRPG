#!/usr/bin/env bash
# Builds PDCurses (Windows console platform) as a static library using a
# toolchain staged by stage-mingw.sh, and drops it directly into that
# toolchain's target sysroot so `-lpdcurses` / `#include <curses.h>` resolve
# without anything external — the same way rpg_dspf_runtime.h expects on
# Windows (see RPGC_DSPF_FLAGS " -lpdcurses" in src/main.cpp). Used by both
# Windows release jobs in release.yml, after stage-mingw.sh has run.
#
# Usage: build-pdcurses.sh <mingw-dir> <target-triple>
#   mingw-dir: root of a toolchain staged by stage-mingw.sh (must contain
#              bin/<target-triple>-clang.exe and <target-triple>/)
#   target-triple: aarch64-w64-mingw32 | x86_64-w64-mingw32
set -euo pipefail

MINGW_DIR="${1:?usage: build-pdcurses.sh <mingw-dir> <target-triple>}"
TARGET_TRIPLE="${2:?usage: build-pdcurses.sh <mingw-dir> <target-triple>}"

# Pinned so an upstream change can't silently alter what we ship.
PDCURSES_TAG="PDCurses_3_6"

BIN="$MINGW_DIR/bin"
SYSROOT="$MINGW_DIR/$TARGET_TRIPLE"

for exe in "${TARGET_TRIPLE}-clang.exe" "${TARGET_TRIPLE}-llvm-ar.exe"; do
    if [ ! -f "$BIN/$exe" ]; then
        echo "Error: expected $BIN/$exe from stage-mingw.sh, not found" >&2
        exit 1
    fi
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning PDCurses $PDCURSES_TAG..."
git clone --quiet --depth 1 --branch "$PDCURSES_TAG" \
    https://github.com/wmcbrine/PDCurses.git "$WORK_DIR/PDCurses"

# wincon/Makefile at this tag hardcodes `LIBEXE = ar` for the static-lib
# path rather than referencing a variable — there's no AR override to pass
# on the command line. Patch it to use $(AR) so we can point it at our
# bundled llvm-ar instead of depending on some ambient `ar` being on PATH.
sed -i 's/LIBEXE = ar$/LIBEXE = $(AR)/' "$WORK_DIR/PDCurses/wincon/Makefile"
if ! grep -q 'LIBEXE = \$(AR)' "$WORK_DIR/PDCurses/wincon/Makefile"; then
    echo "Error: expected 'LIBEXE = ar' line not found in wincon/Makefile — upstream layout changed" >&2
    exit 1
fi

echo "Building wincon/pdcurses.a for $TARGET_TRIPLE..."
make -C "$WORK_DIR/PDCurses/wincon" \
    CC="$BIN/${TARGET_TRIPLE}-clang.exe" \
    LINK="$BIN/${TARGET_TRIPLE}-clang.exe" \
    AR="$BIN/${TARGET_TRIPLE}-llvm-ar.exe" \
    libs

mkdir -p "$SYSROOT/lib" "$SYSROOT/include"
# -lpdcurses resolves via the standard -l naming convention (lib<name>.a),
# but the PDCurses Makefile names its output bin without that prefix.
cp "$WORK_DIR/PDCurses/wincon/pdcurses.a" "$SYSROOT/lib/libpdcurses.a"
cp "$WORK_DIR/PDCurses/curses.h" "$SYSROOT/include/curses.h"
cp "$WORK_DIR/PDCurses/panel.h" "$SYSROOT/include/panel.h"

echo "Staged libpdcurses.a + curses.h/panel.h into $SYSROOT"
