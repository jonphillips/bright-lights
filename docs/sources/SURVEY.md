# Event source survey

*Observed 2026-11-18. Per-source details and evidence are in [survey.json](survey.json); bounded source samples are in [fixtures/](fixtures/).*

## Coverage and adapters

The registry has **47 entries: 24 core and 23 other**. The brief says 25 other sources; this survey follows `registry.json` and records the mismatch in `survey.json`.

For the 24 core sources, the recommended routes are:

| Route | Count | Sources |
|---|---:|---|
| Structured HTML | 13 | Bowery Ballroom, Brooklyn Steel, Brooklyn Bowl, Town Hall, Bell House, UCB, The Stand, NY Comedy Club, Caveat, 92NY, Cooper Union, Greene Space, Atlantic Theater |
| Public platform pages | 1 | Union Hall → Eventbrite |
| Public reservation-page scrape | 1 | Comedy Cellar; stop on any challenge |
| Editorial RSS | 1 | The New Yorker Goings On |
| Editorial extraction | 2 | Time Out, Vulture |
| Manual check | 3 | LIVE from NYPL (page is a JS shell), Playbill, Oh My Rockness |
| Skip | 3 | The Public Theater (403), Broadway.com (retail inventory), New York Times (403/paywall and RSS blocked) |

That is **18 automated source routes** if the two editorial sources each need their own section rules. NYPL stays manual until its public data route is identified. The lowest-effort high-coverage order is:

1. **Bowery Presents** — one venue-aware adapter covers Bowery Ballroom and Brooklyn Steel, and the same page family covers Music Hall of Williamsburg while it operates. It publishes server-readable listings; Ticketmaster links provide useful event identifiers.
2. **Ticketmaster event metadata** — reuse ID and link handling for Bell House and ticket links from other venues, while keeping each venue’s own listing as the descriptive source. No documented public Ticketmaster API was confirmed in this pass.
3. **Comedy schedules** — The Stand, UCB, NY Comedy Club, Caveat, Comedy Cellar, and Union Hall each need a small site-specific route; their calendars and lineup conventions differ. Union Hall links into Eventbrite.
4. **Institution and performing-arts calendars** — Brooklyn Bowl, Town Hall, 92NY, Cooper Union, The Greene Space/WNYC, Atlantic Theater, and NYPL. Most are server-readable; NYPL needs a rendered-page/endpoint check.
5. **Editorial and aggregators** — use The New Yorker’s official Goings On feed and selected Time Out/Vulture articles for recommendations. Keep Playbill and Oh My Rockness as manual discovery sources unless reuse permission is established.

No single aggregator found covers the core venue set. Oh My Rockness says it hand-lists indie/rock/alt/pop/art/punk shows and overlaps with venue listings, but misses other event types and has no event feed. Playbill is useful for theatre productions, not venue-wide calendars. Broadway.com’s deal page is ticket inventory for the next 48 hours. DoNYC is a broad discovery directory, but this pass did not establish completeness, a public event API, or reuse permission. These sources can help Jon find things to check; they cannot replace the official venue schedules.

## Access, feeds, and terms

Direct requests checked `robots.txt` before the page fetch and paused about a second between requests. No login, CAPTCHA, paywall, or bot challenge was bypassed. The Public Theater calendar and NYT Arts section returned 403; NYT RSS access was also denied by the search service’s robots rule. The Strand (secondary) also returned 403. The Beacon URL in the registry is stale; the current official page is [MSG’s Beacon Theatre page](https://www.msg.com/beacon-theatre), with the public [AXS venue calendar](https://www.axs.com/venues/100784/beacon-theatre-new-york-tickets). Music Hall of Williamsburg remains active during its final weeks, with closure at the end of 2026 reported by [The Bowery Presents](https://www.bowerypresents.com/music-hall-of-williamsburg/) and [Time Out](https://www.timeout.com/newyork/news/the-music-hall-of-williamsburg-will-likely-shut-down-at-the-end-of-2026-121925).

No clear terms prohibition was established for the accessible official venue pages, but terms were not fully reviewed for every source. **Robots permission and public visibility do not grant reuse rights.** In particular, no affirmative permission or licensed access was found for Broadway.com, Playbill event listings, Oh My Rockness, or NYT content. Keep those routes manual or skipped until permission is clear. New Yorker’s official [RSS directory](https://www.newyorker.com/about/feeds) includes Goings On; that is a selective weekly editorial feed, not an event calendar. Time Out and Vulture expose article/site metadata, but no usable event feed was verified.

## Comedy lineups

The Stand is the strongest observed lineup source: its [show schedule](https://thestandnyc.com/shows) lists multiple named comics, show time, and room. UCB publishes dated shows, detailed casts for some events, and “TBA” for others; it also warns that lineups can change. New York Comedy Club pages name many comics but explicitly allow surprise drop-ins. Caveat event pages identify confirmed hosts and guests. Comedy Cellar’s public reservation list shows same-day show formats and selected headliners; its [past-lineup page](https://www.comedycellar.com/pastlineups/) helps confirm performers but is not a reliable advance roster. The pages establish that lineups can change, but not how often. For a booking decision, refresh close to the date and preserve the observation time.

## Named-listing horizon

These are the furthest named dates actually observed, not guaranteed publication limits. “Not measured” means the page was not sampled deeply enough to claim a horizon. Days are approximate from Nov 18, 2026.

| Core source | Observed horizon | Core source | Observed horizon |
|---|---|---|---|
| Bowery Ballroom | Dec 12 (~24 days) | Brooklyn Steel | May 22, 2027 (~185 days) |
| Brooklyn Bowl | Not measured | Town Hall | Apr 27, 2027 (~160 days) |
| Comedy Cellar | Same-day listings; horizon not measured | Bell House | Not measured |
| UCB | Dec 27 (~39 days) | Union Hall | Not measured |
| The Stand | Not measured | New York Comedy Club | Not measured |
| Caveat | Dec 29 (~41 days) | 92NY Talks | Dec 13 (~25 days) |
| LIVE from NYPL | Not measured; direct pages are JS shells | Cooper Union | Dec 10 (~22 days) |
| The Greene Space | Not measured | The Public Theater | Blocked; not measured |
| Atlantic Theater | Jul 3, 2027 (~227 days) | Broadway.com | Retail inventory limited to next 48 hours |
| Playbill | Upcoming/announced productions; horizon not measured | Oh My Rockness | June 2027 announcements (>6 months) |
| Time Out | Editorial, no calendar horizon | Vulture | Editorial, no calendar horizon |
| New York Times Arts | Blocked; not measured | The New Yorker | Weekly editorial picks, not a calendar |

The confirmed **4–8 week** listings in this sample are UCB and Caveat. Brooklyn Steel, Town Hall, Atlantic Theater, and Oh My Rockness publish at least some dates further than eight weeks out; the short snapshot does not establish a consistent horizon for most other sources. Source-by-source horizons, stable IDs, platform notes, and confidence are in [survey.json](survey.json).

## Editorial notes and surprises

The New Yorker has a usable official Goings On RSS listing for selective culture recommendations. Time Out and Vulture are article sources, not reliable comprehensive event schedules. NYT Arts is blocked from this route and paywall/rights constraints prevent using it without licensed access.

The registry/brief count mismatch is the main input correction. The venue observations also surfaced distinct content traps: Brooklyn Bowl mixes performances with paid bowling add-ons and multi-night passes; 92NY has a broad calendar that must be filtered to Talks; Greene Space events live under WNYC event URLs; and The Stand has separate rooms/locations. Preserve those distinctions during deduplication. The Music Hall of Williamsburg registry risk is confirmed: it is still publishing shows, but its current location is slated to close after 2026.
