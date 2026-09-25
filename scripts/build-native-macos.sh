#!/usr/bin/env bash
# Build the native SDL/OpenGL MechCommander 2 engine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_DIR}/native/mc2"
PATCH_FILE="${REPO_DIR}/native/macos.patch"
NATIVE_DIR="${NATIVE_DIR:-${REPO_DIR}/build/native}"
BUILD_DIR="${NATIVE_DIR}/mc2-build"
DATA_DIR="${NATIVE_DIR}/mc2srcdata"
DATA_BUILD_DIR="${DATA_DIR}/build_scripts"
COMPAT_DIR="${NATIVE_DIR}/macos-compat"
READY_FILE="${NATIVE_DIR}/.ready"

if [[ -f "$READY_FILE" ]]; then
    printf 'Native build already ready: %s\n' "$NATIVE_DIR"
    exit 0
fi

need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    }
}

for command in cmake git make; do need_command "$command"; done

missing=()
need_command brew
for formula in sdl2-compat sdl2_mixer sdl2_ttf glew; do
    brew --prefix "$formula" >/dev/null 2>&1 || missing+=("$formula")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'ERROR: missing Homebrew dependencies: %s\n' "${missing[*]}" >&2
    printf 'Install with: brew install %s\n' "${missing[*]}" >&2
    printf '       or:   make deps\n' >&2
    exit 1
fi

[[ -d "$SOURCE_DIR" ]] || {
    printf 'ERROR: native source submodule is missing. Run: git submodule update --init\n' >&2
    exit 1
}

if [[ ! -d "$DATA_DIR/.git" ]]; then
    git clone https://github.com/alariq/mc2srcdata.git "$DATA_DIR"
fi
if command -v git-lfs >/dev/null 2>&1; then
    git -C "$DATA_DIR" lfs install --local
    git -C "$DATA_DIR" lfs pull
fi

if ! git -C "$SOURCE_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    git -C "$SOURCE_DIR" apply "$PATCH_FILE"
fi

mkdir -p "$COMPAT_DIR/GL"
printf '#pragma once\n#include <OpenGL/gl.h>\n' > "$COMPAT_DIR/GL/gl.h"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-/opt/homebrew}" \
    -DCMAKE_LIBRARY_ARCHITECTURE=x64 \
    -DCMAKE_CXX_FLAGS="-I${COMPAT_DIR}"
cmake --build "$BUILD_DIR" --parallel "${JOBS:-8}"

for tool in aseconv makefst makersp pak; do
    cp "$BUILD_DIR/out/data_tools/$tool" "$DATA_BUILD_DIR/$tool"
done
cp "$BUILD_DIR/out/text_tool/text_tool" "$DATA_BUILD_DIR/text_tool"
make -C "$DATA_BUILD_DIR" all BUILD_PLATFORM=linux

ln -sf "$BUILD_DIR/mc2" "$DATA_BUILD_DIR/mc2"
ln -sf "$BUILD_DIR/out/res/libmc2res_64.dylib" "$DATA_BUILD_DIR/libmc2res_64.so"
ln -sfn "$SOURCE_DIR/shaders" "$DATA_BUILD_DIR/shaders"
touch "$READY_FILE"

printf 'Native build ready. Run: %s\n' "${SCRIPT_DIR}/run-native-macos.sh"
