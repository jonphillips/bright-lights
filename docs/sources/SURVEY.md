# Event source survey

*Observed 2026-11-18. Per-source details and evidence are in [survey.json](survey.json); bounded samples are in [fixtures/](fixtures/).*

## Coverage and routes

The registry has **47 entries: 24 core and 23 other**. The brief says 25 other sources; this survey follows `registry.json` and records the mismatch in `survey.json`.

The recommended methods cover **15 automated core routes**. The **14 distinct adapters** are:

| Adapter | Sources | Count |
|---|---|---:|
| Mercury East WordPress event-discovery plugin | Bowery Ballroom | 1 |
| AEG/AXS public JSON feed, filtered by venue | Brooklyn Steel | 1 |
| Brooklyn Bowl event-card HTML | Brooklyn Bowl | 1 |
| Schema.org Event JSON-LD | Bell House, New York Comedy Club | 2 |
| UCB event-card HTML | UCB | 1 |
| Eventbrite public event pages | Union Hall | 1 |
| The Stand schedule HTML | The Stand | 1 |
| Caveat first-party JSON API | Caveat | 1 |
| Cooper Union event HTML | Cooper Union | 1 |
| WNYC event-card HTML | The Greene Space | 1 |
| Atlantic production calendar HTML | Atlantic Theater | 1 |
| The New Yorker Goings On RSS | The New Yorker | 1 |
| Editorial article extraction | Time Out; Vulture | 2 |

The count treats the shared JSON-LD parser as one adapter and each editorial source as its own adapter. Bowery Ballroom and Brooklyn Steel are separate platforms: Bowery Ballroom uses the Mercury East WordPress event plugin; Brooklyn Steel uses an AEG/AXS JSON feed shared with other AEG venues. The Music Hall of Williamsburg shares the AEG/AXS venue family while it operates. Ticketmaster links and IDs are useful event metadata, not a separate adapter or a confirmed public Ticketmaster API.

| Recommendation | Count | Sources |
|---|---:|---|
| Structured HTML | 9 | Bowery Ballroom, Brooklyn Bowl, Bell House, UCB, The Stand, New York Comedy Club, Cooper Union, The Greene Space, Atlantic Theater |
| Official JSON API/feed | 2 | Brooklyn Steel (AEG/AXS), Caveat |
| Public platform pages | 1 | Union Hall (Eventbrite) |
| Editorial RSS | 1 | The New Yorker Goings On |
| Editorial extraction | 2 | Time Out, Vulture |
| Manual check | 6 | Comedy Cellar (reCAPTCHA), The Town Hall (linked CMS 403), 92NY Talks (invalid robots response), LIVE from NYPL (JS shell), Playbill, Oh My Rockness |
| Skip | 3 | The Public Theater (403), Broadway.com (retail inventory), New York Times (403/paywall and RSS blocked) |

The lowest-effort implementation order is to start with the event JSON-LD shared by Bell House and NY Comedy Club, then Caveat and AEG/AXS, followed by the remaining venue-specific listing routes. Keep editorial extraction and RSS separate from venue calendars. NYPL stays manual until its public data route is identified.

No single aggregator found covers the core venue set. Oh My Rockness hand-lists indie/rock/alt/pop/art/punk shows and overlaps with venue listings, but misses other event types and has no event feed. Playbill is useful for theatre productions, not venue-wide calendars. Broadway.com’s deal page is ticket inventory for the next 48 hours. DoNYC is a broad discovery directory, but this pass did not establish completeness, a public event API, or reuse permission. These sources can help Jon find things to check; they cannot replace official venue schedules.

## Access, feeds, and terms

Direct requests checked `robots.txt` before page requests and paused about one second between requests. No login, CAPTCHA, paywall, or bot challenge was bypassed. The Public Theater calendar and NYT Arts section returned 403; NYT RSS access was also denied by the search service’s robots rule. The Strand (secondary) returned 403. Town Hall’s React page linked to a WordPress CMS endpoint that returned 403, and the CMS robots URL returned a login page rather than usable directives. 92NY’s talks page was readable, but its robots URL returned an Imperva challenge document; the route is manual until valid directives are available. Comedy Cellar’s reservation page presented reCAPTCHA, so its route is manual.

The Beacon URL in the registry was stale; the current official page is [MSG’s Beacon Theatre page](https://www.msg.com/beacon-theatre), with a public [AXS venue calendar](https://www.axs.com/venues/100784/beacon-theatre-new-york-tickets). MSG robots.txt disallows the Beacon calendar path. Music Hall of Williamsburg remains active during its final weeks, with closure at the end of 2026 reported by [The Bowery Presents](https://www.bowerypresents.com/music-hall-of-williamsburg/) and [Time Out](https://www.timeout.com/newyork/news/the-music-hall-of-williamsburg-will-likely-shut-down-at-the-end-of-2026-121925).

No clear terms prohibition was established for accessible official venue pages, but terms were not fully reviewed for every source. **Robots permission and public visibility do not grant reuse rights.** No affirmative permission or licensed access was found for Broadway.com, Playbill event listings, Oh My Rockness, or NYT content. Keep those routes manual or skipped until permission is clear. The New Yorker’s official [RSS directory](https://www.newyorker.com/about/feeds) includes Goings On; this is a selective weekly editorial feed, not an event calendar. Time Out and Vulture expose article/site metadata, but no usable event feed was verified.

## Comedy lineups

The Stand is the strongest observed lineup source: its [show schedule](https://thestandnyc.com/shows) lists multiple named comics, show time, and room. UCB publishes dated shows, detailed casts for some events, and “TBA” for others; it also warns that lineups can change. New York Comedy Club pages name many comics but allow surprise drop-ins. Caveat event records identify confirmed hosts and guests. Comedy Cellar’s reservation list cannot be automated while it presents a challenge; its past-lineup page is not a reliable advance roster. The pages establish that lineups can change, but not how often. For a booking decision, refresh close to the date and preserve the observation time.

## Named-listing horizon

These are the furthest named dates visible in the sampled listing or data response, not guaranteed publication limits. Days are approximate from Nov 18, 2026. Manual and editorial rows are not automation horizons.

| Core source | Observed horizon |
|---|---|
| Bowery Ballroom | Dec 12 (~24 days) |
| Brooklyn Steel | Oct 20, 2027 (~336 days) in the linked AEG/AXS payload |
| Brooklyn Bowl | Nov 25 (~7 days) |
| The Town Hall | Apr 27, 2027 (~160 days); manual because the linked endpoint returned 403 |
| Comedy Cellar | Not measured; reCAPTCHA |
| Bell House | Dec 19 (~31 days) |
| UCB | Dec 5 (~17 days) |
| Union Hall | Nov 25 (~7 days) |
| The Stand | Nov 21 (~3 days) |
| New York Comedy Club | Nov 20 (~2 days) in sampled featured listings |
| Caveat | Mar 27, 2027 (~129 days) in its JSON response |
| 92NY Talks | Dec 13 (~25 days) visible; manual because robots response was a challenge |
| LIVE from NYPL | Not measured; direct page is a JS shell |
| Cooper Union | Dec 10 (~22 days) |
| The Greene Space | Dec 16 (~28 days) |
| The Public Theater | Not measured; blocked |
| Atlantic Theater | Jul 3, 2027 (~227 days) |
| Broadway.com | Next 48 hours; retail inventory, skipped |
| Playbill | Not measured; manual |
| Oh My Rockness | June 2027 (>6 months); manual |
| Time Out | Editorial; no calendar horizon |
| Vulture | Editorial; no calendar horizon |
| New York Times Arts | Not measured; blocked |
| The New Yorker | Weekly editorial picks; no calendar horizon |

The observed 4–8 week range is not consistent across sources. Caveat and Brooklyn Steel publish substantially further dates; most sampled venue pages show shorter windows. Keep each observation timestamped and do not treat a snapshot as a guaranteed horizon. Source-by-source horizons, stable IDs, platform notes, and confidence are in [survey.json](survey.json).

## Editorial notes and surprises

The New Yorker has a usable official Goings On RSS listing for selective culture recommendations. Time Out and Vulture are article sources, not comprehensive event schedules. NYT Arts is blocked from this route and paywall/rights constraints prevent using it without licensed access.

The registry/brief count mismatch is the main input correction. Other content traps: Brooklyn Bowl mixes performances with paid bowling add-ons and multi-night passes; 92NY has a broad calendar that must be filtered to Talks; Greene Space events live under WNYC event URLs; and The Stand has separate rooms/locations. Preserve those distinctions during deduplication. Music Hall of Williamsburg remains active but its current location is slated to close after 2026.
