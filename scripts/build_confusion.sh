#!/usr/bin/env bash
# Build the historical MDL interpreter outside its pinned, immutable upstream Git tree.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/.cache/upstream/mdlzork"
CONFUSION_SOURCE="$UPSTREAM/confusion_patched"
GAME="$UPSTREAM/mdlzork_771212/patched_confusion"
BUILD_ROOT="$ROOT/.cache/build"
CONFUSION_BUILD="$BUILD_ROOT/confusion_patched"

[[ -f "$CONFUSION_SOURCE/Makefile" ]] || { echo 'Run make sources first' >&2; exit 2; }
[[ -f "$GAME/SAVEFILE/ZORK.SAVE" ]] || { echo 'Pinned reconstructed game image missing' >&2; exit 2; }
command -v make >/dev/null || { echo 'make missing' >&2; exit 2; }
command -v g++ >/dev/null || { echo 'g++ missing' >&2; exit 2; }
command -v tar >/dev/null || { echo 'tar missing' >&2; exit 2; }

# A fresh export ensures no generated code or compiled objects can dirty the
# source checkout. This directory is generated and safe to recreate.
if [[ -L "$CONFUSION_BUILD" ]]; then
    echo "Refusing to replace symlink: $CONFUSION_BUILD" >&2
    exit 2
fi
mkdir -p "$BUILD_ROOT"
rm -rf -- "$CONFUSION_BUILD"
git -C "$UPSTREAM" archive --format=tar HEAD confusion_patched | tar -xf - -C "$BUILD_ROOT"
# Newer GCC no longer gets uint64_t transitively in macros.hpp. Inject the
# standard header at compile time; do not alter the pinned source checkout.
CONFUSION_CXXFLAGS='-g -DGC_DEBUG -O2 -Wall -Wno-switch -Wno-unused-but-set-variable -include cstdint'
printf 'Confusion C++ flags: %s\n' "$CONFUSION_CXXFLAGS"
make -C "$CONFUSION_BUILD" CXXFLAGS="$CONFUSION_CXXFLAGS" mdli
[[ -x "$CONFUSION_BUILD/mdli" ]] || { echo 'Confusion build did not produce mdli' >&2; exit 1; }
printf 'Confusion built at %s\n' "$CONFUSION_BUILD/mdli"
printf 'Reference image at %s\n' "$GAME/SAVEFILE/ZORK.SAVE"
printf 'Upstream Git checkout was not modified by the build.\n'
printf 'Build is not proof of successful gameplay; run make reference-capture.\n'
