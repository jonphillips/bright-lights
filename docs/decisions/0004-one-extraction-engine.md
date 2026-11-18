# ADR-0004: One extraction engine, deterministic first, with a model as the last resort

*Status: accepted — 2026-11-18 (PR #3). Summary: A single pure engine turns a fetched page (HTML or JSON, plus its URL and
source) into extracted listings. A source's own adapter goes first, then machine-readable data, then a model. The
Mac's checks and the in-app browser both use it.*

*Amended 2026-11-18 (Amendment 1, below) after the M1 S1 review: the adapter now runs before JSON-LD, the model rung
uses an explicit list of excluded hosts, and keys are deduplicated and namespaced by source.*

## Context

The survey found 14 distinct ways to read the 24 core sources. A few are structured: schema.org Event JSON-LD (Bell
House, NY Comedy Club), the Mercury East WordPress plugin (Bowery Ballroom, Mercury Lounge, Irving Plaza), the AEG/AXS
JSON feed (Brooklyn Steel), and Caveat's JSON. The rest are one-off HTML layouts. Hand-writing a parser for each
breaks whenever a site changes its layout. Yes Chef solved the same problem for recipes: a deterministic ladder, then
a model when the page has no machine-readable contract (its ADR-0047), with one engine behind every way in (its
ADR-0051).

## Decision

1. **One engine, in `BrightLightsLibrary`:** `(document, sourceURL, source) → ExtractionResult`, where the result
   holds extracted listings plus warnings. It's pure and does no I/O. Fetching belongs to the caller: the Mac's
   checker or the browser.
2. **The ladder, first useful rung wins:**
   1. **JSON-LD `Event`** found anywhere in the document.
   2. **A named adapter**, if the source declares one: `mercuryEast`, `aegAXS`, `caveatJSON`. An adapter exists only
      where the survey found shared or stable structure.
   3. **Model extraction:** the visible text of the main content, plus links, goes to `LLMClientKit`'s structured
      output with a fixed listing schema. The prompt states NYC local time and that the source's page date is "today".
3. **Every listing records its rung** (provenance, ADR-0002), so a wrong time can be traced back.
4. **Model calls are rationed:** the caller sends a page to rung 3 only if the page's normalized content hash has
   changed since the last check.
5. **Facts need no review step.** Listings are observations of public pages, not choices, so the engine's output is
   saved directly. Jon's choices live in reactions. A bad extraction is corrected by the next check, or by marking
   the source to be looked at manually.
6. **Fixtures are the contract.** Every adapter and the JSON-LD rung are tested against the survey's samples in
   `docs/sources/fixtures/`. Model extraction is tested with a stub client that returns recorded output, plus an
   opt-in live test that's never part of `check-drift`.

## Consequences

- Adding a new source is usually zero code: JSON-LD or the model rung handles it. An adapter is added only when a
  source's volume or the model rung's error rate justifies one.
- The Mac pays model costs only for one-off HTML sources whose content changed. At about 10 such sources, mostly
  checked weekly, that's a small monthly cost. The checker logs model calls per source so it stays visible.

## Amendment 1 — what the M1 S1 review changed (2026-11-18)

The M1 S1 review (PR #4) found three ways the original ladder could lose or duplicate listings without saying so. The
engine as merged follows this amendment.

1. **A declared adapter runs first** (replaces point 2's order). An adapter exists only because the survey studied
   that source, so it's the most reliable reading. Under the old order, one JSON-LD `Event` on a Mercury East page (a
   featured show) returned 1 listing and the adapter, which would have returned 20, never ran. The ladder is now: the
   source's adapter, if it declares one; then JSON-LD `Event`; then the model.
2. **The model rung drops by an explicit exclusion list, never by allowlist.** A source can name `excludedHosts`
   (registry `excluded_hosts`): a sister venue's site, such as `thestandwest.com` for The Stand. A host matches
   itself or any subdomain. Every drop is counted in a warning. An allowlist of the source's own site silently
   dropped every Stand listing, because The Stand links its events to its ticketing site.
3. **Every rung's output is deduplicated by stable key, and keys are namespaced** `"<source id>:<identity>"`. A bare
   feed ID such as an AXS `eventId` can then never collide with another source's ID in the `Listing` table.
4. **A shared adapter takes its filter from the source** (`adapterVenue`, registry `adapter_venue`), instead of
   hardcoding a venue.
5. **A JSON-LD `endDate` on the same NYC calendar day is still a single performance.** Only a later day makes a run.
6. **Model output without a full date-time is rejected and counted.** A clock-only start is dropped, never treated
   as midnight or today.

