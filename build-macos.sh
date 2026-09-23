#!/usr/bin/env bash
# Build and run the supplied Windows game with free WineHQ macOS binaries.
# The game files remain local; this script only downloads the Wine runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${ARCHIVE:-${SCRIPT_DIR}/MechCommander-2_Win_EN_RIP-Version.zip}"
BUILD_DIR="${BUILD_DIR:-${SCRIPT_DIR}/build}"
GAME_DIR="${BUILD_DIR}/Mech Commander 2 RIP"
TOOLS_DIR="${BUILD_DIR}/tools"
PREFIX_DIR="${BUILD_DIR}/wine-prefix"
WINE_VERSION="${WINE_VERSION:-11.17}"
WINE_KIND="${WINE_KIND:-staging}"
WINE_URL="${WINE_URL:-https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-${WINE_KIND}-${WINE_VERSION}-osx64.tar.xz}"
WINE_ARCHIVE="${TOOLS_DIR}/wine-${WINE_KIND}-${WINE_VERSION}-osx64.tar.xz"
WINETRICKS="${WINETRICKS:-${TOOLS_DIR}/winetricks}"
case "$WINE_KIND" in
    staging) WINE_APP_NAME="Wine Staging.app" ;;
    devel) WINE_APP_NAME="Wine Devel.app" ;;
    stable) WINE_APP_NAME="Wine Stable.app" ;;
    *) printf 'ERROR: WINE_KIND must be stable, devel, or staging\n' >&2; exit 2 ;;
esac
WINE_APP="${TOOLS_DIR}/${WINE_APP_NAME}"
WINE_BIN="${WINE_BIN:-${WINE_APP}/Contents/Resources/wine/bin/wine}"
GAME_EXE="${GAME_DIR}/Mc2Rel.exe"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--setup] [--run] [--windowed] [--software] [--no-hardware-mouse]

  --setup       Extract the ZIP and download the free WineHQ runtime.
  --run         Run Mc2Rel.exe after setup (default if no option is given).
  --windowed    Set the game's fullscreen option off before launching.
  --software    Use the game's BLADE software rasterizer instead of Wine D3D.
  --no-hardware-mouse
                Disable the game's asynchronous/hardware mouse update.

Environment overrides:
  ARCHIVE, BUILD_DIR, WINE_BIN, WINE_VERSION, WINE_KIND, WINE_URL, WINEPREFIX
EOF
}

need_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

setup_game() {
    need_command unzip
    [[ -f "$ARCHIVE" ]] || {
        printf 'ERROR: game ZIP not found: %s\n' "$ARCHIVE" >&2
        exit 1
    }

    mkdir -p "$BUILD_DIR"
    if [[ ! -f "$GAME_EXE" ]]; then
        printf 'Extracting game files...\n'
        unzip -q "$ARCHIVE" -d "$BUILD_DIR"
    else
        printf 'Game already extracted: %s\n' "$GAME_DIR"
    fi
    [[ -f "$GAME_EXE" ]] || {
        printf 'ERROR: expected executable not found after extraction: %s\n' "$GAME_EXE" >&2
        exit 1
    }
}

setup_wine() {
    if [[ -x "$WINE_BIN" ]]; then
        return
    fi

    need_command curl
    need_command tar
    mkdir -p "$TOOLS_DIR"
    printf 'Downloading free WineHQ macOS runtime (%s %s)...\n' "$WINE_KIND" "$WINE_VERSION"
    curl -fL --retry 3 -o "$WINE_ARCHIVE" "$WINE_URL"
    tar -xJf "$WINE_ARCHIVE" -C "$TOOLS_DIR"
    [[ -x "$WINE_BIN" ]] || {
        printf 'ERROR: Wine executable not found at: %s\n' "$WINE_BIN" >&2
        printf 'Set WINE_BIN to the wine executable from the extracted app.\n' >&2
        exit 1
    }
}

prepare_prefix() {
    export WINEPREFIX="${WINEPREFIX:-$PREFIX_DIR}"
    export WINEARCH="${WINEARCH:-win64}"
    # Match the synchronization defaults used by Porting Kit's Wineskin
    # launcher. These are harmless on Wine builds without native support.
    export WINEMSYNC="${WINEMSYNC:-1}"
    export WINEESYNC="${WINEESYNC:-1}"
    mkdir -p "$WINEPREFIX"
}

setup_directplay() {
    local marker="${WINEPREFIX}/.directplay-installed"
    if [[ -f "$marker" ]]; then
        return
    fi

    need_command curl
    if ! command -v cabextract >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            printf 'Installing free cabextract prerequisite with Homebrew...\n'
            brew install cabextract
        else
            printf 'ERROR: cabextract is required for the DirectPlay fix.\n' >&2
            printf 'Install it with Homebrew: brew install cabextract\n' >&2
            exit 1
        fi
    fi

    if [[ ! -x "$WINETRICKS" ]]; then
        printf 'Downloading free Winetricks...\n'
        curl -fL --retry 3 -o "$WINETRICKS" \
            "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
        chmod +x "$WINETRICKS"
    fi

    printf 'Installing the native DirectPlay component required by netlib...\n'
    export PATH="$(dirname "$WINE_BIN"):${PATH}"
    PATH="$(dirname "$(command -v cabextract)"):${PATH}" \
        WINE="$WINE_BIN" \
        arch -x86_64 "$WINETRICKS" -q directplay
    touch "$marker"
}

setup_mouse_capture() {
    local marker="${WINEPREFIX}/.mouse-capture-configured-v2"
    if [[ -f "$marker" ]]; then
        return
    fi

    printf 'Configuring macOS Wine input defaults...\n'
    export PATH="$(dirname "$WINE_BIN"):${PATH}"
    # Porting Kit's Wineskin defaults leave these game-specific overrides
    # unset. Forced warping/confinement can suppress old game input polling.
    arch -x86_64 "$WINE_BIN" reg.exe delete \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v UseConfinementCursorClipping /f >/dev/null 2>&1 || true
    arch -x86_64 "$WINE_BIN" reg.exe delete \
        'HKEY_CURRENT_USER\Software\Wine\DirectInput' \
        /v MouseWarpOverride /f >/dev/null 2>&1 || true
    arch -x86_64 "$WINE_BIN" reg.exe add \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v LeftOptionIsAlt /t REG_SZ /d y /f >/dev/null
    arch -x86_64 "$WINE_BIN" reg.exe add \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v RightOptionIsAlt /t REG_SZ /d y /f >/dev/null
    arch -x86_64 "$WINE_BIN" reg.exe add \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v LeftCommandIsCtrl /t REG_SZ /d y /f >/dev/null
    arch -x86_64 "$WINE_BIN" reg.exe add \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v RightCommandIsCtrl /t REG_SZ /d y /f >/dev/null
    arch -x86_64 "$WINE_BIN" reg.exe add \
        'HKEY_CURRENT_USER\Software\Wine\Mac Driver' \
        /v UsePreciseScrolling /t REG_SZ /d n /f >/dev/null
    touch "$marker"
}

set_windowed() {
    # The bundled config uses Windows backslashes and FITini syntax.
    if [[ "${WINDOWED:-0}" == "1" ]]; then
        for prefs in "$GAME_DIR"/*.cfg; do
            [[ -f "$prefs" ]] || continue
            perl -0pi -e 's/(b\s+FullScreen\s*=\s*)TRUE/${1}FALSE/i' "$prefs"
        done
    fi
    if [[ "${SOFTWARE:-0}" == "1" ]]; then
        for prefs in "$GAME_DIR"/*.cfg; do
            [[ -f "$prefs" ]] || continue
            perl -0pi -e 's/(l\s+Rasterizer\s*=\s*)\d+/${1}3/i' "$prefs"
        done
    fi
    if [[ "${NO_HARDWARE_MOUSE:-0}" == "1" ]]; then
        for prefs in "$GAME_DIR"/*.cfg; do
            [[ -f "$prefs" ]] || continue
            perl -0pi -e 's/(b\s+(?:AsyncMouse|useAsyncMouse)\s*=\s*)\w+/${1}FALSE/ig' "$prefs"
        done
    fi
}

run_game() {
    need_command arch
    setup_game
    setup_wine
    prepare_prefix
    setup_directplay
    setup_mouse_capture
    set_windowed

    # Gcenx's Wine macOS builds are x86_64 and run through Apple's free Rosetta 2.
    if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
        printf 'ERROR: Rosetta 2 is required for the free x86_64 Wine runtime.\n' >&2
        printf 'Install it with: softwareupdate --install-rosetta --agree-to-license\n' >&2
        exit 1
    fi

    export PATH="$(dirname "$WINE_BIN"):${PATH}"
    export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
    cd "$GAME_DIR"
    local -a game_args=()
    if [[ "${WINDOWED:-0}" == "1" ]]; then
        # These are the game's own legacy switches. They avoid its failed
        # ChangeDisplaySettings path under Wine's macOS driver.
        game_args+=("-window" "/gosnojoystick")
        if [[ "${SOFTWARE:-0}" != "1" ]]; then
            # /gosnoblade disables the BLADE software rasterizer. Keep it
            # paired with the hardware switch, never with --software.
            game_args+=("/gosnoblade" "/gosusehw")
        fi
    fi
    printf 'Launching MechCommander 2 with Wine...\n'
    printf '  Prefix: %s\n  Game:   %s\n' "$WINEPREFIX" "$GAME_EXE"
    exec arch -x86_64 "$WINE_BIN" "$GAME_EXE" "${game_args[@]}"
}

MODE="run"
WINDOWED="${WINDOWED:-0}"
SOFTWARE="${SOFTWARE:-0}"
NO_HARDWARE_MOUSE="${NO_HARDWARE_MOUSE:-0}"
for arg in "$@"; do
    case "$arg" in
        --setup) MODE="setup" ;;
        --run) MODE="run" ;;
        --windowed) WINDOWED=1 ;;
        --software) SOFTWARE=1 ;;
        --no-hardware-mouse) NO_HARDWARE_MOUSE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'ERROR: unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$MODE" == "setup" ]]; then
    setup_game
    setup_wine
    prepare_prefix
    setup_directplay
    setup_mouse_capture
    printf 'Setup complete. Run: %s --run\n' "$0"
else
    run_game
fi
