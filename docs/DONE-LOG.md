# Done Log — completed dispatches

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-24 — Source health (`effort/source-health`)

- **Result:** Fixed model extraction dates and truncation handling, stopped caching empty results, added the Eventbrite organizer adapter, made UCB manual, and surfaced empty sources and bot challenges.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 131 package tests, check-report fixture, iOS Simulator build, and macOS build.
- **Owed:** source-health's device gate, in [device-passes.md](device-passes.md).

## 2026-11-24 — M3 · S3 — The model suggests (`m3/s3-model-suggests`)

- **Result:** Added per-screen frontier suggestions with a local cache, stored each first verdict beside the decision, and added 30-day agreement counts in Settings.
- **Verification:** scripts/check-drift.sh passed: 127 package tests, SwiftLint, check-report fixture, iOS Simulator build, and macOS build.
- **Owed:** M3 S3's device gate, in [device-passes.md](device-passes.md).

## 2026-11-24 — Taste notes (`m3/s2-taste-notes`)

- **Result:** Added shared household taste notes with author-based editing, listing prefill, and entry points from New and Settings.
- **Verification:** scripts/check-drift.sh passed: SwiftLint had 0 violations, 115 package tests passed, the check-report fixture passed, and the iOS simulator and macOS builds succeeded.
- **Owed:** M3 S2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-24 — Counts sort a screen (`m3/s1-counts-sort`)

- **Result:** New and capture review sort listings by the household taste counts and show the evidence behind each matched score.
- **Verification:** scripts/check-drift.sh passed: SwiftLint had 0 violations, 113 package tests passed, the check-report fixture passed, and the iOS simulator and macOS builds succeeded.
- **Owed:** M3 S1's device gate, in [device-passes.md](device-passes.md).

## 2026-11-22 — Invited Wendy through household sharing (`m2/s2-inviting-wendy`)

- **Result:** Added CloudKit household sharing, participant acceptance, per-person attribution and sync health. Private household convergence preserves and re-keys taste records and people; participants do not seed the registry.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 103 BrightLightsLibrary tests, check-report fixture, iOS build and macOS build.
- **Owed:** M2 S2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-21 — Production and TestFlight (`m2/s1-production-testflight`)

- **Result:** Release builds sync to Production with a separate store, registry writes are gated by version, checker passes sync before and after checking, and the TestFlight release configuration is ready. Jon runs the Production cutover after merge.
- **Verification:** scripts/check-drift.sh passed (99 package tests, SwiftLint, check-report fixture, iOS and macOS builds); signed macOS Debug and Release builds and entitlement checks passed; git diff --check passed.
- **Owed:** M2 S1's device gate, in [device-passes.md](device-passes.md).

## 2026-11-21 — Nightly check report (`codex/check-report`)

- **Result:** Added reconcile counts, per-source check records, coordinated iCloud report storage, and the check-report summary command.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 95 package tests, the report fixture test, and the iOS and macOS builds. Signed macOS build and codesign entitlement checks passed for CloudDocuments and the Bright Lights ubiquity container.
- **Owed:** check-report's device gate, in [device-passes.md](device-passes.md).

## 2026-11-20 — Screening and the taste record (`effort/screening`)

- **Result:** Added source grouped screening, persistent taste records, and picked versus unscreened projections. Listings now prune 30 days after ending regardless of reaction.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 91 package tests, iOS Simulator build, and macOS build.
- **Owed:** screening's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-21, built from `a5feee0` on iPad, iPhone and the checking Mac. The Development schema was imported first (below).
- **Build fix:** the architect added `a5feee0` during the pass. The build-stamp pre-action now creates `DERIVED_FILE_DIR` before writing, so a Mac build into an empty build folder no longer fails at "Write build stamp metadata".
- **Schema:** the architect imported `tasteRecords` into CloudKit Development on 2026-11-20. The live export matched the proposal's base beforehand. Afterwards Development matched the proposal apart from CloudKit's field order, and Production was unchanged.

## 2026-11-20 — Install Bright Lights on the Mac (`codex/mac-installer`)

- **Result:** Added a per-build Git stamp, launch-time login-item restoration, and a verified rollback installer for the checking Mac.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, 85 package tests, and iOS/macOS builds. A signed macOS build also passed build-stamp, codesign, and Development CloudKit entitlement checks.
- **Owed:** mac-installer's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** install and login passed on Jon's device report of 2026-11-20. `scripts/install-bright-lights` installed into `/Applications`. After logging out and back in, the running process was `/Applications/BrightLights.app/Contents/MacOS/BrightLights`, not the Xcode build, so re-registering the login item at launch is enough. The first nightly run from the installed copy passed on Jon's device report of 2026-11-21: Settings on the checking Mac showed **Last household check** from that night.

## 2026-11-20 — Fixing a source from the app (`effort/source-fixes`)

- **Result:** Added app-owned start pages and source flags, with registry reconciliation that preserves both fixes and clears a start page when the registry catches up. Prepared and validated the CloudKit Development proposal for the three synced fields.
- **Verification:** check-drift.sh passed: SwiftLint, 81 package tests, and iOS Simulator and macOS builds.
- **Owed:** source-fixes's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-20, built from `aafe067`. The Development schema was imported first (below). On iPad, Jon set a source's start page from Capture, flagged sources with notes, and saw the flags on iPhone after sync.
- **Schema:** the architect imported the three `sources` fields into CloudKit Development on 2026-11-20, from a fresh export plus the six new fields. Development matched the proposal afterwards, and Production was unchanged.

## 2026-11-20 — Capture tab (`effort/capture-tab`)

- **Result:** Replaced the Rounds and Browser screens with a Capture tab that keeps one browser page, presents due sources in an inspector and home list, advances with Next, and routes source and ticket actions into Capture.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, BrightLightsLibrary tests (78 tests), and iOS/macOS builds.

## 2026-11-19 — Rounds and browser capture (`m1/s5-rounds-browser-capture`)

- **Result:** Added Rounds with due-source groups and a persistent in-app browser. Browser captures use the shared extraction and listing reconciliation path, record browser provenance, and cache page extraction for the app session.
- **Verification:** check-drift passed: SwiftLint, 75 package tests, and iOS and macOS builds.
- **Owed:** M1 S5's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-21, run on the Capture tab ([capture-tab](efforts/archive/capture-tab.md)) as Jon held it on 2026-11-20: a full round with **Next** on iPad, DoNYC capturing only on **Capture**, **Tickets** and **Open in browser** landing in Capture, and the iPhone sheet and sync.

## 2026-11-19 — Stays and What’s on (`m1/s4-stays-and-whats-on`)

- **Result:** Added New York stay validation, the pure WhatsOnProjection, adaptive navigation for While we’re here, Coming up and Stays, listing details, and shared reactions. S4 adds no schema columns or migrations.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, 65 package tests, and iOS and macOS builds.
- **Owed:** M1 S4's device gate, in [device-passes.md](device-passes.md).
- **Device gate:** passed on Jon's device report of 2026-11-21: a tentative stay, reactions and a note on iPad, synced to iPhone with the Booked filter, and the extra day gone once the departure was booked.

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
