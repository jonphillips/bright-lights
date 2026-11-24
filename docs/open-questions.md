# Open questions — architect only

*Candidates, not commitments. The executor never reads this file.*

- **Editorial signal.** How does a critic's pick attach to a listing? And which editorial sources are usable at all
  (NYT paywall, usage rights)?
- **After M3: may the model pre-select or clear?** ADR-0010 D1 keeps every decision a person's tap. Once S3's
  agreement numbers in Settings → Taste cover a few weeks, Jon decides whether likely keeps may start selected, and
  whether likely clears may ever be cleared without Done. Revisit nightly ranking on the Mac (D8) at the same time.
- **Favorites list.** Opportunistic sources need one, so it needs a minimal home.
- **Places, after ADR-0007.** Settled: anything can be a place, one shared standing, venues stay out, a food filter
  by meal. Still open, none of it urgent:
  - **Opening hours and "open tonight."** Galavant's `WeeklyHours` is the model. It's a permanent column, so it
    waits until meals alone fall short.
  - **Meals from a place's website.** ADR-0007 D4 allows filling meals from website hours (Galavant's
    `HoursExtractor`). M4 fills them by hand. Revisit once S3's "no meals set" count shows whether hand entry keeps
    up.
  - **Progress by neighborhood** ("tried 11 of 27 in Williamsburg"). Needs a neighborhood per place, maybe from the
    Apple Maps address.
  - **Getting home** from places as well as listings, and **places in chat access**.
- **Stays.** Entered by hand at first. Calendar ingestion (Galavant ADR-0034) comes later. But suggesting when to
  go needs home commitments as a constraint, so it may pull calendar reading earlier.
- **Window scoring.** Is it computed in the app from predicted scores per listing, or does a chat model reason over
  the candidates through MCP tools? The survey's listing horizons decide how far ahead it can work at all.
- **UCB beyond the first page.** UCB's server response stops at about 17 days, and 69 more events sit behind a WP
  Grid Builder "Load more" control. A direct request to its render endpoint returned 403, and the survey didn't try
  again. Before a UCB adapter is planned, check whether a normal rendered page loads more without a challenge. If
  it needs anything beyond ordinary page JavaScript, keep UCB at first-page depth or make it manual. Don't work
  around the 403. ADR-0005 Amendment 1 (capture helpers) is the way to do this: a UCB reveal helper is its first
  case, and its stop reasons answer the question. Plan it as a dispatch once S3 has merged.
- **Per-page hashes for the model ration (S3 review, PR #8).** The Stand reads 9 pages and New York Comedy Club 8,
  all model-rung, under one combined hash. Any change on any page re-extracts every page, so a normal night is
  about 17 model calls. A hash per page, with each unchanged page's listings carried forward, would cut that to
  the pages that changed. Decide it from the S3 live pass's model-call count and a week of the mini's logs. The
  check report now records it: the first reported pass (2026-11-22, 9 sources) made 15 calls, 9 of them The Stand's,
  and 6 of those 9 pages returned nothing usable.
- **"Missing" on sources read one page deep (S3 review, PR #8).** On a complete check, a future listing that isn't
  returned is marked `missing`. On a source we read only one page of (UCB, and any whose first page is a window),
  a still-on-sale listing pushed off page 1 by newer ones gets marked `missing` too. Watch for it in S4's What's
  on. If it shows, treat a one-page source's check as incomplete for marking, or mark only listings dated inside
  the window the page covers.
- **Model rows dropped for invalid dates (S3 review, PR #8).** The S3 live pass's first model pass dropped 22 rows
  as invalid dates or times (and 13 for excluded hosts), with no per-source breakdown. Date-only starts were zero,
  so it's not the date-only rule. Once the mini runs nightly, read its `SourceChecks` and `ModelExtraction` logs and
  each source's `lastCheckNote` to see which sources produce them. If one source accounts for most of them, look at
  its pages: a prompt or parsing fix there may recover real listings. **Lead (first check report, 2026-11-22):**
  Union Hall dropped 16 model rows for invalid dates or times and kept none, so it shows 0 listings. Start with its
  page.
- **Sources that succeed with zero listings (first check report, 2026-11-22).** The report counts a check as
  healthy when it succeeds, even with 0 listings found. "Dropping" needs earlier successful checks to compare
  against, so it can't catch a source that's been empty from the start. On the first reported night, 4 of 9 checks
  succeeded with 0 listings: Union Hall (above), Gotham Comedy Club and UCB NYC ("Model extraction returned no usable
  listings"), and The Greene Space / WNYC, whose page hash matches a check that found nothing, so the model is never
  called again until the page changes. Two pieces of work:
  - **The report:** add an **Empty** section to `scripts/check-report`, listing each source whose latest successful
    check found 0, and count it in the verdict line.
  - **The sources:** look at each one's page and sort it as the failed-sources entry below does. For UCB, see "UCB
    beyond the first page" above. For The Greene Space, decide whether an unchanged page should be re-extracted when
    the last check found nothing.
- **The automated sources that failed in the S3 device pass.** Jon passed the gate on 2026-11-20, but a few
  automated sources failed on the mini's first nights. Each one's `lastCheckNote` on the Sources screen, and the
  mini's `SourceChecks` log, give the reason. Sort them into: a site change or adapter fix (a dispatch), a challenge
  or 403 (move the source to manual in the registry, since nothing works around it), or a transient error (no
  action). A failing source shows in Rounds after three failures, so S5 covers the gap in the meantime. Once
  `source-fixes` lands, Jon flags the broken ones in the app, and the flags are this list.
