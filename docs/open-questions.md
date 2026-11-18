# Open questions — architect only

*Candidates, not commitments. The executor never reads this file.*

- **Where ingestion runs, under the no-server rule.** The Mac mini poller has precedent in Vinyl Fever. Decide how it
  writes: directly to CloudKit as Jon, or via an iCloud Drive inbox the app imports from. Read jon-platform's
  persistence-and-sync doc and Vinyl Fever's poller first.
- **Shape of a listing.** It's either a single date or a run. It has an on-sale date, a closing date, and provenance
  from multiple observations. The registry's `event_schema_suggestion` is input, not a decision.
- **Editorial signal.** How does a critic's pick attach to a listing? And which editorial sources are usable at all
  (NYT paywall, usage rights)?
- **Favorites list.** Opportunistic sources need one, so it needs a minimal home.
- **Places.** Restaurants and bars near the apartment: in scope for v1 or not? If yes, lift Galavant's places parts
  rather than copying them.
- **Stays.** Entered by hand at first. Calendar ingestion (Galavant ADR-0034) comes later. But suggesting when to
  go needs home commitments as a constraint, so it may pull calendar reading earlier.
- **Window scoring.** Is it computed in the app from predicted scores per listing, or does a chat model reason over
  the candidates through MCP tools? The survey's listing horizons decide how far ahead it can work at all.
- **House scaffolding** (project.yml, check-drift, githooks, TestFlight config) arrives with the first code slice,
  not before.
- **UCB beyond the first page.** UCB's server response stops at about 17 days, and 69 more events sit behind a WP
  Grid Builder "Load more" control. A direct request to its render endpoint returned 403, and the survey didn't try
  again. Before a UCB adapter is planned, check whether a normal rendered page loads more without a challenge. If
  it needs anything beyond ordinary page JavaScript, keep UCB at first-page depth or make it manual. Don't work
  around the 403.
