# Effort — Source health

**Status:** Ready · **Summary:** Four automated sources succeed every night with zero listings. Each has a
different cause, found in the first three nights of check reports. This effort fixes the extraction bugs behind
them: the model isn't told today's date, its output is cut off at 5,000 tokens, and an empty result is cached as
"unchanged". It adds an Eventbrite organizer adapter for Union Hall, points The Greene Space at its new events page,
makes UCB manual because it shows a bot challenge, and adds an **Empty** section to `scripts/check-report`. No
schema change.

**Implements:** [ADR-0004](../decisions/0004-one-extraction-engine.md) (adapters first, the model last) and
[ADR-0003](../decisions/0003-the-mac-checks-the-sources.md) point 6 (failures surface). It answers the
`open-questions.md` entries "Sources that succeed with zero listings", "Model rows dropped for invalid dates" and
"UCB beyond the first page". Branch `effort/source-health`.

## Why

The check reports from 2026-11-22 to 2026-11-24 show 9 nightly sources checked three times each, with nothing
failing. Four of them found 0 listings every night, and the report counts that as healthy. The architect fetched
each page once on 2026-11-24:

| Source | What the page holds | Why it finds nothing |
| --- | --- | --- |
| Gotham Comedy Club | 84 shows, each with a full date and time | 84 rows of 10 fields don't fit in `maxTokens: 5000`. The JSON is cut off, `modelRows` can't parse it, and the check records "no usable listings". |
| Union Hall | `/calendar` shows "Nov 24" and a title, with no year and no time. Every ticket link goes to Eventbrite. | The model returns rows without a clock time, which are dropped as invalid (16 a night). Eventbrite's organizer page, `https://www.eventbrite.com/o/union-hall-17899496497`, embeds an `upcomingEvents` JSON array with `start_date`, `start_time` and `timezone` for each event. |
| The Greene Space | `wnyc.org/tgs/` is now a landing page with no events. The events moved to `https://wnyc.org/events` ("December 1 - 12:00 PM", with no year). | The page hash matches the first empty check, so the model is never called again. |
| UCB | A Cloudflare "Just a moment..." challenge page, with a 403. | The rendered fetch reads the challenge and the model finds nothing in it. |

There's a fifth problem that affects every model source. The system prompt says "The source page date is today",
but the request never says what today is. Pages that omit the year, like Union Hall's and WNYC's, can't be dated
reliably.

## Decisions pinned in this plan

- **The model is told the date.** `ExtractionEngine.extract` takes the pass's `now`. The prompt's first line becomes
  `Today is <yyyy-MM-dd> in New York.`, formatted in America/New_York. The system prompt's "The source page date is
  today" sentence is replaced with: "When the page omits a year, use the year that puts the date closest to today."
- **The token cap rises to 16,000,** and a cut-off reply is reported rather than swallowed. A response whose
  `stopReason` is `max_tokens` (Anthropic) or `max_output_tokens` (OpenAI) adds the warning "Model output hit the
  token limit; some listings may be missing." Any rows that parse are kept. The check counts as incomplete
  (`complete == false`), so nothing is marked missing from it. Splitting a page across calls is not in this effort.
- **The content hash is stored only when it's worth trusting.** `recordSuccess` stores `lastContentHash` only when
  the model found at least one listing and no reply was cut off. Otherwise it stores nil, so an unchanged page is
  extracted again the next night. That answers the open question about The Greene Space: an empty result is never
  cached.
- **The hash carries an extraction version.** `ExtractionEngine.modelExtractionVersion` is a constant string that
  `combinedHash` mixes in. This effort sets it to `"2"`. Every stored hash from before then stops matching, so each
  model source is extracted once with the new prompt. A comment on the constant says to bump it whenever the
  prompt, schema or row parsing changes.
- **A new adapter, `eventbriteOrganizer`.** It reads the organizer page's embedded `upcomingEvents` array. Each
  element gives:
  - the title (`name`, with runs of whitespace collapsed);
  - the start, from `start_date` and `start_time` read as wall-clock time in the element's `timezone`. An element
    missing either is skipped;
  - the identity and ticket URL, both from `url`;
  - an empty performer list and a nil room. The venue is in the source.

  It finds the array by locating `"upcomingEvents":` and decoding the JSON array that follows. The adapter's raw
  value is `eventbriteOrganizer`, matching the existing camel-case names.
- **A challenge page fails the check.** After each fetch, rendered or plain, a page whose HTML contains
  `<title>Just a moment...</title>`, `challenge-platform` or `_cf_chl_opt` throws a new
  `SourceCheckError.challenge`. Its note is "The site showed a bot challenge. Make this source manual; nothing works
  around it." That's a failure, so it shows under **Failing** in the report, and in Rounds after three failures.
  Nothing tries to get past the challenge.
- **Registry 1.4** (`registry_version` "1.4", `as_of` "2026-11-24"), in `docs/sources/registry.json` and the bundled
  copy, which must stay byte-identical:
  - `union-hall`: `listing_url` is the Eventbrite organizer page above, and `adapter` is `eventbriteOrganizer`.
    `method`, `registered_hosts` and `cadence` stay the same. Capture on `unionhallny.com` still works.
  - `greene-space`: `listing_url` is `https://wnyc.org/events`. WNYC's robots.txt allows `/events`.
  - `ucb`: `mode` and `method` become `manual`, and `cadence` becomes `weekly`, as the registry's `about` sets for
    manual sources. Its other fields stay.
  Registry reconciliation already carries `mode`, `adapter` and `listing_url` to the `Source` rows, and it clears an
  in-app start page that matches the new listing URL.

## The work

1. **Today's date.** Add the `now` parameter to the extraction entry point and its callers (`SourceChecker` and
   `BrowserCapture`), and change the prompt as pinned.
2. **The token limit.** Raise `maxTokens`, detect a cut-off reply, and thread the warning and `complete == false`
   through `extractDocuments` to the report.
3. **Hash storage and the version.** Apply both hash decisions in `SourceChecker`.
4. **The adapter.** Add `eventbriteOrganizer` to `SourceDescriptor.Adapter` and to `adapterListings`.
5. **Challenge detection.** Add it in `SourceChecker`'s page fetch, and add the error case.
6. **The registry.** Make the 1.4 changes in both copies.
7. **`scripts/check-report`.** Add an **Empty** section between Dropping and Flagged. It lists each source whose
   latest record in the window is `succeeded` or `unchanged` with `found == 0`, with that record's note:
   `  Union Hall · latest note: Model extraction returned no usable listings.` (or "no note"). The verdict line
   gains a count after dropping: `check-report: 3 nights, 3 sources, 1 failing, 1 dropping, 1 empty, 1 flagged`.
   `--json` gains `empty` and `emptyCount`. Add an empty source to the fixture and update `expected.txt`.

## Tests

Package tests. Every fixture uses invented venues, performers and titles, because the repo is public.

- The model request's prompt starts with today's New York date for a fixed `now`, and the system prompt has the
  closest-year rule.
- A model reply with `stopReason` `max_tokens` keeps its parsed rows, adds the warning, reports `complete == false`,
  marks nothing missing, and stores no hash. The same goes for `max_output_tokens`.
- A model check that finds 0 listings stores no hash, and the next check of the same page calls the model again.
- A check that finds listings stores the hash, and the next check of the same page is `unchanged`.
- A stored hash computed without the version salt doesn't match, so the page is extracted again.
- `eventbriteOrganizer`, on a small invented organizer page with three events: two listings come back with the
  right New York start instants, titles and URLs, and the event missing `start_time` is skipped. A page with no
  `upcomingEvents` returns no listings.
- A rendered page and a plain page holding the challenge markers each fail the check with the challenge note.
- Seeding from the 1.4 registry gives UCB a manual mode and Union Hall the adapter.

Script test: `scripts/tests/check-report.sh` passes with the new fixture.

## Not in this effort

- Splitting large pages across several model calls, or per-page hashes (`open-questions.md`).
- Getting past the first page at any source, UCB included.
- Treating a one-page source's check as incomplete for marking missing (`open-questions.md`).
- The weekly sources. They haven't come due since reporting started on 2026-11-22, so the device gate covers them.

## Done when

`scripts/check-drift.sh` passes, including the registry check and `scripts/tests/check-report.sh`, and CI is green.
Closeout (ADR-0005 D16), appending the device gate below.

**Merges:** no schema, sync or sharing change. The registry is seed data, so the architect merges on approve.

## Device gate (Jon)

Install the build on the checking Mac with `scripts/install-bright-lights`, and let one night's checks run. Then
run `scripts/check-report --days 1` on the laptop and ask the architect how the checks are doing. Gotham Comedy
Club, Union Hall and The Greene Space should show listings, UCB should be gone from the checked sources, and Empty
should list none of the three. A week later, run `scripts/check-report --days 8` so the weekly sources are covered
too.
