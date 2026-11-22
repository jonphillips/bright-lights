# M2 — Wendy joins

*Architect, 2026-11-21. Arc: from Jon alone in CloudKit Development to Jon and Wendy sharing one household in
Production. Jon installs from TestFlight, the mini checks into Production, and Wendy reacts from her own iPhone.
Decisions: [ADR-0009](../../decisions/0009-production-and-wendy.md) and its Amendment 1. Taste ranking leads M3. Its
open questions are in `open-questions.md`, and the taste record restarts at the cutover.*

## Slice ledger

- [x] **S1** — Production and TestFlight
- [x] **S2** — Inviting Wendy

Each slice is one dispatch. The architect expands a slice into a full brief, here, before dispatching it. Both are
expanded below. S1 follows [check-report](../../efforts/archive/check-report.md), whose report is how the first
Production nights get read. S2's code doesn't need Production, but its device pass runs after the S1 cutover.

## Schema read before Production (architect, 2026-11-21)

Production's schema is permanent (jon-platform `persistence-and-sync.md` § Schema hygiene), so every synced column
from migrations v1 to v4 was read once more before S1:

- **The names, types and tree hold.** Every table has UUID keys, one real foreign key, and no unique index. Every
  persisted enum is stored as string text. The Development schema matches all four migrations, from the 2026-11-20
  import (`docs/cloudkit/SCHEMA-PROPOSAL.md`).
- **The registry's fixed-set strings** (`cadence`, `priority`, `type`, `method`) are TEXT. Typing them in Swift later
  needs no schema change, so nothing permanent is at stake.
- **A bug to fix in S2:** `Household.ensureDefault` repoints a losing household's sources and stays, but not its
  taste records, so `ON DELETE CASCADE` deletes them. A `TasteRecord`'s ID is derived from its household ID, so
  repointing means re-keying. S2 rewrites `ensureDefault`, so the fix goes there.
- **The only addition before the first deploy** is `households.registryVersion` (S1). `people` follows in S2 as an
  additive deploy.

## S1 — Production and TestFlight

**Goal:** Release builds sync to Production on every platform, iOS ships through `testflight`, and the checking
Mac's installed build points at Production. Registry writes are gated by version. Jon runs the cutover after the
merge (below). Branch `m2/s1-production-testflight`.

### Decisions pinned in this plan

- **The Mac's signing is measured** (ADR-0009 Amendment 1, point 1). The development profile allows CloudKit
  Production but only `aps-environment: development`. So the Mac's Release build carries
  `icloud-container-environment: Production` and keeps the development push environment. There's no stop-and-ask
  step.
- **Release means Production, Debug means Development** (Amendment 1, point 2), on iOS and macOS alike. In code,
  `#if DEBUG` is the switch.
- **One database file per environment** (Amendment 1, point 3). Release opens its own file, and Debug keeps today's.
- **CI is added,** because `testflight` refuses to release until `main` has green CI runs, and Bright Lights has none.

### The work

1. **Entitlements by configuration.**
   - **Release**, for both iOS and macOS, signs with `com.apple.developer.icloud-container-environment: Production`.
   - **Debug** signs without it.
   - **The macOS file** keeps `aps-environment: development` in both configurations, and keeps its CloudDocuments
     and ubiquity entries.
   - **iOS** keeps `aps-environment: development` in the project. TestFlight's distribution signing turns it into
     `production`, and `testflight`'s export verifier checks that.

   Express this in `project.yml` however XcodeGen allows, for example a second tracked macOS entitlements file
   chosen by `CODE_SIGN_ENTITLEMENTS` per configuration. List any new generated file in `.gitignore`.
2. **The store per environment.** `bootstrapBrightLightsDatabase` opens `BrightLights-Production.sqlite` in Release
   and today's default file in Debug, through `SQLiteData.defaultDatabase(path:)`. Put the Release file in the same
   directory as the Debug one. `attachMetadatabase` names its metadatabase after the file, so nothing else changes.
   Keep the file choice in one function, and test that Debug and Release give different paths.
3. **Sync policy.** One `SyncPolicy` (or similar) in the app target answers "should sync run?":
   - **Release:** always, when the iCloud account is available.
   - **Debug:** today's persisted opt-in (`BrightLightsCloudKitSyncEnabled`) and its launch argument.

   `startSyncIfEnabled`, Settings' sync toggle and the checker's sync precondition all read it. In Release,
   Settings shows "iCloud sync: on" with no toggle. On every build, Settings' Sync section shows the environment
   ("Production" or "Development") next to the build stamp, so "which build, which environment?" can be answered
   from the device (jon-platform `persistence-and-sync.md` § Before any sync or CloudKit check).
4. **A checker pass starts by syncing.** `CheckerRuntime.check` calls `syncEngine.syncChanges()` before it reads
   sources and stays, and again after the pass writes. A failure there is logged to `SourceChecks` and doesn't stop
   the pass. The Mac's pushes may not arrive (Amendment 1, point 1), and the mini can sleep through them anyway.
5. **`Household.registryVersion` and the version gate** (ADR-0009 point 5).
   - **Migration "Add registry version v5":** `ALTER TABLE "households" ADD COLUMN "registryVersion" TEXT`. It's
     nullable, and v1 to v4 stay frozen.
   - **`RegistryVersion`,** a value type parsed from a dotted string and compared component by component as
     integers: `1.10` is newer than `1.9`, and `1.3` equals `1.3.0`. A string that doesn't parse throws.
   - **In `syncFromRegistry`,** after `ensureDefault`, compare the bundled `registry_version` with the canonical
     household's stored one. Duplicate convergence always runs, because it isn't a registry write.
     - Bundled is the same or newer, or nothing is stored: write as today (inserts, field updates, retirements).
       Then store the bundled version, if it changed.
     - Bundled is older: insert, update and retire nothing, and leave the stored version alone. The build still
       reads and checks.
   - **`check-drift.sh`** fails when `docs/sources/registry.json` differs from `origin/main`'s copy without a higher
     `registry_version`. Skip the check, with a one-line note, when `origin/main` isn't available, as in a shallow CI
     clone.
6. **`cloudkit-expected-fields.txt`** at the repository root lists every synced field as `<recordType> <field>`
   lines, in Galavant's format. That's each column, its `sqlitedata_icloud_userModificationTime_<column>`, and each
   record type's bare `sqlitedata_icloud_userModificationTime`, for all six tables, `registryVersion` included. A
   package test reads the file by path from `#filePath`, and fails if any column of a synced table is missing, or if
   the file names a table or column that the migrated schema lacks. Every later synced column then fails a test
   until it's listed, and `testflight` checks the list against Production.
7. **`testflight.conf`,** with Galavant's keys and Bright Lights' values: `SCHEME=BrightLights`,
   `PROJECT=BrightLights.xcodeproj`, `XCODEGEN=1`, `TEAM_ID=7MQEE539G9`,
   `APP_BUNDLE_ID=com.jonphillips.BrightLights`, `EXTENSION_BUNDLE_IDS=""`, `APP_GROUP=`,
   `CLOUDKIT_CONTAINER=iCloud.com.jonphillips.BrightLights`, `SCHEMA_GATE=1`,
   `EXPECTED_SCHEMA_FIELDS=cloudkit-expected-fields.txt`, `ASC_VERSION=5.17.1`, `TEST_NOTES_LOCALE=en-US`,
   `DONE_LOG=docs/DONE-LOG.md` and `DEVICE_PASSES=docs/device-passes.md`. `.gitignore` already covers `/build/`.
8. **CI.** Add `.github/workflows/ci.yml` as Galavant's thin caller of `jonphillips/ci-workflows`'
   `ios-ci.yml@main`, with `package-path: BrightLightsLibrary`, `platform-relative-root: "../.."` (the manifest
   reaches `../../jon-platform`), the default test runner, and `secrets: inherit`. If the hosted runner can't build
   the package yet, the workflow's capability gate skips the tests green and says so. That's expected.
9. **`scripts/install-bright-lights`** builds Release by default.
   - **Release:** verify the signed `icloud-container-environment` is `Production` and `aps-environment` is
     `development`.
   - **`--configuration Debug`:** verify there's no container environment.
   - Replace the "Production is held for M2" error, and name the environment in the summary table and in the `-n`
     plan.

### Tests (package)

- `RegistryVersion`: `1.10` > `1.9`, `1.3` == `1.3.0`, `2.0` > `1.99`, and a malformed string throws.
- The gate, each with a stored version and a bundled registry:
  - An older bundle changes no source field, inserts no source, retires none, and leaves `registryVersion` alone.
  - A newer bundle writes the fields and stores its version.
  - An equal bundle writes, and a nil stored version writes and stores.
  - Convergence of seeded duplicate sources still runs under an older bundle.
- Migration v5 adds `registryVersion`, and a household from v4 reads it as nil.
- The expected-fields test above, and the database-path test.

### Done when

- `scripts/check-drift.sh` passes, with SwiftLint, the package tests, both app builds and the registry-version
  check.
- CI on the PR is green, or skipped green by the capability gate, which the PR says.
- The PR lists `codesign -d --entitlements -` for a Release and a Debug macOS build, or marks them **not run** with
  the reason, since the architect reruns them.
- Closeout (ADR-0005 D16), with a device gate whose check is § S1 cutover, below.

**Not in S1:** sharing, `Person`, sync health, the survivor rule, and backup or restore (ADR-0009 point 1).
**Escalates:** schema and sync, so Jon merges. At review, the architect runs `persistence-and-sync.md` § Adding a
synced table or column, steps 1 to 6, for `registryVersion`, with Jon's OK on the diff.

### S1 cutover (Jon)

After the merge, in this order. The Mac goes first, because the oldest household wins until a share exists.

1. **Deploy the schema.** In the CloudKit Console, deploy Development to Production for
   `iCloud.com.jonphillips.BrightLights`. This can't be undone. The architect has checked that Development holds
   everything, `registryVersion` included.
2. **App Store Connect.** Create the iOS app record for `com.jonphillips.BrightLights`, and an internal testing group
   with Jon in it.
3. **Dry run.** On clean `main` with green CI, `testflight --dry-run` passes preflight, schema parity and the
   expected fields.
4. **The checking Mac.** Run `scripts/install-bright-lights` (Release). Open the app. Settings shows "Production"
   and the merged commit. Turn **Check sources on this Mac** off and on, so the Mac claims Production's empty lease
   and runs a pass. When it's done, Sources lists 44 and some listings show.
5. **TestFlight.** Run `testflight`. Install the build on the iPad and the iPhone. Each shows "Production". After a
   sync, each lists 44 sources (not 88), and Bowery Ballroom shows the same source ID and household ID as on the
   Mac.
6. **Re-enter** the stays and the source fixes (start pages and flags) on the iPad.
7. **Pushes.** With the Mac app open, add a stay on the iPad, and note whether it appears on the Mac within a minute
   without **Check now**. Either answer passes. Tell the architect which, for Amendment 1.
8. **The next morning,** `scripts/check-report --days 1` shows the night's Production checks.

## S2 — Inviting Wendy

**Goal:** Jon shares the household from the iPad. Wendy accepts on her iPhone through TestFlight, sees what's on,
and her reactions show her name on Jon's devices. A participant's own household never survives, and never leaks
into the share (ADR-0009 points 6 and 7, Amendment 1 point 4). Branch `m2/s2-inviting-wendy`.

**Builds on S1:** Production, the sync policy, and `cloudkit-expected-fields.txt`, whose test makes the new table
list its fields.

### Decisions pinned in this plan

- **Sharing state is a three-case enum,** `HouseholdSharing`: `.private`, `.sharedByMe` (this account owns it and
  its `SyncMetadata.isShared` is true), and `.sharedWithMe` (its `SyncMetadata.ownerName` isn't
  `CKCurrentUserDefaultName`, so it lives in another person's zone). Each household's state is read from its
  `SyncMetadata` row. With no metadata, as in tests or before sync, it's `.private`.
- **The survivor** is a pure function over `[(Household, HouseholdSharing)]`. It picks `.sharedWithMe` first, then
  `.sharedByMe`, then `.private`. Within a case it keeps M1's `(createdAt, id)` order, so it's a total order.
  `ensureDefault` and `Household.canonical` must pick the same household. If `canonical` can't see sharing state in
  SQL, replace it with a function over the fetched households, since there are at most a few rows.
- **When the survivor is shared,** losing households are deleted with their children by cascade. Nothing is
  repointed or re-parented. **When it's private** (M1's rule, between one person's devices), losers are repointed as
  today. That now includes taste records, re-keyed to the survivor: on a key collision, the later `updatedAt` wins.
  It also includes people (below).
- **`Person` IDs are derived,** as `TasteRecord`'s are: `Person.id(householdID:recordName:)`, a SHA-256 of
  `"<householdID>|<recordName>"` shaped as a UUID. Two of Jon's devices write the same row, so there's no duplicate
  to converge.
- **A device binds itself, with no picker.** There are two people, each on their own devices, so Galavant ADR-0051's
  picker and "acting for someone else" aren't needed. Binding needs only this device's own
  `CKContainer.userRecordID()`. It never matches share participants across devices, so ADR-0051's OQ1 doesn't
  arise.

### The work

1. **Schema: migration "Add people v6".** Create `people`: `id` (TEXT primary key),
   `householdID` (references `households`, `ON DELETE CASCADE`), `iCloudUserRecordName` (TEXT, not null),
   `displayName` (TEXT, not null, empty by default) and `createdAt`, plus an index on `householdID`. In Swift it's
   `@Table("people") struct Person`. Add it to the `SyncEngine`'s tables and its fields to
   `cloudkit-expected-fields.txt`.
2. **Binding.** `Person.bind(recordName:participantGivenName:in:)` runs after `ensureDefault` on the canonical
   household:
   - It upserts the derived row, writing only when it's missing, or when `displayName` is empty and a participant
     given name is available.
   - It returns the ID, which the app stores in a device-local `@Shared(.appStorage("brightLightsCurrentPersonID"))`
     (house law 4).
   - The app calls it at launch after sync's first `syncChanges()`, and after a share is accepted. The record name
     comes from `CKContainer.userRecordID()`. The given name comes from the canonical household's `CKShare`
     `currentUserParticipant`, when the household is shared.
   - With no account, nothing binds, and `authorID` stays nil.
3. **Attribution.** Every reaction and taste-record write passes the current person's ID: `ScreenList`'s
   `Reaction.screen(authorID:)`, the reaction menu in `SourcesView`, and any other caller of `upsertForListing`.
   Wherever a reaction's kind is shown on a listing, append the author's `displayName` when the author isn't this
   device's person and the name isn't empty ("Interested · Wendy"). It's display only and never a filter
   (ADR-0002). One reaction per listing stays.
4. **Settings → People.** "Your name" edits this device's person's `displayName`. Below it, a read-only list of the
   household's people.
5. **The survivor rule and the taste-record fix,** in `Household.ensureDefault`, per the decisions above.
6. **A participant doesn't seed** (Amendment 1, point 4). When the canonical household is `.sharedWithMe`,
   `syncFromRegistry` converges duplicates and does nothing else: no inserts, updates, retirements or
   `registryVersion` write.
7. **The share,** created as Galavant does (jon-platform `persistence-and-sync.md` § Creating and accepting the
   share). Galavant's `SettingsModel.shareTravelPartyButtonTapped` and `SettingsScreen`'s `.sheet(item:)` are the
   model.
   - **Settings → Household,** on iPad and iPhone, shows the sharing state.
   - **On `.private` or `.sharedByMe`,** a **Share household** button calls `syncEngine.share(record:)` on the
     canonical household, with `CKShare.SystemFieldKey.title` set to "Bright Lights", and presents
     `CloudSharingView`.
   - **On `.sharedWithMe`,** it shows "Shared by <owner's name>" and no button, since only the owner can re-save the
     share.
   - **The Mac** shows the state, read-only.
8. **Accepting,** on iOS, in both scene paths: `windowScene(_:userDidAcceptCloudKitShareWith:)` and
   `connectionOptions.cloudKitShareMetadata` in `scene(_:willConnectTo:options:)`, through a `SceneDelegate` as in
   Galavant's `GalavantApp.swift`. Each calls `syncEngine.acceptShare(metadata:)`, then `syncChanges()`, then the
   same `ensureDefault`, `syncFromRegistry` and bind as launch. Add `CKSharingSupported = true` to the iOS
   Info.plist.
9. **Sync health in Settings,** from `CloudSyncKit`'s `SyncHealth` and `SyncDisplayStatus`, with Galavant's
   `Galavant/Settings/SyncHealthModel.swift` as the model. Show the status summary, then the household's sharing
   state, then S1's environment and build line.
   - Use only the health types. Don't adopt `CloudSync`'s enablement gate, since S1's sync policy stays, and don't
     adopt backup (ADR-0009 point 1).
   - Adding the package must keep the patched SQLiteData: the PR confirms that `Package.resolved` has no remote
     `sqlite-data` pin.

### Tests (package)

- **The survivor function:** every pair of sharing states, ties broken by `(createdAt, id)`, and the same answer
  for any input order.
- **The seeded duplicate (point 6):**
  - Seed a private household with the 44 registry sources and a listing with a reaction, plus a `.sharedWithMe`
    household, newer, with its own 44 sources and a listing with a reaction.
  - Run `ensureDefault` and `syncFromRegistry` as the participant.
  - Only the shared household remains. Its 44 sources keep their IDs, and none of the private source IDs survive.
    The private listing and reaction are gone, and the shared ones are untouched.
- **A participant doesn't seed:** with a `.sharedWithMe` canonical household that's missing a source, and a newer
  bundle, nothing is inserted and `registryVersion` doesn't change.
- **The private rule:**
  - Two private households, each with a taste record (one colliding, one not), converge to the older one.
  - Both records survive, re-keyed, and the collision keeps the later `updatedAt`.
  - People are re-keyed, and `Reaction.authorID` and `TasteRecord.authorID` are repointed.
- **Binding:** the derived ID is stable. A second bind doesn't write. An empty name takes the participant's given
  name, and a set name is kept.
- **Attribution:** the display helper shows the name only for another person with a non-empty name.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- Closeout (ADR-0005 D16), with a device gate whose check is § S2 device pass, below.

Definition of done is two real Apple IDs on two devices, through TestFlight on Production (jon-platform
`persistence-and-sync.md`). The Simulator can't show it.

**Not in S2:** per-person reactions or filters (ADR-0002), a Mac accept path (Wendy has no Mac), a second share, and
anything in M3. **Escalates:** sharing and schema, so Jon merges. At review, the architect runs § Adding a synced
table or column, steps 1 to 6, for `people`, and Jon deploys it before the S2 `testflight` run, which its expected
fields enforce.

### S2 device pass (Jon and Wendy)

1. Jon deploys `people` to Production. Then he runs `testflight`, installs the build on the iPad and iPhone, and adds
   Wendy to the internal testing group.
2. On the iPad, Settings → People shows Jon. **Share household** sends Wendy an invitation in Messages.
3. Wendy installs the build from TestFlight on her iPhone, opens it once, then taps the invitation. Settings →
   Household says "Shared by Jon", and People lists Jon and Wendy.
4. Her Sources screen lists 44, and Bowery Ballroom has the same source ID as on Jon's iPad. What's on shows the
   Mac's listings.
5. Wendy marks a listing Interested. Jon's iPad shows "Interested · Wendy". Jon's reaction on another listing shows
   "· Jon" on Wendy's phone.
6. Both phones show sync health as up to date. The next morning, `scripts/check-report --days 1` shows the Mac still
   checking.

## M2 done

Jon and Wendy each run a TestFlight build on Production. The mini checks into the shared household, and a reaction
either of them makes shows the other's devices who made it.
