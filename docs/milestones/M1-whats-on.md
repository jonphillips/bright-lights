# M1 — What's on

*Architect, 2026-11-18. Arc: from nothing to Jon, on the iPad, seeing real listings from his sources against a stay,
reacting to them, and doing Rounds for the sources the Mac can't read. Decisions: ADR-0001 to ADR-0005. Wendy,
TestFlight and the CloudKit Production schema are M2.*

## Slice ledger

- [x] **S1** — Extraction engine (package only)
- [ ] **S2** — App scaffold, schema, seeded sources
- [ ] **S3** — The Mac checks the sources
- [ ] **S4** — Stays and What's on
- [ ] **S5** — Rounds and browser capture

Each slice is one dispatch. The architect expands a slice into a full brief, here, before dispatching it. S1 and
S2 are expanded below; S3 to S5 are outlines.

## S1 — Extraction engine (package only)

**Goal:** prove ADR-0004 against the survey's samples before any app exists.

**Build:**

- **The local package `BrightLightsLibrary`** with a module `BrightLightsExtraction` and its tests. There's no Xcode
  project yet.
- **Minimal scaffolding for a package-only repo:** `scripts/check-drift.sh` runs SwiftLint (copy Galavant's
  `.swiftlint.yml`) and the package tests through jon-platform's `quiet-run`. Add `.githooks/pre-commit` calling it,
  following jon-platform `docs/ios/drift-control.md`.
- **Value types:**
  - `ExtractedListing`: stable key, title, performers, room, time as an enum `.performance(start)` or
    `.run(opens, closes)`, ticket URL, on-sale date, status, and rung.
  - `ExtractionResult`: listings plus warnings.
  - `SourceDescriptor`: id, adapter name if any, and registered hosts.

  Times are `America/New_York` wall-clock times (ADR-0002, point 4).
- **The ladder (ADR-0004, point 2):**
  1. JSON-LD `Event`, including `@graph`s and arrays.
  2. Adapters `mercuryEast`, `aegAXS` and `caveatJSON`.
  3. Model extraction through `LLMClientKit`'s structured output (jon-platform ADR-0004), behind a `@Dependency` so
     tests use a stub.
- **The page hash** used to ration model calls (ADR-0004, point 4): a normalized hash of the visible text, robust to
  whitespace and script changes.
- **Stable keys:** use the canonical event URL or ID where the source has one (see each source's `stable_event_id`
  in `survey.json`), otherwise the hash described in ADR-0002.

**Tests (fixtures copied into the test target; `docs/sources/fixtures/` stays the survey record):**

- JSON-LD: `bell-house.json`, `ny-comedy-club.json`.
- Adapters: `bowery-ballroom.html` (mercuryEast), `brooklyn-steel.json` (aegAXS), `caveat.json` (caveatJSON).
- For each, assert the listing count, plus the first and last listing's title, start time and key.
- Model rung: one test with `the-stand.html` and a stub returning recorded structured output, checking the mapping
  to `ExtractedListing` (time zone, run versus single performance).
- An opt-in live test against the real model, skipped unless an environment variable is set, and never run by
  `check-drift`.
- The ladder: a document with JSON-LD never reaches an adapter or the model, and a source with an adapter never
  reaches the model.

**Done when:** `check-drift` passes, every structured fixture source yields its listings through the expected rung,
and the stubbed model rung maps correctly. One live model run against `the-stand.html` is reported in the PR,
including its listing count and any wrong fields.

**Not in S1:** fetching, persistence, the app, and the Mac.

## S2 — App scaffold, schema, seeded sources

**Goal:** a Bright Lights app that launches on iPad, iPhone and Mac, holds the ADR-0002 schema in SQLiteData synced
to the CloudKit **Development** container, and shows the 44 sources seeded from `registry.json`.

**Project and scaffolding (ADR-0001):**

- **`project.yml`:** one multiplatform SwiftUI app target `BrightLights` (iOS and macOS destinations, deployment
  target 27), bundle ID `com.jonphillips.BrightLights`, and CloudKit container `iCloud.com.jonphillips.BrightLights`.
  Team and signing are as in Galavant's `project.yml`. Entitlements: iCloud (CloudKit), plus remote-notification
  background mode for sync.
- **Packages:** `BrightLightsLibrary`; the house's **patched SQLiteData** at
  `../../jon-platform/Vendor/sqlite-data`, by path in both `project.yml` and `BrightLightsLibrary/Package.swift`
  (jon-platform `persistence-and-sync.md`: a first upload needs the patch); and `swift-dependencies`. Nothing else
  until a slice needs it.
- **`.gitignore`:** list the generated `Info.plist` and `.entitlements` paths in the template's slot.
- **`.githooks`:** copy Galavant's four regeneration files (`post-checkout`, `post-merge`, `post-rewrite`,
  `xcodegen-sync`) next to the existing `pre-commit`, per jon-platform `drift-control.md`.
- **`check-drift.sh`** adds `xcodegen generate`, then `xcodebuild build` for an iOS simulator and for macOS, both
  with `-onlyUsePackageVersionsFromResolvedFile`, through `quiet-run`. Commit the project-level `Package.resolved`.

**Schema (new module `BrightLightsSchema` in `BrightLightsLibrary`):**

- **The tree,** with one real foreign key per table (house law 2): `Household` → `Source` → `Listing` → `Reaction`, and
  `Household` → `Stay`. UUID primary keys, and no unique indexes (law 3).
- **`Source`:**
  - From the registry: `registryID`, name, type, priority, area, `mode`, `method`, optional `adapter`,
    `adapterVenue`, `listingURL`, `registeredHosts` and `excludedHosts` (JSON text), and `cadence`.
  - Check outcome, all empty until S3: `lastCheckedAt`, `lastCheckOutcome` (`never`, `succeeded`, `failed`),
    `lastListingCount`, `consecutiveFailures`.
- **`Listing`:**
  - Identity and content: `stableKey`, title, performers (JSON text), room, `ticketURL`, `onSaleAt`.
  - Time: `startsAt` plus a nullable `closesAt`. A null `closesAt` is `.performance(startsAt)`; a non-null one is
    `.run(opens: startsAt, closes:)`. Expose the Swift `ExtractedListing.Time` enum over the two columns, so there's no
    invalid combination.
  - Enums: `status` (`listed`, `soldOut`, `cancelled`, `missing`), `rung`, `capturedBy` (`mac`, `browser`).
  - Timestamps: `firstSeenAt`, `updatedAt`.
- **`Stay`:** `arrivesOn`, plus a departure stored as `departureKind` (`booked`, `tentative`, `open`) and a nullable
  `departsOn`. Expose a Swift enum that has the date only for booked and tentative.
- **`Reaction`:** `kind` (`interested`, `booked`, `pass`, `went`), an optional note, an optional loose `authorID`, and
  `updatedAt`. One reaction per listing is a **household** decision. That's deliberate, despite jon-platform's
  one-row-per-person pattern for opinions: BRAINSTORM settled "no voting". The code-level upsert keeps it to one.
- All enums are persisted as string raw values (house schema hygiene). Register migrations once; they're frozen
  after this slice ships.

**Seeding:**

- **`Household.ensureDefault(in:)`:** mirror Galavant's `TravelParty.ensureDefault`
  (`GalavantLibrary/Sources/GalavantSchema/TravelParty.swift`), including its duplicate convergence.
- **`Source.syncFromRegistry(in:)`:** runs on every launch.
  - Upserts by `registryID` from a bundled copy of `registry.json`: inserts sources that are missing, and updates
    registry-owned fields on existing ones. It never touches check-outcome fields. It skips `retired` and `skip`
    sources.
  - Two devices seeding offline can create duplicates. Converge them per house law 3: the survivor is the lowest
    `(createdAt, id)`; repoint its listings before deleting the losers.
- **The bundled copy** is `BrightLightsSchema/Resources/registry.json`. `check-drift.sh` fails if it differs from
  `docs/sources/registry.json`, so `docs/` stays the file Jon edits.

**Sync:** a SQLiteData `SyncEngine` on the Development container, started per jon-platform `persistence-and-sync.md`.
No sharing UI in this slice.

**UI:** a read-only **Sources** screen: a `NavigationSplitView` on iPad and Mac, a stack on iPhone. Sources are
grouped by mode (Automated, Manual), and each row shows the name, area, method (with adapter), cadence and last check
("never" for now). The detail view shows every field and a link to `listingURL`. Use `@FetchAll`.

**Tests (package):**

- Migrations and the time and departure mappings.
- `ensureDefault`.
- `syncFromRegistry`: an insert, a config update that preserves outcome fields, retired and skipped sources left out,
  and convergence of seeded duplicates (law 3 says to test with them).
- The registry-copy check in `check-drift`.

**Done when:** `check-drift` passes, including both app builds. The app launches in the iPad simulator and on the Mac
and lists 44 sources: 29 automated and 15 manual. The PR adds a `device-passes.md` line: "Bright Lights S2: install
from Xcode on the Mac and the iPad; the sources appear on both through CloudKit Development."

**Not in S2:** fetching, creating listings, stays or reactions UI, sharing, TestFlight.

## S3 — The Mac checks the sources (outline)

The role toggle and lease (ADR-0003, Vinyl Fever's pattern), the per-source cadence scheduler, polite fetching with
the survey's pagination, `RenderedDOMFetcher` for rendered sources, the engine, the change-only upsert, check outcomes
on `Source`, and the failure rule that feeds Rounds. Adds the mini's setup line to `device-passes.md`.

Carried from the S1 review (PR #4):
- **Canonicalize URL identities before keying.** Lowercase the host, collapse doubled slashes, and drop fragments and
  trailing slashes. The Stand's page links one show both as `https://thestandnyc.com//shows/show/14184/...` and as
  `/shows/show/14184/...`.
- **Count a model row without a title separately** from rows with invalid dates.
- **Decide what a date-only model start becomes,** such as a talk without a time. It's dropped today.

## S4 — Stays and What's on (outline)

Entering and editing stays (booked, tentative or open departure). **While we're here** (tonight through departure,
grouped by day) and **Coming up** (the next 60 days around the next stay), with closing-soon and on-sale flags where
the data has them. Reactions. An iPad split view and a compact iPhone layout.

## S5 — Rounds and browser capture (outline)

The Rounds due-list (ADR-0005, point 1) and the persistent in-app browser from `WebExtractorKit` with passive capture
on registered hosts. The capture chip, the manual **Capture** button, and assigning a page to a source.

## M1 done

Jon uses it on the iPad, with the Mac mini or laptop holding the checking role, for a planned or virtual stay: real
listings, reactions, and one full round of manual sources. The device pass is recorded in `device-passes.md`.
