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
- **Per-page hashes for the model ration (S3 review, PR #8).** The Stand reads 9 pages and New York Comedy Club 8,
  all model-rung, under one combined hash. Any change on any page re-extracts every page, so a normal night is
  about 17 model calls. A hash per page, with each unchanged page's listings carried forward, would cut that to
  the pages that changed. Decide it from the S3 live pass's model-call count and a week of the mini's logs. The
  check report now records it: the first reported pass (2026-11-22, 9 sources) made 15 calls, 9 of them The Stand's,
  and 6 of those 9 pages returned nothing usable.
  Some of those may have been replies cut off at the old 5,000-token limit, so recount after `source-health`.
- **Rows from a cut-off model reply (source-health review, PR #41).** A reply that hits the token limit is reported
  and the check counts as incomplete, but its JSON is cut off mid-array, so no row parses and the page yields
  nothing. Salvaging the complete rows before the cut would keep most of the page. Decide it if a check report
  shows "hit the token limit" at the 16,000 cap.
- **"Missing" on sources read one page deep (S3 review, PR #8).** On a complete check, a future listing that isn't
  returned is marked `missing`. On a source we read only one page of (Union Hall, and any whose first page is a
  window), a still-on-sale listing pushed off page 1 by newer ones gets marked `missing` too. Watch for it in S4's
  What's on. If it shows, treat a one-page source's check as incomplete for marking, or mark only listings dated
  inside the window the page covers.
