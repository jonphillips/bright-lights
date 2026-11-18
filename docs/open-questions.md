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
- **Stays.** Entered by hand at first. Calendar ingestion (Galavant ADR-0034) comes later.
- **House scaffolding** (project.yml, check-drift, githooks, TestFlight config) arrives with the first code slice,
  not before.
