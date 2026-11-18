# Open questions — architect only

*Candidates, not commitments. The executor never reads this file.*

- **Editorial signal.** How does a critic's pick attach to a listing? And which editorial sources are usable at all
  (NYT paywall, usage rights)?
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
  around the 403.
- **The registry needs corrections from the survey:** Beacon's URL is stale (and MSG's robots file blocks its
  calendar), Music Hall of Williamsburg closes at the end of 2026, and the 47-versus-49 count. Decide whether
  `registry.json` stays Jon's frozen input, with `survey.json` authoritative, or gets corrected. M1 S2 seeds from
  `survey.json` either way.
- **When TestFlight and the Production schema arrive.** Planned for M2 with Wendy. Pull them earlier if Jon wants the
  app on his own devices from TestFlight rather than Xcode during M1.
