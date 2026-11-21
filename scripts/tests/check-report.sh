#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_output="$(mktemp)"
trap 'rm -f "$tmp_output"' EXIT
TZ=America/New_York "$repo_root/scripts/check-report" \
  --dir "$repo_root/scripts/tests/fixtures/check-report" \
  --now 2026-11-21T12:00:00Z > "$tmp_output"
cmp "$repo_root/scripts/tests/fixtures/check-report/expected.txt" "$tmp_output"
echo "check-report.sh: fixture summary passed."
