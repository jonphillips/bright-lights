# Effort: source survey

**Status:** Dispatched
**Summary:** Survey all registered NYC event sources and document access methods, coverage, horizons, and fixtures.

*Architect brief, 2026-11-18. Research only: no app code, no Xcode project, no scaffolding.*

## Why

Bright Lights depends on reading about 50 NYC event sources (`docs/sources/registry.json`). Before designing
ingestion, we need to know, source by source, how each one can be read and how good the result is. The survey's
real value is **grouping**: sources that share a ticketing platform, CMS or feed format share an adapter. The
architecture follows from how many distinct adapters cover the core sources.

## Scope and depth

- **Full pass, all 24 `core` sources.** Follow the registry's `research_protocol` and fill every
  `required_output_fields` entry, plus the extra fields below.
- **Light pass, the 25 others** (`secondary`, `seasonal`, `conditional`, `opportunistic`). Record operating status,
  canonical URL, ticketing platform if visible, `recommended_method` and `confidence`. Go deeper only if a source
  turns out to be trivially easy (a public feed or JSON-LD) or shares a platform with a core source.
- `music-hall-williamsburg`: confirm operating status first, because the registry flags a lease-closure risk.
- **Editorial sources** (`content_mode: editorial`): check for RSS or Atom feeds and article-level structured data
  only. Don't try to extract event listings from them.

## Extra fields (beyond the registry's required fields)

- `ticketing_platform`: for example Ticketmaster, AXS, DICE, SeeTickets, Etix, Eventbrite, Tixr, OvationTix,
  Showclix, a custom in-house system, or none.
- `site_platform`: the CMS or site builder, if identifiable (WordPress plugin, Squarespace, Webflow, Next.js).
- `needs_rendering`: whether the listings exist only after JavaScript runs.
- `stable_event_id`: whether listings carry a durable ID or URL. Say what it is.
- `lineup_detail`: for comedy and music, whether individual performers are named per show, and how far ahead.
- `sample_fixture`: path to a saved sample, if one was captured (see below).

## Method vocabulary

Use the registry's methods (`official_api`, `rss_ical`, `structured_html`, `permitted_scrape`, `editorial_llm`,
`manual`, `skip`). Add **`platform_feed`** for listings read from a ticketing platform's public pages or widget
endpoints, and **`rendered_scrape`** for pages that need headless rendering (jon-platform's `WebExtractorKit` can do
this).

## Rules

- Personal-use research. Honor robots.txt, use no logins or account creation, don't get around paywalls or bot
  protection, and wait about a second between requests. Stay under roughly 15 requests per source.
- If a site blocks plain fetching (Cloudflare challenge, 403), record that as the finding. Don't work around it.
- Throwaway probe scripts stay out of the repo.
- **Fixtures:** for each core source with a workable method, save one representative raw sample (a JSON-LD block,
  feed, API response or HTML fragment) under `docs/sources/fixtures/<id>.<ext>`, trimmed to under 100 KB. These
  become parser test inputs later.

## Deliverables

1. `docs/sources/survey.json`: one record per source, keyed by registry `id`, with the required fields plus the
   extra fields above. Leave `registry.json` unchanged; it's Jon's input.
2. `docs/sources/SURVEY.md`, at most about 2 pages, answering:
   - How many core sources can be read through structured means (`official_api`, `rss_ical`, `structured_html`,
     `platform_feed`), and how many need scraping, rendering, manual entry or skipping?
   - **Adapter groups:** which sources share a platform, and how many distinct adapters cover all core sources? Give
     the best adapter order by coverage.
   - Which sources block automated access, or have terms that clearly forbid it?
   - Comedy (Cellar, The Stand, NY Comedy Club, UCB, and others): how far ahead are lineups named, and how often do
     they change?
   - Aggregators versus venues: does Oh My Rockness, DoNYC or Playbill cover enough venue listings to replace
     separate venue adapters, and is it allowed?
   - **Horizon:** how far ahead does each core source publish named listings? Which ones are visible 4–8 weeks out?
     The app will suggest which week to visit, and only sources with that much lead time can inform the choice.
   - Editorial: which sources have usable feeds?
   - Surprises, closures, and anything that should change the registry.
3. Advance `docs/NEXT_UP.md` to "nothing dispatched" in the same PR.

## Done when

Every source has a record in `survey.json`, every core source has the full field set, `SURVEY.md` answers each
question above, and fixtures exist for every workable core source.
