#!/usr/bin/env bash
# Compare Wine engines and input/rendering settings without changing the main prefix.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="${GAME_DIR:-${SCRIPT_DIR}/build/Mech Commander 2 RIP}"
SOURCE_PREFIX="${SOURCE_PREFIX:-${SCRIPT_DIR}/build/wine-prefix}"
MATRIX_DIR="${MATRIX_DIR:-${SCRIPT_DIR}/build/matrix}"
WINE_BIN_DEFAULT="${WINE_BIN:-${SCRIPT_DIR}/build/tools/Wine Staging.app/Contents/Resources/wine/bin/wine}"
SIKARUGIR_WINE_BIN="${SIKARUGIR_WINE_BIN:-}"
TIME_LIMIT="${TIME_LIMIT:-20}"
ONLY_CASE=""

if [[ "${1:-}" == "--case" ]]; then
    ONLY_CASE="${2:-}"
    [[ -n "$ONLY_CASE" ]] || { printf 'ERROR: --case requires a case name\n' >&2; exit 2; }
fi

[[ -f "$GAME_DIR/Mc2Rel.exe" ]] || { printf 'ERROR: game not found: %s\n' "$GAME_DIR/Mc2Rel.exe" >&2; exit 1; }
[[ -d "$SOURCE_PREFIX" ]] || { printf 'ERROR: prefix not found: %s\n' "$SOURCE_PREFIX" >&2; exit 1; }
command -v arch >/dev/null 2>&1 || { printf 'ERROR: arch command not found\n' >&2; exit 1; }

mkdir -p "$MATRIX_DIR"
SUMMARY="$MATRIX_DIR/summary.tsv"
printf 'case\tengine\texit\tframebuffer\tdisplay_mode\tddraw\texception\tlog\n' > "$SUMMARY"

clone_prefix() {
    local destination="$1"
    rm -rf "$destination"
    cp -c -R "$SOURCE_PREFIX" "$destination"
}

set_reg() {
    local wine_bin="$1" prefix="$2" key="$3" value="$4"
    WINEPREFIX="$prefix" arch -x86_64 "$wine_bin" reg.exe add "$key" \
        /v "$value" /t REG_SZ /d y /f >/dev/null 2>&1 || true
}

delete_reg() {
    local wine_bin="$1" prefix="$2" key="$3" value="$4"
    WINEPREFIX="$prefix" arch -x86_64 "$wine_bin" reg.exe delete "$key" \
        /v "$value" /f >/dev/null 2>&1 || true
}

run_case() {
    local name="$1" engine="$2" wine_bin="$3" mode="$4" input="$5"
    local prefix="$MATRIX_DIR/$name/prefix"
    local log="$MATRIX_DIR/$name/run.log"
    local server="$(dirname "$wine_bin")/wineserver"
    local exit_code=0
    local sync=1
    [[ "$engine" == "sikarugir" ]] && sync="${SIKARUGIR_SYNC:-0}"

    printf 'Running %-28s (%s)\n' "$name" "$engine"
    mkdir -p "$MATRIX_DIR/$name"
    clone_prefix "$prefix"

    case "$input" in
        default)
            delete_reg "$wine_bin" "$prefix" 'HKEY_CURRENT_USER\\Software\\Wine\\DirectInput' MouseWarpOverride
            delete_reg "$wine_bin" "$prefix" 'HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver' UseConfinementCursorClipping
            ;;
        force)
            set_reg "$wine_bin" "$prefix" 'HKEY_CURRENT_USER\\Software\\Wine\\DirectInput' MouseWarpOverride
            ;;
        clip)
            set_reg "$wine_bin" "$prefix" 'HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver' UseConfinementCursorClipping
            ;;
    esac

    local -a game_args=("-window" "/gosnojoystick")
    if [[ "$mode" == "hardware" ]]; then
        game_args+=("/gosnoblade" "/gosusehw")
    fi

    WINEPREFIX="$prefix" WINESERVER="$server" WINEMSYNC="$sync" WINEESYNC="$sync" \
        TIME_LIMIT="$TIME_LIMIT" \
        WINEDEBUG="${WINEDEBUG:--all}" \
        perl -e '$SIG{ALRM}=sub { kill 9, $child if $child; exit 124 }; $child=fork; if (!$child) { exec @ARGV or exit 127 }; alarm $ENV{TIME_LIMIT}; waitpid($child, 0); exit($? >> 8)' \
        arch -x86_64 "$wine_bin" "$GAME_DIR/Mc2Rel.exe" "${game_args[@]}" >"$log" 2>&1 || exit_code=$?

    local framebuffer=0 display_mode=0 ddraw=0 exception=0
    rg -q 'GL_INVALID_FRAMEBUFFER_OPERATION' "$log" && framebuffer=1 || true
    rg -q 'ChangeDisplaySettings.*returned -2' "$log" && display_mode=1 || true
    rg -q 'DDERR_|DirectDraw|ddraw' "$log" && ddraw=1 || true
    rg -q 'NtRaiseException|Unhandled|invalid frame|err:seh' "$log" && exception=1 || true
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$engine" "$exit_code" "$framebuffer" "$display_mode" "$ddraw" "$exception" "$log" >> "$SUMMARY"
}

run_selected() {
    local name="$1"
    shift
    if [[ -z "$ONLY_CASE" || "$ONLY_CASE" == "$name" ]]; then
        run_case "$name" "$@"
    fi
}

run_selected wine11-software-default wine11 "$WINE_BIN_DEFAULT" software default
run_selected wine11-software-force wine11 "$WINE_BIN_DEFAULT" software force
run_selected wine11-hardware-default wine11 "$WINE_BIN_DEFAULT" hardware default

if [[ -n "$SIKARUGIR_WINE_BIN" && -x "$SIKARUGIR_WINE_BIN" ]]; then
    run_selected sikarugir-software-default sikarugir "$SIKARUGIR_WINE_BIN" software default
    run_selected sikarugir-hardware-default sikarugir "$SIKARUGIR_WINE_BIN" hardware default
else
    printf 'Skipping Sikarugir: set SIKARUGIR_WINE_BIN to its wine64 binary.\n'
fi

printf '\nResults: %s\n' "$SUMMARY"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || true
