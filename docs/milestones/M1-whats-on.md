# M1 — What's on

*Architect, 2026-11-18. Arc: from nothing to Jon, on the iPad, seeing real listings from his sources against a stay,
reacting to them, and doing Rounds for the sources the Mac can't read. Decisions: ADR-0001 to ADR-0005. Wendy,
TestFlight and the CloudKit Production schema are M2.*

## Slice ledger

- [x] **S1** — Extraction engine (package only)
- [x] **S2** — App scaffold, schema, seeded sources
- [x] **S3** — The Mac checks the sources
- [ ] **S4** — Stays and What's on
- [ ] **S5** — Rounds and browser capture

Each slice is one dispatch. The architect expands a slice into a full brief, here, before dispatching it. S1 to S4
are expanded below; S5 is an outline.

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
from Xcode on the Mac and the iPad with sync on; after both have synced and relaunched, each lists 44 sources (not
88), and one source's detail shows the same ID and Household ID on both."

*Corrected in the S2 review (PR #6): each device seeds its own 44 sources, so "the sources appear on both" passed
without sync. Matching IDs prove the two devices converged on one set.*

**Not in S2:** fetching, creating listings, stays or reactions UI, sharing, TestFlight.

## S3 — The Mac checks the sources

**Goal:** the Mac that holds the checking role reads every automated source on its cadence, politely. It writes
listings with the change-only upsert, and records each check's outcome on `Source`, so the iPad shows real listings
and an honest last-check time for each source. The Mac checks inside the app process (ADR-0003 Amendment 1).

**Builds on S2 (PR #6):** sources are read through S2's one-row-per-`registryID` query, and `syncFromRegistry` only
writes a source when a field changes.

**Schema (one new migration; S2's migration stays frozen):**

- **`Household` gains the lease:** `checkerDeviceID` (UUID text), `checkerDeviceName` and `checkerClaimedAt`, all
  nullable. The device ID alone decides who holds the role, and the name is only a label. A takeover writes all three
  in one update.
- **`Source` gains:**
  - `pagination`: JSON text, nullable, registry-owned (below).
  - `feedURL`: nullable, registry-owned (below).
  - `retiredAt`: nullable (below).
  - `lastContentHash`: nullable; set only by model-rung checks (below).
  - `lastCheckNote`: nullable; the check's warnings or error, in plain words, up to 500 characters.
- **Create the CloudKit Development fields with `cktool`,** for S2's columns as well as these. Follow jon-platform
  `persistence-and-sync.md` § "Adding a synced table or column": a fresh export, your additions, `validate-schema`,
  Jon's OK on the diff, then import. S2 relied on a build, which creates a field only once some row fills it, so
  nil-only columns such as `lastCheckedAt` are missing.

**The registry (registry 1.3; edit `docs/sources/registry.json` and copy it into the bundle):**

- **An optional `pagination` per source.** If it's absent, the checker reads one page. Two kinds come from the
  survey's notes:
  - `{"kind": "pages", "template": "…/page/{n}/", "first": 2, "max": 6}` reads `listing_url`, then pages from
    `first` up. `max` is the last page number, so this reads pages 2 to 6. It stops at a page with no listings, a
    non-200 response, or `max`. The empty-page stop applies only after the first page; page 1 always goes to the
    engine. Reaching `max` without an empty page means the listings may go on, so that check marks nothing missing
    (it needs no note). Use it for `bowery-ballroom` and `mercury-lounge`
    (`https://mercuryeastpresents.com/<venue>/page/{n}/`).
  - `{"kind": "months", "template": "…/{yyyy-MM}", "months_ahead": N}` reads `listing_url`, then the current NYC
    month through N months ahead. It doesn't stop at an empty month, because The Stand has gaps. Use it for
    `the-stand` (`https://thestandnyc.com/shows/{yyyy-MM}`, 7) and `ny-comedy-club`
    (`https://newyorkcomedyclub.com/calendar/{yyyy-MM}`, 6).
  - Every other source reads one page. That includes `irving-plaza`: confirm in the live pass whether its site
    paginates, and report it rather than guessing. UCB stays at first-page depth with no "Load more"
    (open-questions).
- **An optional `feed_url` per source:** the JSON endpoint the checker reads instead of `listing_url`.
  `listing_url` stays the page a person opens. The survey's `api_evidence_url` gives the two in use:
  - `brooklyn-steel`: `https://aegwebprod.blob.core.windows.net/json/resources/8/events/d099bg4x01/events.json`
  - `caveat`: `https://caveat.nyc/api/events/listings`

  Store it on `Source` as a nullable, registry-owned `feedURL` column in S3's migration, alongside `pagination`.
- **Retired sources.** When a source leaves the seedable set (retired, `skip`, or gone from the registry),
  `syncFromRegistry` sets `retiredAt`. If the source returns, it clears it. A retired source is never checked and
  isn't listed on the Sources screen. Its rows and listings stay, so reactions keep their history, and ADR-0002's
  pruning still applies.

**The role (ADR-0003 and its Amendment 1):**

- **This Mac's identity** is a device-local UUID in `@Shared(.appStorage)` (law 4), plus the Mac's localized host
  name.
- **Settings** (a gear on the Sources screen; the first Settings screen):
  - **Mac:** a "Check sources on this Mac" toggle.
    - Turning it on when another Mac holds the role asks first: "<name> is checking now. Make this Mac the checker?"
      Then it writes the lease, registers the app as a login item with `SMAppService.mainApp`, and runs one pass
      straight away. Vinyl Fever learned not to wait for the next tick (its M13).
    - Turning it off unregisters the login item. The lease stays until another Mac takes it.
    - Show the lease holder, and when macOS needs approval, a note with an **Open Login Items** button
      (`SMAppService.openSystemSettingsLoginItems()`).
    - A **Check all now** button runs every automated source regardless of cadence. It shows only while this Mac holds
      the role.
  - **iPad and iPhone:** a read-only line saying which Mac checks, and when the household's most recent check ran.
  - **Every platform:** the model key field, through `LLMClientKit`'s `APIKeyStore` in the app's default access
    group, as in Galavant's Settings.
  - **Sync:** the checker requires sync to be on. If sync is off, the toggle explains that and does nothing.
- **The Mac app stays running with no window open while it holds the role** (an `NSApplicationDelegateAdaptor`
  returning false from `applicationShouldTerminateAfterLastWindowClosed`). Reopening the app shows a window again.
- **A Mac that doesn't hold the lease never checks,** including one whose toggle is still on (tested). So the lease
  check and the takeover live in the package, not the app target. The lease reads the canonical household (the
  lowest `(createdAt, id)`, as `ensureDefault` converges), never an arbitrary first row.

**The scheduler (Mac only):**

- **An `NSBackgroundActivityScheduler`** repeats hourly with a generous tolerance. Each tick runs one pass if this
  Mac holds the lease and isn't already running a pass. Hold a `ProcessInfo` activity for the length of a pass, so App
  Nap can't stall it.
- **One pass at a time,** whether a tick, **Check all now** or the takeover started it. Claim the running flag before
  the first `await`, so two callers can't both get past the check.
- **Due rules** are a pure function of `(source, now, stays)`, tested:
  - `nightly`: due when the last check is more than 20 hours old.
  - `weekly`: due when the last check is more than 6 days and 20 hours old.
  - A source that has never been checked is due.
  - During a stay, every source counts as nightly. A stay covers a day from 2 days before `arrivesOn` through
    `departsOn`. For an open departure, use 7 days after arrival. Stays can't be entered until S4, but the rule reads
    the table now. Days are `America/New_York` calendar days, and "through" includes the whole last day: the window
    ends at the start of the day after it.
- **A pass** checks due automated sources one at a time, the longest-overdue first.

**Fetching (a `@DependencyClient`, so tests never touch the network):**

- **Identify honestly:** a `User-Agent` of `BrightLights/<version> (personal, non-commercial)`, with the version
  read from the bundle. No cookies carry over between passes, and the checker never logs in. Use one ephemeral
  `URLSession` for the client, not a new session per request.
- **robots.txt:** fetch it once per host per pass. Honor `Disallow` for our agent and for `*`, and honor
  `Crawl-delay`. If robots.txt is unreachable, as with AEG's blob host (HTTP 400 in the survey), treat it as having
  no rules, the way the survey did. A disallowed path fails the check with a note. Match the way RFC 9309 does:
  - Consecutive `User-agent` lines form one group.
  - `*` in a rule matches any run of characters, and a trailing `$` anchors the end.
  - A rule matches against the path plus the query.

  `Allow` can stay unsupported, which errs toward not fetching.
- **Pace:** wait at least 1 second between requests, or the crawl delay if it's longer. Requests are serial; there
  are no parallel fetches.
- **Challenges count as failures:** HTTP 403 or 429, a bot-challenge page, or a login redirect. The checker never
  retries around one within a pass. Detect a challenge page by markers that only real challenge pages carry:
  - Cloudflare's `cf-chl` or `/cdn-cgi/challenge-platform`, or a title of "Just a moment...".
  - PerimeterX's `px-captcha`.
  - A page title of "Access denied" or "Verify you are human".

  Don't match bare words like "captcha" anywhere in a page. Normal pages carry reCAPTCHA on newsletter forms, and
  Squarespace sites such as Union Hall often do.
- **`rendered_scrape` sources** use `WebExtractorKit`'s `RenderedDOMFetcher`. That adds `WebExtractorKit` to the app,
  as ADR-0001 point 5 planned. Today the fetcher loads with WebKit's persistent default data store and Safari's
  User-Agent, which breaks the two rules above. So it gets options, in a **jon-platform package PR first**
  (agent-collaboration.md § "Dispatches whose code lands in jon-platform"):
  - A non-persistent website data store.
  - A custom User-Agent.
  - The main frame's HTTP status, if WebKit exposes it. If it doesn't, say so in the PR; the challenge markers then
    carry the load.

  The same PR adds the fetcher's SEAM-LEDGER row naming Bright Lights. This PR adopts it once that merges.
- **JSON sources** are the ones with a `feed_url`. They're fetched from it and read as `PageDocument.json`.
  Everything else is read from `listing_url` as `.html`. That includes `union-hall`, which is `platform_feed` but
  has no feed: its page is HTML. Robots and pacing apply to the feed host like any other.

**Extracting and the model ration (ADR-0004 point 4):**

- **Run the engine on each page** and merge the results by stable key.
- **Hash every page** with `ExtractionEngine.pageHash(for:)` and combine the page hashes. A check that used the
  model rung saves the combined hash in `lastContentHash`. A check that didn't clears it.
- **The skip:** if the next check's combined hash matches, skip extraction entirely. Record a success with the
  previous count, and the note "unchanged; model not called". Sources that use the deterministic rungs always run
  the engine, because the visible-text hash can't see a change inside JSON-LD. Their change-only upsert keeps the
  writes down.
- **No model key:** a model-rung source fails with the note "no model key".
- **Log each model call** to OSLog with the source ID, page count and listing count (ADR-0004 consequences).
- **Carried from the S1 review (PR #4), in the engine:**
  - **Canonicalize URL identities before keying:** lowercase the host, collapse doubled slashes, and drop fragments
    and trailing slashes. The Stand links one show as both `https://thestandnyc.com//shows/show/14184/...` and
    `/shows/show/14184/...`.
  - **Count a model row with no title separately** from rows with invalid dates.
  - **A start with a date but no time is dropped and counted** in its own warning. This decides the open question:
    a date-only start never becomes midnight. If talks go missing because of it, the counts will show it, and we
    revisit.

**The upsert (ADR-0002 point 3), in `BrightLightsSchema`, tested:**

- **Match by `stableKey` within the source.** Read through a one-row-per-key rule: the survivor is the lowest
  `(firstSeenAt, id)`.
- **On write, converge any duplicates for a key.** Repoint their reactions to the survivor, then delete the losers.
  The browser (S5) is a second writer of the same keys, so duplicates will happen.
- **New key:** insert with `firstSeenAt` and `updatedAt` set to now, and `capturedBy: .mac`.
- **Existing key:**
  - Compare the content fields: title, performers, room, ticket URL, on-sale time, time, and status. Write only if
    one differs. That write also refreshes `rung`, `capturedBy` and `updatedAt`.
  - A provenance change alone isn't a write.
  - Map the engine's status straight across; it never produces `missing`.
- **Missing listings:**
  - On a complete, successful check, a future listing of this source that the check didn't return becomes
    `missing`.
  - A `missing` listing that comes back becomes `listed` again.
  - A partial check never marks anything missing. That's one where page 1 succeeded but a later page failed: the
    check counts as a success with a note.
- **Pruning,** once per pass: delete past listings with no reaction 30 days after they end (`closesAt`, or else
  `startsAt`). Reactions keep their listings.
- **One `Listing` query helper** holds the one-row-per-key rule, so S4 reads through it too.

**Check outcomes on `Source`, written once at the end of each source's check:**

- **On success:** set `lastCheckedAt`, `lastCheckOutcome = .succeeded`, `lastListingCount`, `consecutiveFailures = 0`
  and `lastCheckNote` (the warnings, if any).
- **On failure:** set `lastCheckedAt`, `.failed`, and the note, and increment `consecutiveFailures`. Leave the count
  and the listings untouched.
- **Zero is a failure:** a check that returns no listings when `lastListingCount` was 3 or more counts as failed,
  with the note "returned no listings (was N)". Its listings aren't marked missing. The 3 here is its own constant,
  not the failure threshold's, though the values match. An empty page 1 goes through this rule like any other empty
  result; it isn't a separate failure.
- **`Source.needsManualLook`:** add this computed property, true when `consecutiveFailures >= 3` or the latest
  failure was the zero drop. That second case means `lastCheckOutcome == .failed` and a note starting "returned no
  listings (was". S5's Rounds reads it.
- **Log each source's report** (outcome, listing count, rungs, pages read, model calls, rows written and note) to
  OSLog, so the live pass's table comes from the log.

**UI:**

- **Sources rows** show the last check as relative time and its outcome, with a warning badge when
  `needsManualLook` is true.
- **The detail view** shows the check note and the source's current listings, read-only and deduplicated: the date,
  title and status, soonest first. That's enough to verify S3 on the iPad; S4 builds the real views.

**Tests (package; all network and model calls stubbed):**

- The due rules: nightly, weekly, never checked, a stay window that includes an open departure, and an hour late on
  the departure day itself.
- The lease: a non-holder does nothing, a takeover writes all three fields, and a toggle turned off leaves the lease.
- **robots.txt parsing:** our agent versus `*`, `Crawl-delay`, an unreachable file, consecutive `User-agent` lines,
  a `*` and `$` rule, and a rule on the query.
- **Challenges:** a Cloudflare challenge page fails the check, and a normal page with a newsletter reCAPTCHA doesn't.
- **Pagination:**
  - `pages` stops at an empty page and at `max` (a page number), and reaching `max` marks nothing missing.
  - An empty page 1 meets the zero rule.
  - `months` reads past an empty month.
  - A failed later page makes a partial check.
- **A pass over the fixtures:** stubbed fetches of `bowery-ballroom.html`, `brooklyn-steel.json` and `caveat.json`
  insert their listings and record their outcomes. The stub answers only exact URLs, so the two feed sources pass
  only if they're read from `feed_url`. A `platform_feed` source with no feed is read as HTML.
- **Running the same pass again writes nothing.** Use S2's `SyncMetadata` probe to prove it.
- **The upsert:**
  - A changed title updates the row.
  - A provenance-only change doesn't.
  - A missing listing is marked, then restored.
  - A partial check marks nothing missing.
  - Seeded duplicate listings converge and keep their reaction.
  - Pruning keeps a past listing that has a reaction.
- **The model ration:** an unchanged hash never calls the stub model, and a changed one does.
- **The failure rule:** three failures in a row, and the drop to zero.
- **`syncFromRegistry`:** retiring a source and bringing it back, and `pagination` and `feed_url` round-trip through
  their columns.
- **The engine:**
  - Keys from the two forms of the Stand URL are equal.
  - A missing title gets its own count.
  - A date-only start gets its own count.

**Done when:** `check-drift` passes; closeout (ADR-0005 D16).

- **The live pass:** the PR reports one real **Check all now** on Jon's laptop, with sync on, from a clean store. Give
  a table of every automated source: its outcome, listing count, rung, pages read, and note. Also give the number of
  model calls and the pass's total time. Then run a second **Check all now** straight away and report how many
  listing rows it wrote; it should be close to zero.
- **The gate it owes,** for the mini's setup (ADR-0003 Consequences): on the Mac mini, install from Xcode, turn sync
  on, enter the model key, turn on "Check sources on this Mac" and approve the login item. After a night, the iPad
  shows last-check times and listings for the automated sources.

*Amended in the S3 review (PR #8). The first brief gave the checker no way to reach the two JSON feeds, so it read
Brooklyn Steel's and Caveat's HTML pages as JSON. Registry 1.3 now carries `feed_url`. Also settled here:*

- *`max` is a page number.*
- *An empty page 1 meets the zero rule.*
- *robots.txt matching follows RFC 9309.*
- *Challenge markers are only ones that real challenge pages carry.*
- *The stay window includes the whole departure day.*
- *There's one pass at a time.*
- *The lease logic lives in the package.*
- *Each report is logged.*
- *The rendered fetcher gets a non-persistent store and our User-Agent, in a jon-platform PR first.*

**Not in S3:**

- Stays UI, What's on, and reactions UI (S4).
- Rounds and browser capture (S5).
- Notifications.
- A UCB "Load more".

## S4 — Stays and What's on

**Goal:** Jon enters a stay on the iPad and sees what's on against it. **While we're here** shows tonight through
departure, and **Coming up** shows the next 60 days laid against his stays, with the deadlines that matter while
he's away. He reacts to listings, and the iPhone shows the same stays and reactions.

**Builds on S3 (PR #8):**
- Listings are read through `Listing.canonical`, the one-row-per-key helper.
- The checker already reads `Stay` for its due rules, so a stay entered here makes every source nightly during it.
- `Reaction.upsertForListing` (S2) already keeps one reaction per listing.

**No schema change.** S4 adds no table or column, so there's no migration and no CloudKit import. If the build
seems to need one, stop and say so in the PR.

**Days and times (decided here):**
- A **day** is an `America/New_York` calendar day, whatever the device's time zone. Jon plans from home, outside
  New York.
- `Stay.arrivesOn` and `departsOn` are stored as the **start of that New York day**. That's what S3's due rules
  already assume.
- Listing times show in New York time. When the device's time zone isn't New York's, add "ET".

**The read model: `WhatsOnProjection`, a pure value in `BrightLightsSchema`.** This mirrors Galavant's
`TodayProjection`: a value derived from rows, never stored.
- Its input is the canonical listings, their sources, the stays, the reactions, `now`, and a New York calendar.
- Its output is the sections below.
- Views only render it. Every rule in this section lives in the projection and is tested there.

**Stays in the projection:**
- **A stay's window** runs from its arrival day through its departure day.
  - An open departure counts as 7 days after arrival, as S3's due rule does.
  - A stay is **current** when today is inside its window.
  - The **next stay** is the earliest one arriving after today.
- **Overlapping stays** (two devices offline can make them) are tolerated: the projection uses the earliest-arriving
  current stay. The editor prevents new overlaps (below).

**Which listings show:**
- **Performances and runs:**
  - A **performance** counts as on until 2 hours after its start, so tonight's 8 p.m. show still appears at 9:30.
  - A **run** (`closesAt` set) is on from its opening day through its closing day.
- **Status:**
  - `listed` and `soldOut` show; sold out gets a badge.
  - `cancelled` and `missing` show only if the listing has a reaction, with a "Cancelled" or "No longer listed"
    badge. That way a booked show that vanishes isn't silently dropped. S3's open question about `missing` on
    one-page sources is why this matters.
- **Reactions:**
  - A listing marked **pass** is hidden. Each section shows "N passed", and tapping it reveals them.
  - If offline edits leave a listing with several reactions, the projection reads the one with the latest
    `updatedAt`, ties broken by `id`.
- **The filter,** one control shared by both screens: **All**, **Interested & booked**, or **Booked**.

**While we're here:**
- **When there's a current stay:**
  - Listings from now through the end of its departure day, grouped by day. Headings read "Tonight", "Tomorrow",
    then the weekday and date. Within a day, sort by start time, then by source name.
  - **Runs** that overlap the window appear once, in a **Running** group at the top, never repeated each day.
- **An extra day:** when the departure is tentative or open, one more group follows the last day, headed "If you stay
  through <weekday>". It covers the day after departure, to support "stay through Sunday and you catch X". A booked
  departure has no extra day.
- **When there's no current stay:** an empty state saying when the next stay starts, or "No stay planned", with an
  **Add stay** button.

**Coming up:**
- **The window** is today through 60 days ahead.
- **Deadlines,** a group at the top:
  - **On sale soon:** listings whose `onSaleAt` falls in the next 14 days, soonest first.
  - **Closing:** runs that close inside the window. Each says how many stays remain before it closes. "Closes Jan 12
    — before your next stay" when none, and "Closes Jan 12 — your last stay before it closes" when one.
  - Deadlines ignore the stay filter below, because booking happens while away.
- **When there are future stays in the window:** one group per stay ("Feb 9–15", with "tentative" or "open" noted),
  holding the listings inside its window, by day as in While we're here. A current stay's group starts tomorrow;
  tonight belongs to While we're here.
- **With no stays in the window:** every listing in the window, grouped by week, with a note: "Add your next stay to
  narrow this".
- **Show everything:** a toggle that always shows the whole window by week, stays or not.

**Each listing row and its detail:**
- **The row:** time, title, source name (and room if any), the badges, and the reaction if one is set.
- **The detail:**
  - Title, performers, venue and room, the full date and time (or the run's dates), status, and on-sale time.
  - A **Tickets** link to `ticketURL`. It opens in the system browser until S5's in-app browser exists.
  - The reaction controls.

**Reactions:**
- **Setting one:** pick Interested, Booked, Pass or Went, or **Clear**.
  - On the row, use swipe actions on iPhone and a context menu on iPad and Mac. The detail has the full control.
  - **Went** is offered only once the listing has started.
  - Writes go through `Reaction.upsertForListing`.
  - **Clear** deletes the listing's reactions (add `Reaction.clear(listingID:in:)`, which deletes every duplicate
    too).
- **The note** is optional free text, edited in the detail.
- **`authorID` stays nil in M1.** Attribution arrives with Wendy (M2).

**Stays (a new screen):**
- **The list:** upcoming and current stays first, soonest first, then past stays in a collapsed section.
- **The editor** (a sheet):
  - An arrival date, a departure kind (**Booked**, **Tentative** or **Open**), and a departure date unless Open.
  - Its rules are pure functions in the package, and tested:
    - The departure can't be before the arrival.
    - A new or edited stay can't overlap another stay's window; name the stay it overlaps.
    - Dates are normalized to the start of the New York day.
- **Deleting** asks first, and it doesn't touch listings or reactions.

**Navigation (mirror Galavant's `AppContainer`):**
- **One `AppScreen` enum** drives the shell: **While we're here**, **Coming up**, **Stays**, **Sources**. S5 adds
  Rounds.
- **The shell:**
  - With `prefersTabNavigation` (iPhone), it's a `TabView` with a `NavigationStack` per tab.
  - Otherwise (iPad and Mac), a `NavigationSplitView`: the sidebar lists the screens, and the detail is one stable
    `NavigationStack`.
  - Listing detail is pushed onto the stack. `@SceneStorage` restores the selected screen.
- **Defaults:** the app opens on While we're here when there's a current stay, otherwise on Coming up.
- **Sources** keeps its screen, as S3 built it, and the Settings gear.
- The Mac build compiles and works in the split view; it doesn't need anything Mac-specific.

**Reading:** `@FetchAll` over `Listing.canonical`, limited to listings that end on or after the start of today and
start before 60 days out. Read the stays, reactions and sources whole: they're small. Build the projection from
those in the view, or in a small `@Observable` model if the view gets heavy.

**Tests (package):**
- **Stays:**
  - The current stay for booked, tentative and open departures.
  - The next stay.
  - Overlapping stays: the earliest-arriving one wins.
- **Days:**
  - New York grouping with the calendar's time zone set elsewhere (Los Angeles).
  - A late show just after midnight belongs to the next day.
  - A DST-change week.
- **Visibility:**
  - A performance still shows 2 hours after its start and is gone at 2 hours and 1 minute.
  - A run appears once in **Running**.
  - `cancelled` and `missing` are hidden without a reaction and badged with one.
  - Pass listings are hidden, and the count is right.
- **While we're here:**
  - The extra day for tentative and open departures, and none for booked.
  - The no-stay empty state.
- **Coming up:**
  - Per-stay groups.
  - A current stay's group starts tomorrow.
  - The no-stay fallback by week.
  - **Show everything.**
- **Deadlines:**
  - On sale in the next 14 days, and not on day 15.
  - The closing count with zero, one and two stays before it closes.
- **The filter:** all three settings.
- **Reactions:**
  - With duplicate reactions, the latest one is read.
  - `Reaction.clear` removes every duplicate.
- **The stay editor:** the departure rule, the overlap rule naming the other stay, and New York normalization from
  another time zone.

**Done when:** `check-drift` passes; closeout (ADR-0005 D16).

- **The gate it owes,** for Jon on real devices:
  - **On the iPad:** add a tentative stay covering today. While we're here then shows tonight's real listings by day,
    with an "If you stay through" group.
  - Mark one listing Interested and another Booked, and add a note to one.
  - **On the iPhone, after sync:** the stay and both reactions appear, **Booked** shows only the booked one, and the
    note matches.
  - **Back on the iPad:** Coming up shows a Deadlines group if any on-sale or closing dates exist. Change the stay to
    booked, and the extra-day group disappears.

**Not in S4:**

- Rounds, the in-app browser and capture (S5).
- Taste ranking, editorial picks, getting-home times, and suggesting when to come (M2).
- Notifications, calendar reading, and inviting Wendy.

## S5 — Rounds and browser capture (outline)

The Rounds due-list (ADR-0005, point 1) and the persistent in-app browser from `WebExtractorKit` with passive capture
on registered hosts. The capture chip, the manual **Capture** button, and assigning a page to a source.

## M1 done

Jon uses it on the iPad, with the Mac mini or laptop holding the checking role, for a planned or virtual stay: real
listings, reactions, and one full round of manual sources. The device pass is recorded in `device-passes.md`.
