#!/usr/bin/env bash
# Launch the prepared MechCommander 2 runtime on macOS.
# build-macos.sh performs setup automatically if this is the first run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/build-macos.sh" --run "$@"
