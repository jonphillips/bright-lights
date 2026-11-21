# M2 — Wendy joins

*Architect, 2026-11-21. Arc: from Jon alone in CloudKit Development to Jon and Wendy sharing one household in
Production. Jon installs from TestFlight, the mini checks into Production, and Wendy reacts from her own iPhone.
Decisions: [ADR-0007](../decisions/0007-production-and-wendy.md). Taste ranking leads M3. Its open questions are in
`open-questions.md`, and the taste record restarts at the cutover.*

## Slice ledger

- [ ] **S1** — Production and TestFlight
- [ ] **S2** — Inviting Wendy

Each slice is one dispatch. The architect expands a slice into a full brief, here, before dispatching it. S1 follows
[check-report](../efforts/check-report.md), whose report is how the first Production nights get read.

## S1 — Production and TestFlight

**Goal:** Jon's three devices run Production builds over an empty Production database, seeded by the mini. No
Development data comes along (ADR-0007 points 1 and 2).

**Scope, to expand before dispatch:**

- **Measure the Mac first** (ADR-0007 point 4). A development-signed Release build with the Production container
  environment and production pushes runs on the mini, and receives a push. If it doesn't, the slice stops and asks.
- **`Household.registryVersion` and the version gate** (point 5), with tests for an older bundle that leaves fields
  alone and a newer one that writes them. The column joins the CloudKit Development schema before Production's
  first deploy.
- **The environment split** (point 3). Release builds sync without the opt-in, and Debug builds keep it.
  `install-bright-lights` builds Release against Production.
- **TestFlight setup.** A `testflight.conf`, and `testflight --dry-run` passing preflight and schema parity.
- **The cutover runbook.** Point 2's order, written as `device-passes.md` setup steps for Jon. The deploy to
  Production and the first upload are Jon's.

**Architect, before dispatch:** read every synced column once more, since Production is permanent (jon-platform
`persistence-and-sync.md` § Schema hygiene). **Escalates:** schema and sync, so Jon merges.

## S2 — Inviting Wendy

**Goal:** Wendy accepts the household on her iPhone through TestFlight, sees what's on, and her reactions show her
name on Jon's devices (ADR-0007 points 6 and 7).

**Scope, to expand before dispatch:**

- **The share,** created and accepted as Galavant does: owner only, both scene paths, and `CKSharingSupported`.
- **The shared-household survivor** (point 6), with a seeded-duplicate test: a participant device seeds its own
  household and 44 sources, then accepts, and only the shared root remains, with nothing re-parented.
- **`Person`,** keyed to the iCloud identity as in Galavant ADR-0051, with `authorID` set on new reactions and taste
  records. Display only, never a filter.
- **Sync health in Settings** from `CloudSyncKit`'s `SyncHealth`.

**Done** means two real Apple IDs on two devices, through TestFlight on Production (jon-platform
`persistence-and-sync.md`). **Escalates:** sharing and schema, so Jon merges.

## M2 done

Jon and Wendy each run a TestFlight build on Production. The mini checks into the shared household, and a reaction
either of them makes shows the other's devices who made it.
