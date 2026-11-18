# ADR-0004: One extraction engine, deterministic first, with a model as the last resort

*Status: proposed — 2026-11-18. Summary: A single pure engine turns a fetched page (HTML or JSON, plus its URL and
source) into extracted listings. It tries machine-readable data first, then a source-specific adapter, then a model.
The Mac's checks and the in-app browser both use it.*

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
