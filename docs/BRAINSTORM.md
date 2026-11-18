# Bright Lights — brainstorm and settled decisions

*Captured 2026-11-18 from Jon's conversation with Claude. This is the seed for `PRODUCT.md`, which gets written
after the source survey. Decisions marked **settled** are Jon's calls; don't re-litigate them.*

## The situation

Jon and Wendy are getting an apartment in NYC, probably in Williamsburg, Brooklyn (not final). They'll spend about
a week a month there, starting around February–March 2027. Jon can dogfood the app before then.

They don't want to plan each week like a military operation. They want what's on at venues they care about, laid
against the time they're actually in town.

## Why it's a separate app (settled)

Galavant is trip-shaped: finite, dated plans with a shortlist and itinerary days. A home base you keep coming back
to has a different rhythm: ambient, driven by venue listings, with booking deadlines. Galavant has no NYC places,
and events on trips are one-offs not worth integrating. So Bright Lights is its own app. It lifts shared parts
from jon-platform and Galavant and leaves Galavant's model alone.

## Core ideas

**Stays have soft edges (settled).** There's no fixed week, and return flights may be open-ended or not bought. A
stay is an arrival plus a tentative departure. That gives two time ranges:

- **While we're here:** from tonight to roughly the departure date. It supports the "is it worth staying an extra
  day?" decision. For example: "stay through Sunday and you catch X."
- **Coming up:** about the next 60 days, laid against a guessed next stay. On-sale dates and closing dates matter
  here, because most booking happens during the three weeks away. The best single alert is something like "this
  closes Jan 12, and you're only in town once more before then."

**Mostly venue-driven (settled).** About 90% of discovery comes from following venues and presenters. Jon tracks
the artists he loves himself. A short **favorites** list still matters for the opportunistic sources, where only a
favorite's name justifies a listing (Radio City, Songkick, Bandsintown in the registry). Sources update on two
schedules:

- **Season sources:** theater runs, talks series, larger venues. They post weeks to months ahead. Check weekly.
- **Nightly sources:** comedy clubs and small music rooms. Lineups go up days ahead and drop-ins happen. Check often,
  but mainly while in town.

**Source types.** The registry (`docs/sources/registry.json`) has venues, presenters, aggregators, festivals, and
**editorial** sources (Vulture, The New Yorker, NYT, Time Out). Editorial is a different kind of input: it's a
critic's signal pointing at a listing, not a listing itself. Treat it as an annotation on listings, never a parallel
event stream.

**Jon's reactions build up taste.** Each listing gets interested, booked, pass, or saw it plus a note. Performers
he's rated well get ranked higher in later listings. This adapts Galavant's taste record (Galavant ADR-0053).

**Getting home matters.** From Williamsburg, rank by travel time from the apartment, not distance. A late show in
the West Village means a late L train or a cab, while BAM, Bell House and Union Hall are close. Each evening listing
could show a small "getting home" estimate.

**iPad plans, iPhone consumes (settled).** The iPad holds the coming-up range, venue management and a stay laid out
as a calendar. The iPhone shows tonight, tomorrow, what's booked, and what's still possible nearby. Galavant
ADR-0038's split between Journey and Today shows how to project both from one read model.

**Wendy is a full peer, with no ceremony (settled).** Jon does about 95% of the curation at first. Wendy gets full
access later: she can view, select and schedule. There's no voting or negotiation structure ("we can just talk").
Everything is shared, with no ownership flags, as in Galavant. The schema must be built for CloudKit sharing from
day one so adding her later is just an invitation.

**The Mac mini checks the sources (settled).** Background refresh on the phone isn't reliable for about 50 sources.
Jon's always-on Mac mini (arriving late November 2026) runs the venue checks. Vinyl Fever's listening poller is the
house precedent. The checks write into the app's data, and the details are open.

**Chat access.** It comes later, through jon-platform's `MCPServerKit` / `ChatAccessKit`, so Claude or ChatGPT can
answer "what's good Thursday night?" from real listings.

## Likely lifts

From jon-platform: `WebExtractorKit` (including headless DOM fetch), `LLMClientKit`, `CloudSyncKit`, `MCPServerKit`,
and `ChatAccessKit`. From Galavant, if places come into scope: `GalavantPlaces` and Capture. Bright Lights is the
second user that jon-platform's `SEAM-LEDGER.md` requires before lifting, so record the rows there when a lift is
planned.

## Sequence

1. **Source survey:** learn how each source can be read (`docs/NEXT_UP.md`). This tells us whether ingestion is
   the easy part or the hard part.
2. Write `PRODUCT.md` and the first decision records (data model, where ingestion runs, sharing).
3. First build: sources plus nightly checks, a "What's on" screen filtered to a stay and the coming-up range,
   reactions to listings, and booking and closing flags. Places, chat tools and calendar ingestion come later.
