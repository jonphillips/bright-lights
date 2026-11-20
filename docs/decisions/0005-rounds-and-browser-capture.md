# ADR-0005: Rounds — a due-list of sources, captured in the in-app browser while Jon reads

*Status: accepted — 2026-11-18 (PR #3). Summary: Sources the Mac can't read, and automated sources that are failing, appear in
**Rounds**: a checklist ordered by how overdue each one is. Tapping a source opens it in the persistent in-app
browser, which captures the listings on every page Jon views on that source's site through the same extraction
engine. Looking is capturing.*

*Amended 2026-11-20 (Amendment 2, below): Rounds becomes the **Capture** tab. The browser is the tab, and the
list of sources due is a panel beside it, so a round is look, capture, Next. Every way into the browser leads to
that one tab.*

*Amended 2026-11-19 (Amendment 1, below): a source can declare a **capture helper**, a small bundled script that
reveals the rest of the listings or reads data the page already holds. A helper only does what a reader could do
with a few clicks. On a blocked source it runs only in Jon's visible browser session.*

## Context

The survey left six core sources that need a manual check: Comedy Cellar (reCAPTCHA), Town Hall (403 on its data),
92NY (a bot challenge on its robots file), LIVE from NYPL (a JavaScript-only page), Playbill and Oh My Rockness.
The Public Theater and the NYT block automated requests; the Public is a manual source in `registry.json`. Several of these are Jon's favorites. A person in a real browser
passes all of them legitimately. Jon asked for a checklist that reminds him which sources to look at, and for capture
while he's looking.

Both sibling apps already capture from an in-app browser through `WebExtractorKit`:

- **Yes Chef ADR-0009:** the WebKit session persists, so Jon logs in once and browses freely. Capture reads the
  rendered DOM. The app never stores credentials. The browser is a new way to fetch, not a new way to write.
- **Galavant ADR-0025:** a persistent, full-screen browser on `WebPage` with an address bar, rendering at panel width
  so sites serve their desktop layout.

## Decision

1. **Rounds is a list of the sources due for a look.** A source is due when it's manual and its last capture is
   older than its cadence, or when it's automated and failing (ADR-0003, point 6). Order: overdue during a stay first,
   then by how overdue. Each row shows the time of the last capture and the listing count. In M1 the reminder is a
   badge on Rounds; notifications come later, if wanted.
2. **Tapping a source opens the persistent in-app browser** (`WebExtractorKit` `WebPage` engine, Galavant ADR-0025
   style) at the source's calendar URL. The WebKit data store persists, so a passed challenge or a site login holds,
   and the app never sees credentials.
3. **Passive capture.** When a page finishes loading on one of a source's registered hosts, the browser reads
   `currentDOM()` and runs the extraction engine (ADR-0004). A small chip confirms it ("14 listings from Comedy
   Cellar"), and a save that includes the source's main calendar page marks the source as checked. A **Capture**
   button does the same thing on demand, for any page.
4. **Same engine, same upsert.** Browser captures go through ADR-0004 and ADR-0002's change-only upsert, with
   provenance set to `browser`. On a host that isn't registered, capture does nothing unless Jon assigns the page to
   a source.
5. **The Safari share extension is deferred.** The in-app browser covers Rounds. A share extension (Galavant's
   preprocessing-JavaScript pattern, which delivers Safari's DOM) is an M2 option for pages Jon finds while browsing
   elsewhere.

## Consequences

- The model rung (ADR-0004) runs on whichever device captures, so iPad and iPhone need Jon's key through iCloud
  Keychain too, as `LLMClientKit` already provides.
- Rounds keeps the app working when sites change: a broken adapter becomes a checklist item, not a silent gap.
- Passive capture only ever runs on pages Jon chose to open. That's personal browsing, not scraping.

## Amendment 1 — capture helpers (2026-11-19)

### Context

`currentDOM()` already reads a page after its own JavaScript has run, so a JavaScript-only page (LIVE from NYPL)
needs no extra code. Some pages still hold back listings: UCB shows about 17 days and puts 69 more events behind a
WP Grid Builder "Load more" control (`open-questions.md`), and other calendars page by month or lazy-load as you
scroll. Some pages also carry their listings as JSON in the page itself, which is sturdier to read than the layout.
`WebBrowserView` already runs injected JavaScript (its opt-in consent clicker), so running a script per source uses a
mechanism that already exists. The rule from PRODUCT.md and ADR-0003 point 4 still holds: never get around a CAPTCHA,
challenge, login or 403.

### Decision

1. **A source can declare a capture helper** (registry `capture_helper`, `Source.captureHelper`), named like an
   adapter so related sites can share one. Helpers are `.js` files bundled with `BrightLightsLibrary`, one per name.
   A source without a helper captures exactly as before.
2. **A helper does one of two things, or both:**
   - **Reveal:** click a named control on the page ("Load more", "Next month", "Show all dates") or scroll to the
     end, and wait for the page to grow.
   - **Read:** return the listings data the page already holds (inline JSON, a `window` state object), or the
     event-list part of the DOM with navigation and ads removed.
3. **A helper only does what a reader could do on that page with a few clicks.** It may click and scroll on the
   current page, and read the DOM and data the page has already loaded. It may not call `fetch` or XHR itself,
   navigate to another URL, fill in forms, read cookies or storage, or touch a challenge widget. Limits:
   - At most 5 reveal steps per run (a source can lower this, not raise it).
   - At least 1 second between steps, to match ADR-0003's politeness rules.
   - It stops as soon as it sees a challenge (a reCAPTCHA, hCaptcha or Turnstile frame, a Cloudflare challenge
     page), when the page doesn't grow after a step, or when the control is gone.
   - It returns what it has so far and reports why it stopped: `done`, `limit`, `noGrowth`, `noControl` or
     `challenge`.
4. **Where helpers run depends on the source, not the device:**
   - **Manual sources** (blocked to automated requests): only in the in-app browser, on a page Jon opened, while
     it's on screen. Reveal steps run on the source's listing page during passive capture. The chip shows their
     progress, and Jon can stop them. On other pages of the source, only read helpers run.
   - **Automated sources:** also in the Mac's headless render (ADR-0003 point 5). There they apply only to a page
     that loaded with no challenge, and each reveal step counts as a request under ADR-0003's rate rules. A
     `challenge` stop counts as a failed check (ADR-0003 point 6). The headless fetcher keeps its fresh,
     non-persistent data store, so a challenge Jon passed in the browser is never reused unattended.
5. **The helper's output goes into the same extraction engine** (ADR-0004) as just another document: HTML for the
   usual ladder, JSON for a declared adapter. Helpers don't add a rung. The engine stays pure. The stop reason and
   step count go into the check's warnings and log, so a broken helper shows up. The model-call ration hashes the
   helper's output, so a trimmed event list changes the hash only when listings change.
6. **A helper never makes capture worse.** If it throws, times out (10 seconds overall) or returns nothing, capture
   falls back to plain `currentDOM()`.
7. **`WebExtractorKit` gets one generic seam:** an optional after-load script on `RenderedDOMFetcher.Options`, whose
   result is returned with the document. The package stays domain-free, and the browser side needs no package change
   because the host already holds the `WebPage`.
8. **Tests:**
   - Each read helper is tested against its source's saved fixture, loaded in a `WebPage`.
   - Each reveal helper is tested for its stop conditions against fixtures with the control removed or with a
     challenge frame added.
   - Live reveal runs are opt-in tests and never part of `check-drift`, like the model rung.

### Consequences

- **UCB comes first.** Its first dispatch also answers the open question: does the rendered page load more without
  a challenge? If "Load more" returns a 403 or a challenge inside the page, the helper stops at `noGrowth` or
  `challenge`, and UCB stays at first-page depth. Nothing works around it.
- Helpers for manual sources get added from experience: after a few Rounds show where plain capture misses
  listings, not in advance. S5 ships plain capture.
- Helpers are per-site code and will break when sites change, as adapters do. Rule 6 makes a break degrade to plain
  capture, and rule 5 makes it visible.
- Reading a source more deeply also helps the open question on marking one-page sources `missing`.

## Amendment 2 — the Capture tab (2026-11-20)

### Context

S5 built Rounds as decision 1 and 2 describe: a list, where tapping a source pushes the browser over it. On the iPad
during the S5 device pass, Jon found that slow for a round. Each source needs a Back to get to the next one, and the
browser was also pushed from Sources and from a listing's Tickets link. That put the one persistent `WebPage` on
several screens at once on iPhone, which is fragile. Jon asked for a Capture tab that is the browser, with the list
of sources to capture close at hand.

### Decision

1. **Rounds becomes Capture.** It's a tab on iPhone and a sidebar row on iPad and Mac, and it keeps the badge
   (decision 1).
2. **The browser is the tab's main view.** The list of sources from decision 1 is a panel beside it that Jon can
   show or hide: a side column on iPad and Mac, a sheet on iPhone. When no page is open, the browser shows the
   same list on its empty page.
3. **A round is look, capture, Next.** **Next** opens the next source on the list, so Jon never leaves the
   browser during a round.
4. **One browser, one place.** Sources' **Open in browser** and a listing's **Tickets** switch to the Capture tab
   and load the page there. Nothing else shows the browser.
5. Capture itself doesn't change: passive and explicit capture, matching, the ration and the chip stay as
   decisions 3 and 4 and the S5 brief describe them.

### Consequences

- The M1 S5 device gate runs on the Capture tab ([efforts/capture-tab.md](../efforts/capture-tab.md)).
- On iPad, Jon can hide the app's sidebar to give the browser more room, since the panel holds the list.
