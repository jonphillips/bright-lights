# Bright Lights — Product Brief

*Last updated: 2026-11-18. Grew out of [BRAINSTORM.md](BRAINSTORM.md); the facts about sources come from
[sources/SURVEY.md](sources/SURVEY.md).*

## What it is

A private app for **Jon and Wendy** (two users, never on the App Store) for their monthly stays at an NYC apartment,
probably in Williamsburg. It follows the venues and presenters they care about (indie rock and pop, stand-up, live
podcasts, talks, Off-Broadway) and answers three questions:

1. **While we're here:** what's on from tonight until we leave, and is it worth staying an extra day?
2. **Coming up:** what goes on sale, closes, or happens before or during the next stay?
3. **When should we come next?** Which week holds the most things we'd love that are only on then? (M2)

It doesn't plan stays like an itinerary. It gives a short menu with deadlines, and Jon and Wendy decide.

## The core loop: sources → listings → reactions

1. **Sources.** About 25 followed venues, presenters and editorial feeds, each with a way to read it: automated or
   manual ([ADR-0004](decisions/0004-one-extraction-engine.md)).
2. **Listings.** The always-on Mac checks the automated sources ([ADR-0003](decisions/0003-the-mac-checks-the-sources.md)).
   Jon covers the rest through **Rounds**, a checklist of sources due for a look that opens each one in the in-app
   browser, which captures listings while he reads ([ADR-0005](decisions/0005-rounds-and-browser-capture.md)).
3. **Reactions.** Interested, booked, pass, or went plus a note. Reactions are shared state, and the start of the
   taste record.

**Stays** frame what's on. A stay is an arrival plus a departure that may be tentative or open, because return flights
may be open-ended.

## Who does what

Jon curates (about 95% at first). Wendy is a full peer as soon as she's invited: she sees everything and can react,
book and edit stays. There's no voting, ownership or private items. The schema is built for sharing from day one
([ADR-0002](decisions/0002-shared-data-model.md)).

## Platforms

iPad first for planning: Coming up, Rounds and the browser. iPhone for use on the go: tonight, tomorrow, and what's
booked. A Mac build exists mainly so the always-on Mac mini can check sources. Decided in
[ADR-0001](decisions/0001-house-stack-and-targets.md).

## In scope for M1

Sources seeded from the survey; automated checks on the Mac; the extraction engine; stays; the "What's on" views
(While we're here, Coming up); reactions; Rounds and capture in the in-app browser. See
[milestones/M1-whats-on.md](milestones/M1-whats-on.md).

## Later (M2 and beyond)

- **Suggesting which week to come next**, weighted toward what's only on during that week (see BRAINSTORM).
- **Taste:** performers Jon has rated well rank higher; adapts Galavant ADR-0053.
- **Editorial picks** attached to listings (The New Yorker Goings On RSS first).
- **Getting home:** travel-time estimates from the apartment.
- **Chat access** through jon-platform's `MCPServerKit` / `ChatAccessKit`.
- **Calendar constraints** from the shared Apple Calendar (Galavant ADR-0034).
- **Inviting Wendy**, TestFlight, and the CloudKit Production schema.
- **Safari share extension** as a second way to capture.
- **Places** (restaurants and bars near the apartment), only if wanted.

## Out of scope

- No server: the Mac mini is Jon's own device running the app (ADR-0003).
- No working around CAPTCHAs, paywalls, logins or 403s. A blocked source becomes a manual check.
- No ticket buying or inventory. Listings link out.
- No social layer, no App Store, no Android or web.
- No catalog of the city. Only followed sources are read.
