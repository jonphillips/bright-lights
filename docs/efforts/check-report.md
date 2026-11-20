# Effort — The nightly check report

**Status:** Designed · **Summary:** After each run, the checking Mac adds one line per source to a check report in
the app's iCloud Drive folder and keeps about 60 days of them. Jon can then ask the architect "how are the checks
doing?" and get an answer read from the report, without opening Console on the mini. No schema change.

**Implements:** a follow-up to [ADR-0003](../decisions/0003-the-mac-checks-the-sources.md) point 6 (failures surface).
Jon asked for it on 2026-11-20. Queued after [mac-installer.md](mac-installer.md), whose build stamp each record
carries, and after [screening.md](screening.md).

## Why

Each `Source` keeps only its latest check. The detailed logs stay on the mini, where macOS keeps them for a few days,
and nothing off the mini can read them. So there's no history: nothing shows a source that fails every other night, or
one that quietly finds fewer listings after a site redesign. That second case is the important one, because it raises
no error.

## Shape (decided)

- **One record per source checked, per run,** as JSON lines:
  - when, and the build;
  - the source's `registryID`;
  - the outcome and the failure reason (the check note);
  - listings found, new, changed and marked missing;
  - the rung, pages read and model calls;
  - how long it took;
  - the source's flag and note, and a start page set in the app, if any
    ([ADR-0005 Amendment 3](../decisions/0005-rounds-and-browser-capture.md#amendment-3--fixing-a-source-from-the-app-2026-11-20)).
- **Written only by the Mac that holds the checker lease,** after each run. Browser captures aren't in it yet.
- **One file per month,** deleting files older than about 60 days.
- **Read as files** by the architect on whichever Mac syncs the app's iCloud Drive folder. An MCP tool over the same
  files (jon-platform ADR-0007) is a later option, only if Jon wants to ask from ChatGPT.

## To settle before Ready

- **The transport.** Whether this goes through `ChatAccessKit`'s iCloud Drive export (jon-platform ADR-0009), which
  Yes Chef and Galavant use, or a plain write into the app's ubiquity container. It also needs the iCloud Documents
  capability alongside CloudKit: the entitlement and the container's `NSUbiquitousContainers` entry. The plan PR that
  makes this brief Ready pins the choice.
- **Where the counts come from.** The new, changed and missing counts need `Listing.reconcile` to return them, not
  just the rows written. Pin the change to its return value.
- **A summary command.** Whether a small script prints the "how are the checks doing" summary, so any agent gets the
  same answer.
