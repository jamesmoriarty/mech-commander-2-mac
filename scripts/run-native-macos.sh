#!/usr/bin/env bash
# Build and launch the native SDL/OpenGL MechCommander 2 engine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
"${SCRIPT_DIR}/build-native-macos.sh" >/dev/null
cd "${REPO_DIR}/build/native/mc2srcdata/build_scripts"
exec ./mc2 "$@"
