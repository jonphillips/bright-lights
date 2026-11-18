# Event source survey

*Observed 2026-11-18. Per-source details and pagination evidence are in [survey.json](survey.json); bounded samples are in [fixtures/](fixtures/).*

## Coverage and adapters

The registry has **47 entries: 24 core and 23 other**. The brief says 25 other sources; this survey follows `registry.json` and records the mismatch in `survey.json`.

The 24 core sources need **14 distinct adapters across 15 automated routes**. Shared platform coverage beyond the core is included below.

| Adapter | Sources covered | Count |
|---|---|---:|
| Mercury East WordPress event-discovery plugin | Bowery Ballroom; Mercury Lounge and Irving Plaza (secondary) | 1 |
| AEG/AXS public JSON feed, filtered by venue | Brooklyn Steel; Music Hall of Williamsburg (conditional) | 1 |
| Brooklyn Bowl event-card HTML | Brooklyn Bowl | 1 |
| Schema.org Event JSON-LD | Bell House, New York Comedy Club | 2 |
| UCB event grid with rendered load-more | UCB | 1 |
| Eventbrite public event pages | Union Hall | 1 |
| The Stand schedule HTML | The Stand | 1 |
| Caveat public JSON endpoint | Caveat | 1 |
| Cooper Union event HTML | Cooper Union | 1 |
| WNYC event-card HTML | The Greene Space | 1 |
| Atlantic production calendar HTML | Atlantic Theater | 1 |
| The New Yorker Goings On RSS | The New Yorker | 1 |
| Editorial article extraction | Time Out; Vulture | 2 |

Bowery Ballroom and Brooklyn Steel do not share an adapter: Bowery Ballroom uses the Mercury East WordPress plugin, while Brooklyn Steel uses the AEG/AXS JSON feed. Ticketmaster links and IDs are useful event metadata, not a separate adapter or a confirmed public Ticketmaster API. Caveat also uses a public first-party JSON endpoint, but it is undocumented; that and AEG/AXS are classified as `platform_feed`.

For implementation order by venue coverage, start with Mercury East (Bowery Ballroom plus Mercury Lounge and Irving Plaza), then AEG/AXS (Brooklyn Steel plus conditional Music Hall of Williamsburg), then the shared Event JSON-LD parser (Bell House and New York Comedy Club). Follow with Caveat’s JSON endpoint and the remaining single-source venue adapters.

| Recommended method | Core routes | Count |
|---|---|---:|
| Structured HTML | Bowery Ballroom, Brooklyn Bowl, Bell House, The Stand, New York Comedy Club, Cooper Union, The Greene Space, Atlantic Theater | 8 |
| Public platform/feed endpoint or pages | Brooklyn Steel (AEG/AXS), Caveat (first-party JSON), Union Hall (Eventbrite) | 3 |
| Rendered scrape | UCB (load-more pagination requires JavaScript) | 1 |
| Editorial RSS | The New Yorker Goings On | 1 |
| Editorial extraction | Time Out, Vulture | 2 |
| Manual check | Comedy Cellar (reCAPTCHA), The Town Hall (linked CMS 403), 92NY Talks (invalid robots response), LIVE from NYPL (JS shell), Playbill, Oh My Rockness | 6 |
| Skip | The Public Theater (403), Broadway.com (retail inventory), New York Times (403/paywall and RSS blocked) | 3 |

No single aggregator found covers the core venue set. Oh My Rockness hand-lists indie/rock/alt/pop/art/punk shows, but misses other event types and has no event feed. Playbill is useful for theatre productions, not venue-wide calendars. Broadway.com’s deal page is ticket inventory for the next 48 hours. DoNYC is a broad discovery directory, but this pass did not establish completeness, a public event API, or reuse permission. These sources can help Jon find things to check; they cannot replace official venue schedules.

## Pagination and access

Direct requests checked `robots.txt` before page requests and paused at least one second between requests, observing longer published crawl delays. No login, CAPTCHA, paywall, or bot challenge was bypassed. The Public Theater calendar and NYT Arts section returned 403; NYT RSS access was also denied by the search service’s robots rule. The Strand (secondary) returned 403. Town Hall’s React page linked to a WordPress CMS endpoint that returned 403, and the CMS robots URL returned a login page rather than usable directives. 92NY’s talks page was readable, but its robots URL returned an Imperva challenge document; the route is manual until valid directives are available. Comedy Cellar’s reservation page presented reCAPTCHA, so its route is manual.

The source pages expose different pagination shapes. Bowery Ballroom uses four WordPress listing pages; the furthest page has shows through May 25, 2027. The Stand uses monthly pages; after Dec 2026, Jan and Feb had no show cards, Mar had a Mar 6 show, and Apr–Jun had none. New York Comedy Club’s monthly calendar pages were followed through May 2027; May 31 was the last named date and the page had no next-month link. Brooklyn Bowl returned 12 cards with a disabled “Load More Events” control. Union Hall returned page 1 with eight upcoming cards and no rendered next-page control; a `?page=2` request remained on page 1. UCB’s page showed a JavaScript “Load more (69)” control; a direct pagination request returned 403, so the route is classified as rendered and its horizon beyond the first page remains unmeasured. Other sampled venue pages exposed their observed listings without a next-page or load-more control; each mechanism and sample limit is recorded in `survey.json`.

The Beacon URL in the registry was stale; the current official page is [MSG’s Beacon Theatre page](https://www.msg.com/beacon-theatre), with a public [AXS venue calendar](https://www.axs.com/venues/100784/beacon-theatre-new-york-tickets). MSG robots.txt disallows the Beacon calendar path. Music Hall of Williamsburg remains active during its final weeks, with closure at the end of 2026 reported by [The Bowery Presents](https://www.bowerypresents.com/music-hall-of-williamsburg/) and [Time Out](https://www.timeout.com/newyork/news/the-music-hall-of-williamsburg-will-likely-shut-down-at-the-end-of-2026-121925).

No clear terms prohibition was established for accessible official venue pages, but terms were not fully reviewed for every source. **Robots permission and public visibility do not grant reuse rights.** No affirmative permission or licensed access was found for Broadway.com, Playbill event listings, Oh My Rockness, or NYT content. The New Yorker’s official [RSS directory](https://www.newyorker.com/about/feeds) includes Goings On; it is a selective weekly editorial feed, not an event calendar. Time Out and Vulture expose article/site metadata, but no usable event feed was verified.

## Named-listing horizon

These are the furthest named dates observed after following the listing routes described above, not guaranteed publication limits. Days are approximate from Nov 18, 2026. Manual and editorial rows do not provide an automated venue horizon.

| Core source | Observed horizon |
|---|---|
| Bowery Ballroom | May 25, 2027 (~188 days), page 4 of 4 |
| Brooklyn Steel | Oct 20, 2027 (~336 days), linked AEG/AXS payload |
| Brooklyn Bowl | Nov 25 (~7 days); 12 cards, load-more disabled |
| The Town Hall | Apr 27, 2027 (~160 days) visible; manual because linked endpoint returned 403 |
| Comedy Cellar | Not measured; reCAPTCHA |
| Bell House | Dec 19 (~31 days) in homepage JSON-LD; /shows list had 36 event records through Dec 17 |
| UCB | Not measured beyond first page; Dec 5 (~17 days) visible and 69 more events advertised, but pagination returned 403 to a direct request |
| Union Hall | Nov 25 (~7 days); page 1, no next-page control rendered |
| The Stand | Mar 6, 2027 (~108 days); pages checked through Jun, with no show cards in Apr–Jun |
| New York Comedy Club | May 31, 2027 (~194 days); last named date on May’s calendar page |
| Caveat | Mar 27, 2027 (~129 days), one JSON response with 76 records |
| 92NY Talks | Dec 13 (~25 days) visible; manual because robots response was a challenge |
| LIVE from NYPL | Not measured; direct page is a JS shell |
| Cooper Union | Dec 10 (~22 days); no next-page control in response |
| The Greene Space | Dec 16 (~28 days); no next-page control in response |
| The Public Theater | Not measured; blocked |
| Atlantic Theater | Jul 3, 2027 (~227 days); calendar instances in page response |
| Broadway.com | Next 48 hours; retail inventory, skipped |
| Playbill | Not measured; manual |
| Oh My Rockness | June 2027 (>6 months); manual |
| Time Out | Editorial; no calendar horizon |
| Vulture | Editorial; no calendar horizon |
| New York Times Arts | Not measured; blocked |
| The New Yorker | Weekly editorial picks; no calendar horizon |

Among automated venue routes, Bell House (~31 days) and The Greene Space (~28 days) reach the 4–8 week window. Bowery Ballroom, Brooklyn Steel, The Stand, New York Comedy Club, Caveat, and Atlantic Theater show named listings more than eight weeks ahead. UCB’s first page reaches 17 days and its additional listings need rendered pagination; Brooklyn Bowl and Union Hall show about a week; Cooper Union shows about three weeks. Town Hall also publishes much further ahead, but its route remains manual. Treat each horizon as a timestamped observation, not a publication guarantee.

## Comedy lineups and editorial sources

The Stand’s schedule lists multiple named comics, show time, and room, and its monthly navigation reaches March 2027 listings. UCB publishes dated shows and detailed casts for some events, but the additional 69 cards require JavaScript and the direct pagination probe returned 403. New York Comedy Club’s month pages name shows through May 2027; lineup details allow surprise drop-ins. Caveat event records identify confirmed hosts and guests. Comedy Cellar’s reservation list cannot be automated while it presents a challenge; its past-lineup page is not a reliable advance roster. The pages establish that lineups can change, but not how often. For a booking decision, refresh close to the date and preserve the observation time.

The New Yorker has a usable official Goings On RSS listing for selective culture recommendations. Time Out and Vulture are article sources, not comprehensive event schedules. NYT Arts is blocked from this route and paywall/rights constraints prevent using it without licensed access.

## Surprises

The registry/brief count mismatch is the main input correction. Other content traps: Brooklyn Bowl mixes performances with paid bowling add-ons and multi-night passes; 92NY has a broad calendar that must be filtered to Talks; Greene Space events live under WNYC event URLs; and The Stand has separate rooms/locations. Preserve those distinctions during deduplication. Music Hall of Williamsburg remains active but its current location is slated to close after 2026.
