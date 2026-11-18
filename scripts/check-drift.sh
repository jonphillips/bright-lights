#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

quiet_run="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/quiet-run"
qr=()
if [[ -x "$quiet_run" ]]; then qr=("$quiet_run"); fi

"${qr[@]}" swiftlint lint --strict
env -u BRIGHT_LIGHTS_LIVE_MODEL_TEST "${qr[@]}" swift test --package-path BrightLightsLibrary

echo "check-drift.sh: SwiftLint and BrightLightsLibrary tests passed."

check_handoff="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/check-handoff"
if [[ -x "$check_handoff" ]]; then
  "$check_handoff"
fi
