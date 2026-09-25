#!/usr/bin/env bash
# Build a distributable engine package (no game data) plus a separate
# game-data archive that end users download through the bundled launcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${REPO_DIR}/native/mc2"
NATIVE_DIR="${NATIVE_DIR:-${REPO_DIR}/build/native}"
BUILD_DIR="${NATIVE_DIR}/mc2-build"
DATA_DIR="${NATIVE_DIR}/mc2srcdata"
DATA_BUILD_DIR="${DATA_DIR}/build_scripts"
DIST_DIR="${REPO_DIR}/dist"
APP_NAME="MechCommander2.app"
APP_DIR="${DIST_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
BIN_DIR="${CONTENTS_DIR}/MacOS"
LIB_DIR="${CONTENTS_DIR}/lib"
RES_DIR="${CONTENTS_DIR}/Resources"
ENGINE="${BIN_DIR}/mc2"
LAUNCHER="${RES_DIR}/MechCommander2.sh"
ZIP_NAME="MechCommander2-mac.zip"
STAGE_DIR="${DIST_DIR}/data-stage"
DATA_ARCHIVE="${DIST_DIR}/mc2-data.tar.gz"

need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    }
}

for command in otool install_name_tool codesign rsync tar zip curl iconutil swiftc; do
    need_command "$command"
done

if [[ ! -f "${NATIVE_DIR}/.ready" ]]; then
    "${SCRIPT_DIR}/build-native-macos.sh"
fi

rm -rf "$APP_DIR" "$STAGE_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR" "$RES_DIR" "$STAGE_DIR"

cp "$BUILD_DIR/mc2" "$ENGINE"
cp "$BUILD_DIR/out/res/libmc2res_64.dylib" "$LIB_DIR/libmc2res_64.dylib"
cp -R "$SOURCE_DIR/shaders" "$RES_DIR/shaders"
cp "$SOURCE_DIR/license.txt" "$RES_DIR/license.txt"
iconutil -c icns "${REPO_DIR}/native/icon/AppIcon.iconset" -o "$RES_DIR/AppIcon.icns"

bundle_dylibs() {
    local binary="$ENGINE"
    local lib_srcs=() lib_names=() queue=("$binary" "$LIB_DIR/libmc2res_64.dylib")
    local qhead=0
    local src name base n i idx dep canon extra rest f anchor target collision

    add_lib() {
        src="$1"
        for i in "${!lib_srcs[@]}"; do
            [[ "${lib_srcs[$i]}" == "$src" ]] && return 0
        done
        base="$(basename "$src")"
        name="$base"
        n=2
        while :; do
            collision=0
            for i in "${!lib_names[@]}"; do
                [[ "${lib_names[$i]}" == "$name" ]] && collision=1
            done
            [[ "$collision" -eq 0 ]] && break
            name="${base}.${n}"
            n=$((n + 1))
        done
        cp -f "$src" "$LIB_DIR/$name"
        install_name_tool -id "@rpath/$name" "$LIB_DIR/$name" 2>/dev/null
        lib_srcs+=("$src")
        lib_names+=("$name")
        queue+=("$LIB_DIR/$name")
    }

    # Homebrew's SDL2 is the sdl2-compat shim: it dlopen()s libSDL3.dylib
    # at runtime, which no load command reveals. Seed it explicitly so it
    # lands in Contents/lib next to the shim.
    for extra in /opt/homebrew/opt/sdl3/lib/libSDL3.dylib; do
        [[ -f "$extra" ]] && add_lib "$extra"
    done

    while [[ "$qhead" -lt "${#queue[@]}" ]]; do
        f="${queue[$qhead]}"
        qhead=$((qhead + 1))
        anchor="@loader_path"
        [[ "$f" == "$binary" ]] && anchor="@executable_path/../lib"
        while read -r dep rest; do
            [[ "$dep" == @* ]] && {
                [[ "$dep" == "@rpath/$(basename "$f")" ]] ||
                    printf 'NOTE: relocatable dependency left as-is: %s (%s)\n' "$dep" "$(basename "$f")"
                continue
            }
            [[ "$dep" == /opt/homebrew/* ]] || continue
            if [[ ! -f "$dep" ]]; then
                printf 'WARNING: missing dependency: %s (%s)\n' "$dep" "$(basename "$f")" >&2
                continue
            fi
            # Resolve Homebrew opt/Cellar aliases so the same physical dylib
            # referenced through different paths is bundled only once.
            canon="$(cd "$(dirname "$dep")" && pwd -P)/$(basename "$dep")"
            add_lib "$canon"
            idx=-1
            for i in "${!lib_srcs[@]}"; do
                [[ "${lib_srcs[$i]}" == "$canon" ]] && idx=$i
            done
            target="${lib_names[$idx]}"
            install_name_tool -change "$dep" "${anchor}/${target}" "$f" 2>/dev/null
        done < <(otool -L "$f" | tail -n +2)
    done
}

bundle_dylibs

# Mach-O bundle launcher (execs the bash launcher; doubles as the
# --download progress window used by that script).
swiftc -O -o "$BIN_DIR/MechCommander2" "${REPO_DIR}/native/launcher/Mc2Launcher.swift"

if otool -l "$ENGINE" | grep -q 'path /opt/homebrew'; then
    install_name_tool -delete_rpath /opt/homebrew/lib "$ENGINE" 2>/dev/null
fi

if [[ "${SKIP_DATA_ARCHIVE:-0}" != "1" ]]; then
    printf 'Staging game data (build tools excluded)...\n'
    rsync -a \
        --exclude='.DS_Store' \
        --exclude='/aseconv' --exclude='/ase2tgl' \
        --exclude='/makefst' --exclude='/makersp' --exclude='/pak' \
        --exclude='/text_tool' --exclude='/mc2' --exclude='/libmc2res_64.so' \
        --exclude='/shaders' --exclude='/makefile' --exclude='/*.mk' \
        --exclude='/*.rsp' --exclude='/README.md' --exclude='/testtxm.tga' \
        --exclude='/options.cfg' --exclude='/options.cfg.old' \
        "$DATA_BUILD_DIR/" "$STAGE_DIR/"
    printf 'Compressing game data to %s...\n' "$DATA_ARCHIVE"
    tar -czf "$DATA_ARCHIVE" -C "$STAGE_DIR" .
    rm -rf "$STAGE_DIR"
fi

cat > "$RES_DIR/data-url.txt" <<EOF
# Download URL for the game data (a .tar.gz archive or a GitHub release
# .zip such as alariq/mc2's Windows bundle, from which the launcher
# extracts only the shared game data). Override with MC2_DATA_URL.
${MC2_DATA_URL:-https://github.com/alariq/mc2/releases/download/v0.1.3/mc2-win64-v0.1.3.zip}
EOF

cat > "$CONTENTS_DIR/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MechCommander2</string>
    <key>CFBundleDisplayName</key>
    <string>MechCommander 2</string>
    <key>CFBundleExecutable</key>
    <string>MechCommander2</string>
    <key>CFBundleIdentifier</key>
    <string>org.mechcommander2.mc2-mac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

cat > "$LAUNCHER" <<'EOF'
#!/bin/bash
# MechCommander 2 launcher: fetches game data on first run, then starts the game.
set -euo pipefail

RES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS_DIR="$(dirname "$RES_DIR")"
BIN_DIR="$CONTENTS_DIR/MacOS"
ENGINE="$BIN_DIR/mc2"

DATA_DIR="${MC2_DATA_DIR:-$HOME/Library/Application Support/MechCommander2/game-data}"
MARKER="$DATA_DIR/.mc2-data-ready"

assume_yes=0
if [[ "${1:-}" == "--yes" ]]; then
    assume_yes=1
    shift
fi

gui=0
[[ -t 0 ]] || gui=1

notify() {
    printf '%s\n' "$1" >&2
    if [[ "$gui" -eq 1 ]]; then
        osascript - "$1" >/dev/null 2>&1 <<'OSA' || true
on run argv
    display alert "MechCommander 2" message (item 1 of argv)
end run
OSA
    fi
}

confirm_download() {
    if [[ "$assume_yes" -eq 1 ]]; then
        return 0
    fi
    if [[ "$gui" -eq 0 ]]; then
        printf 'Game data (~630 MB) will be downloaded from:\n  %s\n' "$1" >&2
        read -r -p 'Download now? [y/N] ' reply || reply=n
        [[ "$reply" == [yY]* ]]
    else
        osascript - "$1" 2>/dev/null <<'OSA' | grep -q '^true$'
on run argv
    display alert "MechCommander 2" message ("Game data (~630 MB) will be downloaded from:" & return & (item 1 of argv)) buttons {"Cancel", "Download"} default button "Download"
    return button returned of result is "Download"
end run
OSA
    fi
}

if [[ ! -f "$MARKER" ]]; then
    url="${MC2_DATA_URL:-}"
    if [[ -z "$url" && -f "$RES_DIR/data-url.txt" ]]; then
        url="$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$RES_DIR/data-url.txt" | head -n 1 || true)"
    fi
    if [[ -z "$url" ]]; then
        notify "Game data is not installed and no download URL is configured. Host the data archive yourself, then set its URL in Contents/Resources/data-url.txt inside MechCommander2.app, or launch with MC2_DATA_URL=<url>."
        exit 1
    fi
    if ! confirm_download "$url"; then
        notify 'Aborted.'
        exit 1
    fi
    mkdir -p "$DATA_DIR"
    partial="$DATA_DIR/.mc2-data.partial"
    tmp="$DATA_DIR/.mc2-data-tmp"
    rm -rf "$partial" "$tmp"
    printf 'Downloading game data...\n' >&2
    downloader="$BIN_DIR/MechCommander2"
    rc=0
    if [[ "$gui" -eq 1 && -x "$downloader" ]]; then
        "$downloader" --download --url "$url" --out "$partial" || rc=$?
    else
        curl -fL --progress-bar -o "$partial" "$url" || rc=1
    fi
    if [[ "$rc" -ne 0 ]]; then
        rm -f "$partial"
        if [[ "$rc" -eq 2 ]]; then
            notify 'Download cancelled.'
        else
            notify 'ERROR: download failed.'
        fi
        exit 1
    fi
    printf 'Extracting game data...\n' >&2
    ok=0
    if [[ "$url" == *.zip ]]; then
        # GitHub release archives (e.g. alariq/mc2) are zips with a single top
        # directory plus Windows binaries we must not take.
        if unzip -qq "$partial" -x '*.exe' '*.dll' '*.pdb' '*/shaders/*' '*/testtxm.tga' '*/options.cfg' '*/options.cfg.old' -d "$tmp"; then
            top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
            rsync -a "${top:-$tmp}/" "$DATA_DIR/"
            ok=1
        fi
    else
        tar -xzf "$partial" -C "$DATA_DIR" && ok=1
    fi
    rm -f "$partial"
    rm -rf "$tmp"
    if [[ "$ok" -ne 1 ]]; then
        rm -rf "$DATA_DIR"
        notify 'ERROR: extraction failed; the download was removed.'
        exit 1
    fi
    touch "$MARKER"
    printf 'Game data installed.\n' >&2
fi

# The app-provided shaders/resource library take precedence over anything
# that came in the archive.
rm -rf "$DATA_DIR/shaders"
rm -f "$DATA_DIR/libmc2res_64.so"
ln -sfn "$RES_DIR/shaders" "$DATA_DIR/shaders"
ln -sfn "$CONTENTS_DIR/lib/libmc2res_64.dylib" "$DATA_DIR/libmc2res_64.so"

cd "$DATA_DIR"
exec "$ENGINE" "$@"
EOF
chmod +x "$LAUNCHER"

cat > "$RES_DIR/README.md" <<'EOF'
# MechCommander 2 for macOS (Apple Silicon)

Open-source engine port (GPLv3, see `license.txt`). The original game data
(Microsoft's assets) is **not included**; the app downloads it on first run
from the URL in `Contents/Resources/data-url.txt`.

## Run

Double-click `MechCommander2.app`, or from a terminal:

```sh
open MechCommander2.app
# or with a custom data URL / directory:
MC2_DATA_URL=<url> MC2_DATA_DIR=<dir> open MechCommander2.app
```

On first run the app asks before downloading the game data (~630 MB) from
the alariq/mc2 GitHub release (URL in `Contents/Resources/data-url.txt`)
into `~/Library/Application Support/MechCommander2/game-data/`, showing a
download progress window (cancel stops the download). To run offline,
pre-populate that directory (it must contain `data/`, `assets/` and the
`.fst` files).

If macOS blocks the app after download:

```sh
xattr -dr com.apple.quarantine MechCommander2.app
```

No Homebrew or other dependencies are required; all libraries are bundled.
The app is ad-hoc signed (no Developer ID), so it is intended for local use.

## Data download

By default the launcher downloads game data from alariq/mc2's GitHub
release. Point `data-url.txt` (or `MC2_DATA_URL`) at your own
`mc2-data.tar.gz` if you host one; whoever distributes this package must
ensure that download is allowed to host the Microsoft game assets.

## Engine source

https://github.com/alariq/mc2 plus the macOS patch (`native/macos.patch`)
from this repository.
EOF

leak="$(cd "$CONTENTS_DIR" && find MacOS lib -type f \
    \( -exec otool -L {} \; -exec otool -l {} \; \) 2>/dev/null \
    | grep -e /opt/homebrew -e '/Users/' || true)"
if [[ -n "$leak" ]]; then
    printf 'ERROR: unbundled Homebrew library references remain:\n%s\n' "$leak" >&2
    exit 1
fi

# Signing: use MC2_SIGN_IDENTITY ("Developer ID Application: ...") when
# given; otherwise auto-detect one from the keychain, else sign ad-hoc.
if [[ -z "${MC2_SIGN_IDENTITY:-}" ]]; then
    MC2_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -n "$MC2_SIGN_IDENTITY" ]]; then
    printf 'Signing with: %s (hardened runtime, timestamped)\n' "$MC2_SIGN_IDENTITY"
    CS_ARGS=(--options runtime --timestamp --sign "$MC2_SIGN_IDENTITY")
else
    printf 'No Developer ID identity found; ad-hoc signing (not notarizable).\n'
    CS_ARGS=(--sign -)
fi

# Nested code first: dylibs, helpers, engine, launcher stub, then the bundle.
for file in "$LIB_DIR"/* "$ENGINE" "$BIN_DIR/MechCommander2"; do
    [[ -f "$file" ]] || continue
    codesign --force "${CS_ARGS[@]}" "$file"
done
codesign --force "${CS_ARGS[@]}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" && printf 'Signature verified.\n'

rm -f "${DIST_DIR}/${ZIP_NAME}"
( cd "$DIST_DIR" && zip -qryX "$ZIP_NAME" "$APP_NAME" -x '*/.DS_Store' )

# Notarization (requires a Developer ID build above).
if [[ -n "${MC2_NOTARY_PROFILE:-}" || -n "${MC2_NOTARY_KEY_FILE:-}" ]]; then
    if [[ -z "$MC2_SIGN_IDENTITY" ]]; then
        printf 'ERROR: notarization needs a Developer ID signature.\n' >&2
        exit 1
    fi
    if [[ -n "${MC2_NOTARY_PROFILE:-}" ]]; then
        NOTARY_ARGS=(--keychain-profile "$MC2_NOTARY_PROFILE")
    else
        NOTARY_ARGS=(--key "$MC2_NOTARY_KEY_FILE" --key-id "$MC2_NOTARY_KEY_ID")
        [[ -n "${MC2_NOTARY_ISSUER_ID:-}" ]] && NOTARY_ARGS+=(--issuer "$MC2_NOTARY_ISSUER_ID")
    fi
    printf 'Notarizing (this uploads %s to Apple)...\n' "$ZIP_NAME"
    xcrun notarytool submit "${DIST_DIR}/${ZIP_NAME}" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$APP_DIR"
    rm -f "${DIST_DIR}/${ZIP_NAME}"
    ( cd "$DIST_DIR" && zip -qryX "$ZIP_NAME" "$APP_NAME" -x '*/.DS_Store' )
    printf 'Notarized and stapled.\n'
elif [[ -n "$MC2_SIGN_IDENTITY" ]]; then
    printf 'NOTE: signed with Developer ID but NOT notarized.\n'
    printf '      Set MC2_NOTARY_PROFILE or MC2_NOTARY_KEY_FILE to notarize.\n'
fi

printf '\nBuild complete:\n'
printf '  App bundle (run this):            %s\n' "$APP_DIR"
printf '  Engine package (share this zip):  %s\n' "${DIST_DIR}/${ZIP_NAME}"
if [[ -f "$DATA_ARCHIVE" ]]; then
    printf '  Game data archive (host this):   %s\n' "$DATA_ARCHIVE"
    printf '    sha256: %s\n' "$(shasum -a 256 "$DATA_ARCHIVE" | awk '{print $1}')"
fi
printf '\nNext steps:\n'
printf '  Game data downloads by default from the alariq/mc2 GitHub release\n'
printf '  (see Contents/Resources/data-url.txt in the app).\n'
printf '  To use your own archive instead: MC2_DATA_URL=<url> make dist\n'
