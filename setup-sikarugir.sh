#!/usr/bin/env bash
# Stage Porting Kit's Sikarugir engine for the diagnostic matrix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ARCHIVE="${SIKARUGIR_ENGINE_ARCHIVE:-${HOME}/Library/Application Support/Wineskin/Engines/WS12WineSikarugir10.0_3.tar.7z}"
FRAMEWORKS="${WINESKIN_FRAMEWORKS:-${HOME}/Library/Application Support/Wineskin/Wrapper/Wineskin-3.0.6-2.app/Contents/Frameworks}"
DEST="${SIKARUGIR_DIR:-${SCRIPT_DIR}/build/tools/sikarugir/wswine.bundle}"
SEVEN_ZA="${SEVEN_ZA:-${SCRIPT_DIR}/build/tools/7za}"

[[ -f "$ENGINE_ARCHIVE" ]] || {
    printf 'ERROR: Sikarugir engine archive not found: %s\n' "$ENGINE_ARCHIVE" >&2
    exit 1
}
[[ -d "$FRAMEWORKS" ]] || {
    printf 'ERROR: Wineskin frameworks not found: %s\n' "$FRAMEWORKS" >&2
    exit 1
}

if [[ ! -x "$SEVEN_ZA" ]]; then
    mkdir -p "$(dirname "$SEVEN_ZA")"
    cp "/Applications/Porting Kit.app/Contents/Resources/app.asar.unpacked/node_modules/7zip-bin/mac/arm64/7za" "$SEVEN_ZA"
    chmod +x "$SEVEN_ZA"
fi

if [[ ! -x "$DEST/bin/wine64" ]]; then
    rm -rf "$(dirname "$DEST")"
    mkdir -p "$(dirname "$DEST")"
    "$SEVEN_ZA" x "$ENGINE_ARCHIVE" -so | tar -x -C "$(dirname "$DEST")"
fi

for library in "$FRAMEWORKS"/*.dylib; do
    ln -sf "$library" "$DEST/lib/$(basename "$library")"
done

printf 'Sikarugir staged at: %s\n' "$DEST"
printf 'Run with:\n'
printf '  SIKARUGIR_WINE_BIN="%s/bin/wine64" ./test-matrix.sh --case sikarugir-software-default\n' "$DEST"
