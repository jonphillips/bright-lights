# ADR-0005: Rounds — a due-list of sources, captured in the in-app browser while Jon reads

*Status: proposed — 2026-11-18. Summary: Sources the Mac can't read, and automated sources that are failing, appear in
**Rounds**: a checklist ordered by how overdue each one is. Tapping a source opens it in the persistent in-app
browser, which captures the listings on every page Jon views on that source's site through the same extraction
engine. Looking is capturing.*

## Context

The survey left six core sources that need a manual check: Comedy Cellar (reCAPTCHA), Town Hall (403 on its data),
92NY (a bot challenge on its robots file), LIVE from NYPL (a JavaScript-only page), Playbill and Oh My Rockness.
The Public Theater and the NYT are blocked outright. Several of these are Jon's favorites. A person in a real browser
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
