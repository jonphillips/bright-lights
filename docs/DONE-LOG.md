# Done Log — completed dispatches

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-18 — Bright Lights app scaffold, shared schema, and seeded sources (`codex/m1-s2-app-scaffold-schema-seeded-sources`)

- **Result:** Added the multiplatform app shell, Development CloudKit wiring behind a local opt-in, the household/source/listing/stay/reaction schema, registry reconciliation, and read-only Sources screens. Seed reconciliation preserves check history and converges offline duplicate rows.
- **Verification:** check-drift.sh passed: registry parity, SwiftLint, 17 package tests, and iOS Simulator plus macOS builds.
- **Owed:** M1 S2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-18 — Extraction engine (`m1-s1-extraction-engine`)

- **Result:** Added the BrightLightsExtraction package with JSON-LD, Mercury East, AEG/AXS and Caveat adapters, model fallback, stable page hashing, copied fixtures, and package drift controls.
- **Verification:** scripts/check-drift.sh passed SwiftLint and ten deterministic tests. A live run returned three The Stand listings; titles, rooms, start times and event URLs matched the fixture, and two The Stand West rows were excluded with a warning. A prior run emitted date-only performance starts; those are now rejected with a count warning.

## 2026-11-18 — Event source survey (`codex/source-survey`)

- **Result:** Surveyed all 47 registry sources, documented core source methods and limits, and added bounded fixtures for all 15 automated core routes. Recorded the registry count mismatch and the access/permission limits.
- **Verification:** JSON parses; registry/source counts are 24 core plus 23 other; all 15 automated core routes have fixtures under 100 KB. No build or tests run (research-only dispatch).
