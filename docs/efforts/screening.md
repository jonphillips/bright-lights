# Effort — Screening, and the taste record

**Status:** Ready · **Summary:** New listings wait in **New** until Jon screens them. A screen lists one source's new
listings with none selected: tap to keep, and **Done** clears the rest for good. What's on shows what was kept. Every
decision is also written to a `TasteRecord` that outlives its listing. Listings are now deleted 30 days after they
end, whatever their reaction. New reaction kinds, one new synced table.

**Implements:** [ADR-0006](../decisions/0006-screening-and-the-taste-record.md) and
[ADR-0002 Amendment 1](../decisions/0002-shared-data-model.md#amendment-1--whats-deleted-and-when-2026-11-20).
**Builds on:** the Capture tab (PR #19) and source fixes ([source-fixes.md](archive/source-fixes.md)), whose v3 migration
comes first.

## The work

### Schema

1. **Reaction kinds.** Add `kept` and `cleared` to `ReactionKind`. Add:
   - `isPicked`, true for kept, interested, booked and went;
   - `isHidden`, true for pass and cleared;
   - a `title` for display: "Kept", "Interested", "Booked", "Went", "Pass", "Cleared".

   The column doesn't change.
2. **`TasteRecord`.** A migration, "Add taste records v4", creates `tasteRecords`, added to the `SyncEngine`'s
   tables:
   - `id`, and `householdID` (references `households`, on delete cascade);
   - `sourceRegistryID`, `sourceName`, `stableKey`, `title`, `performers` (the listing's JSON string), `room`,
     `startsAt`, `closesAt`;
   - `kind` (`ReactionKind`), `note`, `authorID`;
   - `firstDecidedAt`, `updatedAt`.

   Index `(sourceRegistryID, stableKey)`. There is no reference to `listings`. Update `docs/cloudkit/` with a
   validated Development proposal; the import waits for Jon.
3. **A derived ID.** `TasteRecord.id(householdID:sourceRegistryID:stableKey:)` is the first 16 bytes of the SHA-256
   of `"<householdID>|<sourceRegistryID>|<stableKey>"`, with RFC 9562 version-8 and variant bits set. Every writer
   uses it, so two devices deciding the same listing write the same row.

### Writes (BrightLightsSchema)

4. **Every reaction write also writes the taste record.** `Reaction.upsertForListing` fetches the listing and its
   source, and upserts the `TasteRecord` in the same transaction:
   - It copies the listing's fields and the reaction's kind, note and author.
   - It keeps an existing record's `firstDecidedAt`.
   - It sets `updatedAt` from the reaction.
5. **Nothing returns to unscreened.** Remove `Reaction.clear` from the app. Its uses (the context menu's and the
   detail's **Clear reaction**) become **Remove reaction**, which upserts `kept` with the existing note. Keep
   `Reaction.clear` only if a test needs it.
6. **`Reaction.screen(kept:cleared:authorID:now:in:)`** takes two sets of listing IDs. In one transaction, for each
   listing that still has no reaction, it writes `kept` or `cleared` with its taste record. It skips listings that
   already have a reaction, so a keep made on another device wins. It returns how many it wrote.
7. **`TasteRecord.backfill(in:)`** writes a record for every reaction whose derived ID has none. It runs at launch
   after `syncFromRegistry`, in the same write, so the rows sync, and it's idempotent.
8. **Deletion.** `Listing.pruneExpired` drops its `NOT EXISTS` reaction clause. Every listing that ended (`closesAt`,
   else `startsAt`) before the cutoff is deleted, and its reaction goes by the existing cascade. The cutoff is
   unchanged. Leave `tasteRecords` alone.

### Projections (pure, package)

9. **`WhatsOnProjection`:**
   - Hidden reactions (pass and cleared) are left out wherever pass is left out today. `passedItems` stays pass only.
   - `WhatsOnFilter` becomes `picked` ("Picked", the new default), `interestedAndBooked`, `booked` and `everything`
     ("Everything": picked plus unscreened).
   - `picked` shows items whose reaction `isPicked`. The filter applies to every group, as it does today.
10. **`NewProjection(listings:sources:reactions:now:)`:**
    - An unscreened listing has no reaction, is `listed` or `soldOut`, and hasn't ended (`(closesAt ?? startsAt) >=
      now`), on an active source.
    - It groups unscreened listings by source: name order, each with its count and its listings sorted by start.
    - It gives `count(for: Source.ID)` and a total.

### UI

11. **`ScreenList(source:listings:onDone:)`**, a component:
    - Rows show the title, then the date and time (New York) and room, then performers when there are any.
    - Nothing is selected at first. Tapping a row toggles a checkmark. Rows don't navigate.
    - The toolbar's **Done** names its effect: "Keep 3 · Clear 38", or "Clear all 41" when nothing is selected. It
      calls `Reaction.screen` with exactly the rows on screen, then `onDone`.
    - There's no confirmation. A cleared listing can be restored (item 14).
12. **New.** Add `AppScreen.new`, titled "New", with the symbol `tray.full`, placed after Coming up. Its badge is
    `NewProjection`'s total.
    - It lists sources with their counts. Tapping one pushes its `ScreenList`, and Done pops back.
    - The empty state reads "Nothing new".
    - On iPhone the tab bar now overflows, so Stays and Sources move under More. That's expected.
13. **Capture.** The current source's unscreened count is read live from the database, not from the report.
    - When it's above 0, the chip reads "41 new · Review" and opens the source's `ScreenList`. It replaces the
      "Captured listings" sheet: in the panel on iPad and Mac, and in the panel's sheet on iPhone. The panel returns
      to `RoundsList` on Done or Back.
    - **Next** reads "Review 41" while the current Rounds source has unscreened listings. It opens the screen, and
      Done then loads the next source.
    - With none, chip and Next behave as today.
14. **Cleared and restore.** Sources' detail gets a **Cleared** row, with a count, for future cleared listings. It
    pushes a list where swiping a row to **Keep** upserts `kept`.
15. **Listing detail** offers Kept, Interested, Booked, Went and Pass, with Went still only after the start. For an
    unscreened listing (reached through Everything), it also offers **Clear**. What's on rows' swipe actions and
    context menu stay, plus **Clear** in the context menu.

## Tests (package)

- `TasteRecord.id` is stable for the same inputs and differs when any input changes.
- `upsertForListing` writes and updates the taste record, and keeps `firstDecidedAt`.
- `Reaction.screen`:
  - It writes kept and cleared, with their taste records.
  - It skips a listing that already has a reaction.
- `backfill` creates records for existing reactions. A second run writes nothing.
- `pruneExpired`:
  - It deletes an expired listing that has a reaction, and the reaction goes with it.
  - The taste record survives.
  - A future cleared listing is kept.
- After a listing is captured again (`Listing.reconcile`), a cleared listing stays cleared and isn't in
  `NewProjection`.
- `WhatsOnProjection`:
  - `picked` shows kept, interested, booked and went, and not unscreened.
  - `everything` adds unscreened.
  - Cleared never shows.
- `NewProjection`:
  - It leaves out past, missing, cancelled, reacted and retired-source listings.
  - It groups and orders as described.

## Not in this effort

- Any ranking or model in New (the M2 taste work, ADR-0006).
- Taste notes.
- Ever deleting taste records.
- Screening by Wendy as a separate person (M2).

## Done when

`scripts/check-drift.sh` passes; closeout (ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

Import the Development schema, then install the build on every device, including the checking Mac (an older build
can't read the new reaction kinds).
1. On iPad, New shows a badge and lists sources. Screen one source: keep three and Done. The rest are cleared, and
   What's on (Picked) shows just the three.
2. In Capture, capture a manual source. The chip offers a review. Keep two and Done.
3. Capture the same page again. Nothing new shows, and the chip offers no review.
4. Restore one cleared listing from Sources. It appears in What's on.
5. On iPhone after sync, the same listings are picked and New's count matches.
