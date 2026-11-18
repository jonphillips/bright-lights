# ADR-0003: The app's Mac build on the always-on mini checks the automated sources

*Status: proposed — 2026-11-18. Summary: Bright Lights for Mac, running on Jon's always-on Mac mini, holds the
checking role. It checks each automated source on that source's cadence, runs the extraction engine, and upserts
listings into the shared database. It's Jon's own device running his own app, so it isn't a server.*

## Context

Phone background refresh can't reliably check about 20 sites. Jon agreed the Mac mini (arriving late November 2026)
should do it. Vinyl Fever is the house precedent: since its M13 S3, the Vinyl Fever app itself polls on an
Apple-silicon Mac as a login item. One Mac holds a lease, and the setting moves between Macs. jon-platform's no-server
rule forbids a custom backend; the house reads a household app running on the household's Mac as within the rule.

## Decision

1. **The checking role lives in the Mac build of the app,** not a separate tool. It's a login-item agent, turned on by
   "Check sources on this Mac" in Settings. **One Mac holds the role**, using Vinyl Fever's lease pattern. Any Mac
   (Jon's laptop before the mini arrives) can take it.
2. **It writes like any other device:** SQLiteData rows in the household, synced by CloudKit (ADR-0002). There's no
   inbox file and no import step.
3. **Cadence per source:** `nightly` for comedy rooms and short-horizon venues, `weekly` for season sources. During a
   stay, every source runs nightly. Cadence lives on `Source`, so it can be tuned without a release.
4. **Politeness, as the survey practiced it:** honor robots.txt and crawl delays, wait at least a second between
   requests, follow only the pagination the survey recorded, never log in, and never get around a challenge or 403.
5. **Rendering:** a source the survey marked `rendered_scrape` uses `WebExtractorKit`'s `RenderedDOMFetcher` on the
   Mac. If it hits a challenge, the source is treated as failing (point 6).
6. **Failure falls back to a person.** After three failed checks in a row, or a check that returns no listings where
   it used to return many, the source shows in Rounds as needing a manual look (ADR-0005). The Mac keeps trying on
   its cadence.
7. **Model calls run on the Mac** through `LLMClientKit` with Jon's key from iCloud Keychain, and only when a page's
   content hash has changed since the last check (ADR-0004).

## Consequences

- Nothing happens while no Mac holds the role. The app shows the time of each source's last check, so this is visible.
- The mini's setup (jon-platform `always-on-mac.md`) gains a Bright Lights step: install, sign in, and turn on
  "Check sources on this Mac". That goes in `device-passes.md` when M1 S3 lands.
