#!/usr/bin/env bash
# Trims an already-downloaded llvm-mingw release zip down to just what rpgc
# needs to compile+link a single generated .cpp file against one target:
# the driver binaries for that target, the LLVM/Clang shared libraries they
# load, the target's own sysroot (headers/import libs/CRT objects), and the
# common Win32 API headers. Everything else in the upstream release —
# cross-compilers for the other three targets, Python, lldb, clang-tidy/
# format, busybox, dpkg/rpm — is dropped. Cuts a ~724MB release down to
# ~290MB. Used by both Windows release jobs in release.yml.
#
# The zip itself is fetched separately (via `gh release download` in a pwsh
# step) rather than by this script, because it runs inside the MSYS2 shell,
# which — in this project's setup — doesn't inherit the outer Windows PATH,
# so `gh` isn't reachable from here.
#
# Usage: stage-mingw.sh <zip-path> <host-arch> <output-dir>
#   zip-path: path to an already-downloaded llvm-mingw-<tag>-ucrt-<arch>.zip
#   host-arch: x86_64 | aarch64 (must match the zip's own host arch)
#   output-dir: where to place the trimmed toolchain tree
set -euo pipefail

ZIP_PATH="${1:?usage: stage-mingw.sh <zip-path> <x86_64|aarch64> <output-dir>}"
HOST_ARCH="${2:?usage: stage-mingw.sh <zip-path> <x86_64|aarch64> <output-dir>}"
OUT_DIR="${3:?usage: stage-mingw.sh <zip-path> <x86_64|aarch64> <output-dir>}"

case "$HOST_ARCH" in
    x86_64)  TARGET_TRIPLE="x86_64-w64-mingw32" ;;
    aarch64) TARGET_TRIPLE="aarch64-w64-mingw32" ;;
    *) echo "Error: unknown host arch '$HOST_ARCH' (expected x86_64 or aarch64)" >&2; exit 1 ;;
esac

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Extracting $ZIP_PATH..."
unzip -q "$ZIP_PATH" -d "$WORK_DIR"
SRC="$(find "$WORK_DIR" -maxdepth 1 -mindepth 1 -type d -name 'llvm-mingw-*' | head -1)"
if [ -z "$SRC" ]; then
    echo "Error: no llvm-mingw-* directory found inside $ZIP_PATH" >&2
    exit 1
fi

# Drop every target sysroot except the one we're actually bundling, plus
# everything unrelated to compiling/linking a single C++ translation unit.
for d in aarch64-w64-mingw32 x86_64-w64-mingw32 i686-w64-mingw32 armv7-w64-mingw32 arm64ec-w64-mingw32; do
    [ "$d" = "$TARGET_TRIPLE" ] && continue
    rm -rf "${SRC:?}/$d"
done
rm -rf "$SRC"/python "$SRC"/busybox "$SRC"/share
if [ ! -d "$SRC/$TARGET_TRIPLE" ]; then
    echo "Error: expected target sysroot $TARGET_TRIPLE missing after trim" >&2
    exit 1
fi

# Trim bin/: keep only our target's driver wrappers (+ its UWP variant,
# harmless either way), the generic clang/llvm/ld tool binaries, and the
# shared libraries those actually link against at load time.
find "$SRC/bin" -maxdepth 1 -type f \
    ! -name "${TARGET_TRIPLE}-*" \
    ! -name "${TARGET_TRIPLE}uwp-*" \
    ! -name 'clang.exe' ! -name 'clang++.exe' ! -name 'clang-[0-9]*.exe' \
    ! -name 'clang-target-wrapper*' \
    ! -name 'ld.lld.exe' ! -name 'ld' ! -name 'ld-wrapper.sh' \
    ! -name 'llvm-ar.exe' ! -name 'llvm-ranlib.exe' ! -name 'llvm-nm.exe' \
    ! -name 'llvm-rc.exe' ! -name 'llvm-dlltool.exe' ! -name 'llvm-strip.exe' \
    ! -name 'llvm-objcopy.exe' ! -name 'llvm-cvtres.exe' ! -name 'llvm-lib.exe' \
    ! -name 'libc++.dll' ! -name 'libunwind.dll' ! -name 'libwinpthread-1.dll' \
    ! -name 'libLLVM-*.dll' ! -name 'libclang-cpp.dll' ! -name 'libffi-*.dll' \
    ! -name '*.cfg' \
    -delete

# Trim lib/clang/<ver>/lib/windows/ to just our target's compiler-rt
# builtins (libclang_rt.builtins-aarch64.a etc. — one arch-suffixed file per
# arch in a single shared directory, NOT per-arch subdirectories), drop the
# Linux builtins entirely, and drop the scan-build tooling alongside it.
CLANG_VER_DIR="$(find "$SRC/lib/clang" -maxdepth 1 -mindepth 1 -type d | head -1)"
if [ -n "$CLANG_VER_DIR" ]; then
    rm -rf "$CLANG_VER_DIR/lib/linux"
    if [ -d "$CLANG_VER_DIR/lib/windows" ]; then
        find "$CLANG_VER_DIR/lib/windows" -maxdepth 1 -type f ! -name "*-${HOST_ARCH}.*" -delete
    fi
    rm -rf "$CLANG_VER_DIR/bin" "$CLANG_VER_DIR/share"
fi
rm -rf "$SRC/lib/libscanbuild" "$SRC/lib/libear"

mkdir -p "$OUT_DIR"
cp -a "$SRC"/. "$OUT_DIR"/

echo "Staged trimmed llvm-mingw ($HOST_ARCH host, $TARGET_TRIPLE target) into $OUT_DIR"
du -sh "$OUT_DIR"
