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

if git cat-file -e origin/main:docs/sources/registry.json 2>/dev/null; then
  if ! git diff --quiet origin/main -- docs/sources/registry.json; then
    python3 - docs/sources/registry.json <(git show origin/main:docs/sources/registry.json) <<'PY'
import json
import sys

def version(path):
    with open(path, encoding="utf-8") as file:
        parts = json.load(file)["registry_version"].split(".")
    if not parts or any(not part.isdigit() for part in parts):
        raise SystemExit(f"invalid registry_version in {path}")
    return tuple(map(int, parts))

current, baseline = map(version, sys.argv[1:])
width = max(len(current), len(baseline))
current += (0,) * (width - len(current))
baseline += (0,) * (width - len(baseline))
if current <= baseline:
    raise SystemExit("check-drift.sh: registry changed without a higher registry_version")
PY
  fi
else
  echo "check-drift.sh: skipped registry version comparison; origin/main is unavailable."
fi

xcodegen generate
scripts/install-bright-lights -n
"${qr[@]}" swiftlint lint --strict
env -u BRIGHT_LIGHTS_LIVE_MODEL_TEST "${qr[@]}" swift test --package-path BrightLightsLibrary
scripts/tests/check-report.sh
"${qr[@]}" xcodebuild -project BrightLights.xcodeproj -scheme BrightLights \
  -destination 'generic/platform=iOS Simulator' -onlyUsePackageVersionsFromResolvedFile build
"${qr[@]}" xcodebuild -project BrightLights.xcodeproj -scheme BrightLights \
  -destination 'generic/platform=macOS' -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build

echo "check-drift.sh: registry, SwiftLint, BrightLightsLibrary tests, check-report fixture and iOS/macOS builds passed."

check_handoff="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/check-handoff"
if [[ -x "$check_handoff" ]]; then
  "$check_handoff"
fi
