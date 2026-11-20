# Done Log — completed dispatches

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-20 — Install Bright Lights on the Mac (`codex/mac-installer`)

- **Result:** Added a per-build Git stamp, launch-time login-item restoration, and a verified rollback installer for the checking Mac.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 85 package tests, and iOS/macOS builds. A signed macOS build also passed build-stamp, codesign, and Development CloudKit entitlement checks.
- **Owed:** mac-installer's device gate, in [device-passes.md](device-passes.md).

## 2026-11-20 — Fixing a source from the app (`effort/source-fixes`)

- **Result:** Added app-owned start pages and source flags, with registry reconciliation that preserves both fixes and clears a start page when the registry catches up. Prepared and validated the CloudKit Development proposal for the three synced fields.
- **Verification:** check-drift.sh passed: SwiftLint, 81 package tests, and iOS Simulator and macOS builds.
- **Owed:** source-fixes's device gate, in [device-passes.md](device-passes.md).

## 2026-11-20 — Capture tab (`effort/capture-tab`)

- **Result:** Replaced the Rounds and Browser screens with a Capture tab that keeps one browser page, presents due sources in an inspector and home list, advances with Next, and routes source and ticket actions into Capture.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, BrightLightsLibrary tests (78 tests), and iOS/macOS builds.

## 2026-11-19 — Rounds and browser capture (`m1/s5-rounds-browser-capture`)

- **Result:** Added Rounds with due-source groups and a persistent in-app browser. Browser captures use the shared extraction and listing reconciliation path, record browser provenance, and cache page extraction for the app session.
- **Verification:** check-drift passed: SwiftLint, 75 package tests, and iOS and macOS builds.
- **Owed:** M1 S5's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — Stays and What’s on (`m1/s4-stays-and-whats-on`)

- **Result:** Added New York stay validation, the pure WhatsOnProjection, adaptive navigation for While we’re here, Coming up and Stays, listing details, and shared reactions. S4 adds no schema columns or migrations.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, 65 package tests, and iOS and macOS builds.
- **Owed:** M1 S4's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — Mac source checker (`m1/s3-mac-checker`)

- **Result:** Added polite scheduled source checks on the Mac, change-only listing upserts, check outcomes, model-call rationing, and CloudKit convergence for seeded Household and Source records. Confirmed Irving Plaza is a single-page source and removed the incorrect Mercury East adapter assignment.
- **Verification:** scripts/check-drift.sh passed all 46 package tests, strict lint, and iOS and macOS builds, including final review fixes for typed checker keys, key removal, and Mercury Lounge pagination. Two live Check all passes covered all 29 automated sources; the second wrote 0 rows. After a fresh-store sync and restart, SQLiteData reported 1 Household, 44 Sources, 867 Listings, 912 server-known records, 0 unsynced records, and 0 pending zone changes.
- **Owed:** M1 S3's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-20. The Mac holds the checking role, and most of the eligible automated sources ran and wrote listings, which show on the Mac and the iPad. A few sources failed; that follow-up is in [open-questions.md](open-questions.md).

## 2026-11-18 — Bright Lights app scaffold, shared schema, and seeded sources (`codex/m1-s2-app-scaffold-schema-seeded-sources`)

- **Result:** Added the multiplatform app shell, Development CloudKit wiring behind a local opt-in, the household/source/listing/stay/reaction schema, registry reconciliation, and read-only Sources screens. Seed reconciliation preserves check history and converges offline duplicate rows.
- **Verification:** check-drift.sh passed: registry parity, SwiftLint, 18 package tests, and iOS Simulator plus macOS builds.
- **Owed:** M1 S2's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-19. The Mac and the iPad, installed from Xcode with sync on, each list the sources with no duplicates, and Bowery Ballroom shows the same ID and Household ID on both. The Mac build signs with `com.apple.developer.aps-environment` (checked with `codesign`). The first signed run created the `iCloud.com.jonphillips.BrightLights` container, which unblocked `cktool export-schema` for M1 S3.

## 2026-11-18 — Extraction engine (`m1-s1-extraction-engine`)

- **Result:** Added the BrightLightsExtraction package with JSON-LD, Mercury East, AEG/AXS and Caveat adapters, model fallback, stable page hashing, copied fixtures, and package drift controls.
- **Verification:** scripts/check-drift.sh passed SwiftLint and ten deterministic tests. A live run returned three The Stand listings; titles, rooms, start times and event URLs matched the fixture, and two The Stand West rows were excluded with a warning. A prior run emitted date-only performance starts; those are now rejected with a count warning.

## 2026-11-18 — Event source survey (`codex/source-survey`)

- **Result:** Surveyed all 47 registry sources, documented core source methods and limits, and added bounded fixtures for all 15 automated core routes. Recorded the registry count mismatch and the access/permission limits.
- **Verification:** JSON parses; registry/source counts are 24 core plus 23 other; all 15 automated core routes have fixtures under 100 KB. No build or tests run (research-only dispatch).
