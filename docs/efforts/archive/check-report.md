# Effort — The nightly check report

**Status:** Ready · **Summary:** After each run, the checking Mac adds one line per source to a check report in
the app's iCloud Drive container and keeps about 60 days of them. `scripts/check-report` reads it on any of Jon's
Macs, so Jon can ask the architect "how are the checks doing?" and get an answer without opening Console on the
mini. No schema change.

**Implements:** a follow-up to [ADR-0003](../../decisions/0003-the-mac-checks-the-sources.md) point 6 (failures surface).
Jon asked for it on 2026-11-20. **Model:** the iCloud Documents entitlements in Galavant's `project.yml`
(`icloud-services: [CloudKit, CloudDocuments]`, `ubiquity-container-identifiers`), and the coordinated write in
jon-platform `packages/ChatAccessKit/Sources/ChatAccessKit/ChatAccessExportWriter.swift`.

## Why

Each `Source` keeps only its latest check. The detailed logs stay on the mini, where macOS keeps them for a few days,
and nothing off the mini can read them. So there's no history: nothing shows a source that fails every other night, or
one that quietly finds fewer listings after a site redesign. That second case is the important one, because it raises
no error.

The report also answers three open questions that are waiting on a week of the mini's logs: which sources fail and
why, which ones drop model rows, and how many model calls a normal night makes.

## Decisions pinned in this plan

- **The transport is a plain write into the app's ubiquity container, not `ChatAccessKit`.** The kit's export writer
  replaces one whole snapshot per device under a 15-minute throttle (jon-platform ADR-0009 D2). A report is an
  append-only monthly log, so the writer's shape doesn't fit. Bright Lights doesn't link `ChatAccessKit`. If an MCP
  tool ever reads the report (jon-platform ADR-0007), its reader can read these same files.
- **The Mac build gains iCloud Documents.** Add `CloudDocuments` to `com.apple.developer.icloud-services`, and
  `com.apple.developer.ubiquity-container-identifiers: [iCloud.com.jonphillips.BrightLights]`, in
  `BrightLights-macOS.entitlements` only. The iOS build doesn't write reports. No `NSUbiquitousContainers` entry is
  added. The folder isn't meant to show in Files or Finder, and Galavant's container syncs without one.
- **One file per month per checking device:** `CheckReports/<yyyy-MM>.<checkerDeviceID>.jsonl` at the container root.
  Only the lease holder writes, but the lease can move between Macs, and two Macs writing one iCloud file makes
  conflict copies. One writer per file avoids that.
- **The counts come from `Listing.reconcile`.** It returns a `ListingReconcileCounts` value (`new`, `changed`,
  `markedMissing`) instead of an `Int`. `changed` includes a missing listing that comes back. Its `written` total
  equals today's return value, so `rowsWritten` and the Settings screen stay the same.
- **A summary script:** `scripts/check-report`, so any agent gets the same answer.

## The work

1. **Counts.** Change `Listing.reconcile` as pinned above, and update its callers (`SourceChecker`, `BrowserCapture`,
   `SchemaTests`). `BrowserCapture` keeps its own `newListings` behavior.
2. **A richer `SourceCheckReport`.** Add the reconcile counts, `complete` (false when a later page failed or the page
   limit was hit), `unchanged` (the content hash matched, so the model wasn't called), and the check's duration,
   measured with the clock dependency so tests are deterministic. A failed check has zero counts.
3. **The record.** A pure `CheckReportRecord` in `BrightLightsChecking`, encoded as one JSON object per line with
   sorted keys:
   - `version: 1`, `checkedAt` (the pass's `now`, ISO 8601), `trigger` (`scheduled` or `manual` for Check now),
     `build` (the `BuildStamp` display value), `deviceName`;
   - `registryID`, `name`;
   - `outcome` (`succeeded`, `unchanged` or `failed`), `note` (the check note, capped as it is on `Source`);
   - `found`, `new`, `changed`, `markedMissing`, `complete`;
   - `rungs`, `pagesRead`, `modelCalls`, `durationSeconds`;
   - `flagged` (bool), `flagNote`, `startPageURL`: the source's values after the pass, null when unset.
   Browser captures aren't recorded yet.
4. **The writer.** A `CheckReportClient` dependency in `BrightLightsChecking` with one endpoint that appends a pass's
   records. Its live value resolves the container with `FileManager.url(forUbiquityContainerIdentifier:)` off the
   main actor, then does a coordinated read and an atomic replace of this month's file. A coordinated read
   materializes a file the Mac has evicted. After the append it deletes this device's files for months older than
   the two before the current one. That keeps 60 to 90 days. The test value writes to a temporary folder.
5. **The call site.** `CheckerRuntime.check` appends the pass's records after `runPass` returns, for scheduled passes
   and Check now alike, and only when the pass checked at least one source. A failed write logs to the
   `SourceChecks` category and never fails the pass or shows an alert.
6. **`scripts/check-report`** (Python 3, standard library only, as jon-platform's `closeout` is). It reads every
   `CheckReports/*.jsonl` in `~/Library/Mobile Documents/iCloud~com~jonphillips~BrightLights/`, or a folder given
   with `--dir`. If a file isn't downloaded, the script runs `brctl download` on it and retries once. If it's still
   unreadable, it names the file and stops, so it never reports a missing file as a quiet night. Records with an
   unknown `version` fail loudly. Default output, for the last 7 days (`--days N` changes it):
   - one line per night: the build, sources checked, failed and unchanged, model calls, and listings new, changed and
     marked missing;
   - **Failing:** each source that failed at least once, with its failure count, its latest note, and whether it's
     failing now;
   - **Dropping:** each source whose latest successful `found` is under half the median of its earlier successful
     checks in the window, with both numbers;
   - **Flagged:** each flagged source with its note.
   It ends with one verdict line, such as `check-report: 7 nights, 29 sources, 2 failing, 1 dropping, 0 flagged`.
   With `--json` it prints the same summary as JSON.
7. **Fixture test.** Add `scripts/tests/fixtures/check-report/` with a few nights of records, including a failure
   streak, a drop, a flag and an unchanged night. Add `scripts/tests/check-report.sh`, which runs the script on the
   fixture with a fixed `--now` and compares the output to an expected file. `scripts/check-drift.sh` runs it.

## Tests (package)

- `reconcile` counts: an insert, a change, an unchanged row, a missing listing that returns, and a complete check that
  marks one missing, with each count and `written` asserted.
- `CheckReportRecord` encodes the fields above for a succeeded, an unchanged and a failed check, with stable key order.
- The writer appends a second pass to an existing month file without losing the first, starts a new file in a new
  month, and keeps the current month and the two before it while deleting older ones. It never touches another
  device's files.
- `SourceCheckReport` carries `complete == false` for a partial fetch and `unchanged == true` on the hash-match path.

## Not in this effort

- Browser captures in the report.
- An MCP tool or any UI over the report.
- Changing what the checker does when a source fails or drops (ADR-0003 point 6 is unchanged).

## Done when

`scripts/check-drift.sh` passes, including `scripts/tests/check-report.sh`. A signed macOS build's `codesign -d
--entitlements -` shows `CloudDocuments` and the ubiquity container. Closeout (ADR-0005 D16), appending the device
gate below.

## Device gate (Jon)

Install the build on the checking Mac with `scripts/install-bright-lights`, and let one night's checks run. On Jon's
laptop, `scripts/check-report --days 1` shows that night, with the installed build and the checked sources. Then ask
the architect "how are the checks doing?" and get the answer from the report.
