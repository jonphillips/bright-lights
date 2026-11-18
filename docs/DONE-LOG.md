# Done Log — completed dispatches

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-18 — Extraction engine (`m1-s1-extraction-engine`)

- **Result:** Added the BrightLightsExtraction package with JSON-LD, Mercury East, AEG/AXS and Caveat adapters, model fallback, stable page hashing, copied fixtures, and package drift controls.
- **Verification:** scripts/check-drift.sh passed SwiftLint and five deterministic tests. The live model produced five listings on one run; field review found cross-venue rows, duplicate/mismatched URLs, UTC-stamped local times, single events marked as runs, and inferred on-sale dates. Prompt and mapping safeguards were added, but later live repeats returned zero listings.

## 2026-11-18 — Event source survey (`codex/source-survey`)

- **Result:** Surveyed all 47 registry sources, documented core source methods and limits, and added bounded fixtures for all 15 automated core routes. Recorded the registry count mismatch and the access/permission limits.
- **Verification:** JSON parses; registry/source counts are 24 core plus 23 other; all 15 automated core routes have fixtures under 100 KB. No build or tests run (research-only dispatch).
