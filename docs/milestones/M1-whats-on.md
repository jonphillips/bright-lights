# M1 — What's on

*Architect, 2026-11-18. Arc: from nothing to Jon, on the iPad, seeing real listings from his sources against a stay,
reacting to them, and doing Rounds for the sources the Mac can't read. Decisions: ADR-0001 to ADR-0005. Wendy,
TestFlight and the CloudKit Production schema are M2.*

## Slice ledger

- [ ] **S1** — Extraction engine (package only)
- [ ] **S2** — App scaffold, schema, seeded sources
- [ ] **S3** — The Mac checks the sources
- [ ] **S4** — Stays and What's on
- [ ] **S5** — Rounds and browser capture

Each slice is one dispatch. The architect expands a slice into a full brief, here, before dispatching it. S1 is
expanded below; S2 to S5 are outlines.

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

## S2 — App scaffold, schema, seeded sources (outline)

The XcodeGen project and the full house scaffolding (ADR-0001). The SQLiteData schema from ADR-0002 (`Household`,
`Source`, `Listing`, `Stay`, `Reaction`) against the CloudKit **Development** container. Sources seeded from
`survey.json`, skipping Music Hall of Williamsburg (closing) and the survey's `skip` sources. A read-only Sources
screen showing each source's method and last check. Adds the generated plists to `.gitignore`.

## S3 — The Mac checks the sources (outline)

The role toggle and lease (ADR-0003, Vinyl Fever's pattern), the per-source cadence scheduler, polite fetching with
the survey's pagination, `RenderedDOMFetcher` for rendered sources, the engine, the change-only upsert, check outcomes
on `Source`, and the failure rule that feeds Rounds. Adds the mini's setup line to `device-passes.md`.

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
