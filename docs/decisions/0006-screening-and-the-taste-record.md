# ADR-0006: Screening — new listings are kept or cleared, and a taste record outlives them

*Status: proposed — 2026-11-20. Summary: Every new listing waits in **New** until Jon screens it. A screen shows
a source's new listings with none selected. Jon taps the ones worth keeping, and **Done** clears the rest, so they
never come back. What's on shows what was kept. Each decision is also written to a **taste record** that outlives
its listing, so the later taste work has every keep, clear, pass and booking to learn from. Amends ADR-0002's
deletion rule (Amendment 1 there).*

## Context

During the S5 device pass Jon found that capture brings in far more than he wants. A manual capture of a big
venue lands dozens of listings in What's on, and the automated sources bring about 1,500. A model that learns
Jon's taste could filter them eventually, but that takes data and time. Jon asked for three things now:

- After a manual capture, show what came in right there, with nothing selected. He taps the interesting ones. One
  he didn't tap must never be shown again, even when the source is captured next week.
- A way to clear what the Mac brings in, so he never sees those listings again.
- A clear answer on when data is deleted, and whether the learning has what it needs.

Two facts shape the answer:

- **Not showing something again requires remembering it.** Every capture extracts the same listings again. If a
  cleared listing were deleted, the next capture would bring it back as new. So clearing is a stored decision on
  the listing, and it lasts as long as the listing does.
- **Deleting listings deletes the evidence.** ADR-0002 deletes past listings without a reaction after 30 days and
  keeps reacted ones forever. Once screening exists, most decisions are clears. Under that rule they'd be deleted,
  or, if a clear were treated as a reaction, every cleared listing would be kept forever. Neither is right. The
  decisions should outlive the listings, and the listings shouldn't stay around just to carry them.

Jon settled these on 2026-11-20:
- A tap in a screen means **keep**: worth a closer look later. It doesn't mean Interested, because he can't
  research 50 listings mid-round.
- What's on shows what was kept by default.

## Decision

1. **Every listing starts unscreened.** A listing with no reaction is unscreened, however it was captured. The Mac
   and the browser write listings exactly as before.
2. **Two new reaction kinds: `kept` and `cleared`.** A reaction is still one per listing (ADR-0002), now one of
   `kept`, `interested`, `booked`, `went`, `pass` or `cleared`. **Picked** means kept, interested, booked or went.
   **Hidden** means pass or cleared. Clear and pass are different decisions. A clear is a quick screen-out, a weak
   signal. A pass is a considered no, a strong one.
3. **A screen** is a list of one source's unscreened future listings, sorted by date, with none selected. Tapping a
   row toggles it. **Done** writes `kept` for the selected rows and `cleared` for the other rows on the screen, in
   one transaction. A listing only gets cleared if it was a row on the screen when Jon pressed Done, so a listing
   that syncs in mid-screen stays unscreened. Leaving without Done writes nothing.
4. **Screening happens in two places:**
   - **After a capture in the Capture tab,** where Jon has just been looking at the source. The chip offers the
     review, and in a round **Next** goes through it.
   - **In New,** a new screen with a badge that counts every unscreened future listing, grouped by source. This is
     where the Mac's listings get screened, along with any capture that wasn't reviewed.
5. **What's on shows picked listings by default.** An **Everything** filter adds unscreened ones. Hidden listings
   never show in What's on. A cleared listing can be restored to kept from its source's cleared list.
6. **Once screened, a listing never goes back to unscreened.** Removing a reaction in a listing's detail returns it
   to `kept`.
7. **The taste record.** A new synced table, `TasteRecord`, a child of `Household`, holds one row per decided
   listing:
   - What the listing was, as text: the source's registry ID and name, the stable key, title, performers, room, and
     start and close times.
   - What we decided: the reaction kind, its note, its author, and when it was first and last decided.
   - It's written in the same transaction as every reaction write, and updated when the reaction changes.
   - Its ID is derived from the household, the source's registry ID and the stable key. Writes from two devices, and
     the backfill on every device, then land on the same row.
   - It keeps the listing's details as text and has no reference to the `Listing` row, so it survives when the
     listing is deleted (Galavant ADR-0053 D2's rule, that a note outlives what it's about).
   - It isn't deleted in M1. The taste work decides how long it lasts.
8. **Deletion (ADR-0002 Amendment 1).** Every listing is deleted 30 days after it ends, reacted or not, and its
   reaction goes with it. The taste record keeps what was decided. A cleared listing that hasn't happened yet is
   never deleted early, because it's what keeps the next capture from showing it again.

## What the taste work reads (M2, not decided here)

This ADR only makes sure the evidence is kept. Learning from it is M2's taste work. Its direction is the house
pattern from Vinyl Fever and Galavant ADR-0053: **keep the evidence, let the model interpret it fresh, store no
model-written profile, and let people decide.** Bright Lights differs from Galavant in volume. Screening produces
hundreds of decisions a month, so counts mean something here, as they do in Vinyl Fever. Two layers, both reading
`TasteRecord`:

- **Counts, with no model:** the keep rate by source, by performer, and by room. These alone can sort New so the
  likely keeps come first.
- **The model:** reads Jon's taste notes (his own words, Galavant-style) along with examples of what he kept,
  cleared, booked and went to. It ranks New with a reason for each listing ("you kept 6 of 7 indie shows at Bell
  House"). It may pre-select rows. Whether it may ever clear anything without Jon's tap is his call in M2.

## Considered and rejected

- **A tap means Interested.** Rejected by Jon: a keep has to be cheap during a long screen.
- **Delete what isn't selected.** The next capture would bring it back (Context).
- **Clearing as a column on `Listing`.** The Mac rewrites the whole listing row on every change (ADR-0002's
  upsert), and household decisions belong with reactions.
- **A per-source "screened up to" timestamp instead of a row per listing.** It needs no new rows, but a listing
  from the Mac that syncs late, with an earlier first-seen time, would be cleared without Jon ever seeing it.
- **Keep reacted listings forever, as before.** That means keeping every cleared one, and the history would still
  be lost for anything deleted unscreened. The taste record is smaller and holds only what was decided.

## Consequences

- The day screening ships, New holds everything already captured (about 1,500 listings). Screening one source at a
  time keeps that manageable. Listings that already have reactions count as screened.
- What's on becomes only as good as Jon's screening. The New badge is what keeps it current.
- The new reaction kinds are new strings in an existing column, so CloudKit needs no schema change. `TasteRecord`
  is a new record type, added to the Development schema. An older build can't read the new kinds, so every device,
  including the checking Mac, gets the new build before anything is screened.
- Wendy shares everything (ADR-0002), screening included. A clear by Jon hides the listing from her as well.
