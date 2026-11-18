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

if ! cmp -s docs/sources/registry.json BrightLightsLibrary/Sources/BrightLightsSchema/Resources/registry.json; then
  echo "check-drift.sh: bundled source registry is out of date; copy docs/sources/registry.json into BrightLightsSchema/Resources." >&2
  exit 1
fi

xcodegen generate
"${qr[@]}" swiftlint lint --strict
env -u BRIGHT_LIGHTS_LIVE_MODEL_TEST "${qr[@]}" swift test --package-path BrightLightsLibrary
"${qr[@]}" xcodebuild -project BrightLights.xcodeproj -scheme BrightLights \
  -destination 'generic/platform=iOS Simulator' -onlyUsePackageVersionsFromResolvedFile build
"${qr[@]}" xcodebuild -project BrightLights.xcodeproj -scheme BrightLights \
  -destination 'generic/platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build

echo "check-drift.sh: registry, SwiftLint, BrightLightsLibrary tests and iOS/macOS builds passed."

check_handoff="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/check-handoff"
if [[ -x "$check_handoff" ]]; then
  "$check_handoff"
fi
