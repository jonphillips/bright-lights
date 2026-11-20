# Effort — Fixing a source from the app

**Status:** Dispatched · **Summary:** In the Capture tab, **Use as start page** saves the current page as a source's
start page, and **Flag** marks a source as not working, with a note. The registry never overwrites either one.
Three synced columns on `Source`.

**Implements:** [ADR-0005 Amendment 3](../../decisions/0005-rounds-and-browser-capture.md#amendment-3--fixing-a-source-from-the-app-2026-11-20).
**Builds on:** the Capture tab (PR #19): `CaptureScreen`, `BrowserModel`, `RoundsList`, `AppRouter`.

## The work

1. **Schema.** Add a migration, "Add source fixes v3", with three nullable columns on `sources`: `startPageURL`
   (TEXT), `flaggedAt` (a date, stored as the other dates are) and `flagNote` (TEXT). Add them to `Source`, and
   update `docs/cloudkit/` with a validated Development proposal, as S3 did. The import waits for Jon.
2. **The page a source opens on.** Add `Source.pageURL: String`, which is `startPageURL ?? listingURL`. Use it in
   place of `listingURL`:
   - `BrowserModel.open(_ source:)`;
   - `SourcePageMatcher`, both the listing-page match and the tie-break between sources;
   - `SourceChecker`'s base URL (`feedURL ?? pageURL`).

   Sources' detail keeps showing the registry's URL, labeled "Registry page".
3. **Registry sync leaves them alone.** `syncFromRegistry`'s change check and update don't read or write
   `flaggedAt` or `flagNote`. For `startPageURL`, there's one rule: when the incoming `listing_url` equals
   `startPageURL`, set `startPageURL` to `nil`.
4. **Use as start page.** The Capture accessory gets a menu ("…") for the current page. It holds **Use as start
   page**, shown when the page's host is one of the current source's registered hosts and the page isn't already its
   `pageURL`.
   - The current source is the Rounds source, or the source the page matched.
   - It saves the page URL with the fragment removed, and confirms in the chip ("Start page set for Town Hall").
5. **Flag and Unflag.** The same menu, and Sources' detail, offer **Flag…**:
   - It's an alert with one text field for the note (optional, up to 200 characters).
   - Saving sets `flaggedAt = now` and `flagNote`.
   - On a flagged source the action reads **Unflag**, which clears both.
6. **Showing it:**
   - `RoundsList` rows and Sources rows show a small `flag.fill` on flagged sources.
   - Sources lists a **Flagged** section first, with each note.
   - Sources' detail gets a **Fixes** section: the flag and its note, the start page with "Set in the app" and
     **Reset** (sets `startPageURL` to `nil`), and the flag actions.

## Tests (package)

- `pageURL` falls back to `listingURL`.
- `SourcePageMatcher` matches against `startPageURL` when it's set, and not against the old `listingURL`.
- `syncFromRegistry`:
  - It keeps `startPageURL`, `flaggedAt` and `flagNote` when the registry changes other fields.
  - It clears `startPageURL` when the registry's `listing_url` equals it.
  - It reports no change when only these fields differ.
- The v3 migration runs on a v2 database, and existing sources have the three fields `nil`.

## Not in this effort

- Editing any other source field in the app.
- Changing checking or due dates for flagged sources.
- Getting flags off the device. The check report carries them (`check-report.md`).

## Done when

`scripts/check-drift.sh` passes; closeout (ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

Import the Development schema first. On iPad, open a source that lands on the wrong page. Browse to its real
calendar, choose **Use as start page**, and capture. The source leaves Due. Open it again from the panel, and it
opens on the new page. Flag a broken source with a note. The flag shows in the panel and at the top of Sources, and
on iPhone after sync. Unflag it, and reset the start page from Sources.
