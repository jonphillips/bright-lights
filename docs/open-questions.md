# Open questions — architect only

*Candidates, not commitments. The executor never reads this file.*

- **Editorial signal.** How does a critic's pick attach to a listing? And which editorial sources are usable at all
  (NYT paywall, usage rights)?
- **The taste work (M2).** ADR-0006 keeps the evidence: a `TasteRecord` for every keep, clear, pass, booking and
  visit, outliving its listing. Still open:
  - How the counts and the model rank New, and whether ranking means sorting, pre-selecting rows, or both.
  - Whether the model may ever clear a listing without Jon's tap. Jon decides, once he's seen its suggestions.
  - Where taste notes live (Galavant ADR-0053 D2 is the model).
  - How long taste records last, and how many go into one prompt: a year of clears is thousands of rows, too many to
    send whole.
  - Whether it runs on the checking Mac each night, so New arrives already sorted.
- **Favorites list.** Opportunistic sources need one, so it needs a minimal home.
- **Places.** Restaurants and bars near the apartment: in scope for v1 or not? If yes, lift Galavant's places parts
  rather than copying them.
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
- **The household survivor once Wendy joins (M2).** M1 converges duplicate households by the lowest `(createdAt, id)`
  (S2 review, PR #6). That's safe while every device is Jon's and writes one private zone. With sharing, a
  participant's device can create its own household and 44 sources before it accepts the share. The survivor must
  then be the shared root, whatever its order: a participant's local household must never win, and must never pull
  the shared rows into a private zone. Decide it in the M2 sharing slice, with a seeded-duplicate test. Galavant has
  the same question about its party (galavant `docs/open-questions.md`).
- **Registry writes across builds (S3 review, PR #8).** Each device runs `syncFromRegistry` against the registry
  bundled in its own build, and the writes sync. A device on an older build therefore writes old field values, and
  since S3 it also retires sources its registry doesn't have. A newer device then writes them back, so the two
  flip-flop until both are updated. Proposal: store the applied `registry_version` on `Household`, and have a
  device write registry fields only when its bundled version is the same or newer. Plan it before the registry
  changes again, and certainly before Wendy's devices join (M2).
- **Per-page hashes for the model ration (S3 review, PR #8).** The Stand reads 9 pages and New York Comedy Club 8,
  all model-rung, under one combined hash. Any change on any page re-extracts every page, so a normal night is
  about 17 model calls. A hash per page, with each unchanged page's listings carried forward, would cut that to
  the pages that changed. Decide it from the S3 live pass's model-call count and a week of the mini's logs.
- **"Missing" on sources read one page deep (S3 review, PR #8).** On a complete check, a future listing that isn't
  returned is marked `missing`. On a source we read only one page of (UCB, and any whose first page is a window),
  a still-on-sale listing pushed off page 1 by newer ones gets marked `missing` too. Watch for it in S4's What's
  on. If it shows, treat a one-page source's check as incomplete for marking, or mark only listings dated inside
  the window the page covers.
- **Model rows dropped for invalid dates (S3 review, PR #8).** The S3 live pass's first model pass dropped 22 rows
  as invalid dates or times (and 13 for excluded hosts), with no per-source breakdown. Date-only starts were zero,
  so it's not the date-only rule. Once the mini runs nightly, read its `SourceChecks` and `ModelExtraction` logs and
  each source's `lastCheckNote` to see which sources produce them. If one source accounts for most of them, look at
  its pages: a prompt or parsing fix there may recover real listings.
- **The automated sources that failed in the S3 device pass.** Jon passed the gate on 2026-11-20, but a few
  automated sources failed on the mini's first nights. Each one's `lastCheckNote` on the Sources screen, and the
  mini's `SourceChecks` log, give the reason. Sort them into: a site change or adapter fix (a dispatch), a challenge
  or 403 (move the source to manual in the registry, since nothing works around it), or a transient error (no
  action). A failing source shows in Rounds after three failures, so S5 covers the gap in the meantime. Once
  `source-fixes` lands, Jon flags the broken ones in the app, and the flags are this list.
