#!/usr/bin/env bash
# Reset build-related user-config keys and artefacts (keeps model/platform if set).
# Usage: /opt/arc/reset-build-config.sh
[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
. "${ARC_PATH}/include/functions.sh"
. "${ARC_PATH}/include/update.sh"
. "${ARC_PATH}/arc-functions.sh"
readData
resetBuildConfig
echo "Build config reset (user-config.yml preserved except build/PAT keys)."
