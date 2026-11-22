# ADR-0009: Production starts empty, and Wendy joins through a share of the household

*Status: accepted — 2026-11-21. Amended 2026-11-21 (Amendment 1). Summary: Bright Lights moves to CloudKit Production with an empty database. The
checking Mac seeds it first, and Jon re-enters his stays and source fixes. iPad and iPhone builds ship through
TestFlight. The Mac's installed build points at Production. Before Wendy joins, registry writes are gated by
version, and a shared household always survives a duplicate. Wendy then accepts a share of the household, and her
reactions carry her name. Implements ADR-0002's "inviting Wendy is a share, not a migration".*

## Context

M1 ran entirely in CloudKit Development, from Xcode builds on Jon's iPad, iPhone and Mac. Wendy can only join
through a TestFlight build, and TestFlight builds use Production. Production's schema is permanent and additive.

Most of what sits in Development rebuilds itself. Sources come from the bundled registry, and the mini's checks
rewrite every listing within a night. What only Jon made is his stays, his reactions and taste records from about
two weeks of use, and a few start pages and flags. Carrying them over would mean adopting `CloudSyncKit`
backup/restore and running Yes Chef's restore-based re-seed (jon-platform `persistence-and-sync.md` § Moving a
populated library to Production). That's hours of upload, and Yes Chef's cutover lost rows along the way.

Two M1 review findings become bugs once a second person's devices write: devices on different builds overwrite
each other's registry fields (S3 review, PR #8), and the oldest household wins a duplicate even if it's private
(S2 review, PR #6).

## Decision

1. **Production starts empty** (Jon, 2026-11-21). Nothing is backed up or restored, and Bright Lights doesn't adopt
   `CloudSyncKit` backup. The Development data is left behind. Development stays the environment for Debug builds.
2. **The cutover runs in this order.** The sync metadatabase is keyed by container ID, not environment, so a store
   that has synced to Development must not start Production. On each device the app is deleted (iOS), or its store
   removed (Mac), before the first Production build runs. The checking Mac goes first. It seeds the household and
   the sources, takes the lease, and runs a check. Then the iPad and iPhone install from TestFlight and download it.
   Jon re-enters stays and source fixes by hand.
3. **Which build talks to which environment.** Debug builds use Development, as now. iOS ships through jon-platform's
   `testflight`, and TestFlight builds use Production. `testflight` only archives for iOS, so the Mac doesn't use it.
   `scripts/install-bright-lights` builds the Release configuration against Production instead. A Release build syncs
   without the Settings opt-in. That opt-in stays for Debug builds, so an Xcode run can't write to Production by
   accident.
4. **Whether a development-signed Mac build can reach Production, with pushes, is measured first.** That means
   `com.apple.developer.icloud-container-environment: Production`, and the macOS `aps-environment` at `production`.
   If it can't, the Mac slice stops and asks, naming what it measured. A Developer ID build or Mac TestFlight are the
   alternatives, and each would need a decision.
5. **Registry writes are gated by version.** `Household` gains `registryVersion`, a nullable synced text column.
   `syncFromRegistry` writes registry fields, and retires sources, only when its bundled `registry_version` is the
   same as or newer than the stored one, compared as dotted numbers (`1.10` is newer than `1.9`). It then stores its own version. An older build still reads and checks, but
   it never writes registry fields back. The column lands before Production's first schema deploy, so Production
   never has a schema without it.
6. **A shared household always survives.** M1 keeps the lowest `(createdAt, id)` household. Once a household is
   shared, the shared one survives whatever its order. A participant's own local household, and the sources it
   seeded, are deleted locally. They're never re-parented into the shared zone, and never shared. Until a device has
   accepted a share, M1's rule still applies.
7. **Wendy joins as a participant.** Jon's device shares the household with `syncEngine.share(record:)`, and Wendy's
   accepts in both scene paths. This is Galavant's code (jon-platform `persistence-and-sync.md` § Creating and
   accepting the share). Only the owner sees the share action. Each person is a synced `Person` row keyed to their
   iCloud identity, following Galavant ADR-0051. `Reaction.authorID` and `TasteRecord.authorID` are set to this
   device's person. One reaction per listing stays (ADR-0002), and the author is attribution only. Settings shows
   sync health through `CloudSyncKit`'s `SyncHealth`, so a device that's quietly in a private pool shows it.
8. **Only Jon's Mac checks.** Wendy's devices are iOS, and the checker role is Mac-only (ADR-0003), so nothing
   changes there.

## Considered and rejected

- **Carry Development into Production by backup and restore.** It keeps about two weeks of reactions and taste
  records, at the cost of a new dependency and a cutover that went wrong in Yes Chef. Jon chose to start fresh.
- **Ship the Mac build through TestFlight now.** `testflight` is iOS-only, and the mini runs an installed build
  anyway (mac-installer). Revisit only if point 4's measurement fails.
- **Two reaction columns, or one reaction per person.** Rejected in ADR-0002 and BRAINSTORM ("we can just talk").

## Consequences

- Production's schema is everything M1 built plus `registryVersion`. `Person` follows in the sharing slice, as an
  additive deploy.
- The taste record restarts in Production, so the M3 taste work learns from what's screened after the cutover.
- Every later synced column is a Development import followed by a Production deploy, through `testflight`'s schema
  gate.

## Amendment 1 — the Mac measurement, and one store per environment (2026-11-21)

### Context

Point 4 asked whether a development-signed Mac build can reach Production with pushes. The architect read the
answer from the Mac build installed on 2026-11-20 before expanding S1. Its embedded profile, "Mac Team Provisioning
Profile: com.jonphillips.BrightLights", lists `com.apple.developer.icloud-container-environment` as `Production`
and `Development`, and `com.apple.developer.aps-environment` as `development` only.

The S1 brief also found that Debug and Release would share one store. SQLiteData names the sync metadatabase after
the database file, so a single file is the cause of the problem point 2 deletes apps to avoid.

### Decision

1. **The Mac reaches Production with a development push environment.** The checking Mac's Release build signs
   with `icloud-container-environment: Production` and keeps `aps-environment: development`, because its profile
   allows nothing else. The cutover measures whether Production's pushes reach it. Either way, every checker pass
   starts by fetching and sending changes, so a missed push delays what the Mac sees until its next pass. It never
   stops a check. Point 4's "stops and asks" is replaced by this. A Developer ID build is needed only if the fetch
   at pass time proves not to be enough.
2. **Release means Production, on every platform.** Release builds carry
   `icloud-container-environment: Production`, and Debug builds carry none, so they use Development. A local
   Release build can't write to Development by accident.
3. **Debug and Release open different database files.** So their metadatabases are separate too. A Debug run on a
   device that holds the Production store can't touch it, and Xcode builds keep their Development data. Point 2's
   order stands, with the Mac first, but deleting the app or its store is no longer needed.
4. **A participant's devices never seed the registry.** When this device's household is shared with it (it lives
   in another person's zone), `syncFromRegistry` inserts, updates and retires nothing. It still converges
   duplicates. The owner's devices keep the registry, as the checker role already does (point 8).
