# M3 — Taste

*Architect, 2026-11-22. Arc: from screening every listing in date order to screens that put likely keeps first,
with the evidence on each row and a model's suggestion beside it. Jon and Wendy still make every decision.
Decisions: [ADR-0010](../../decisions/0010-taste-suggests-jon-decides.md). Builds on ADR-0006's taste record and
M2's people. The repo is public, so every fixture uses invented venues, performers and notes.*

## Slice ledger

- [x] **S1** — Counts sort a screen
- [x] **S2** — Taste notes
- [x] **S3** — The model suggests

Each slice is one dispatch, in this order. S3 reads S1's counts and S2's notes. All three are expanded below.

## S1 — Counts sort a screen

**Goal:** A screen lists likely keeps first, by the household's own record, and each row with evidence says what it
is. No model, no schema. Branch `m3/s1-counts-sort`.

### Decisions pinned in this plan

- **A new package target, `BrightLightsTaste`,** depending on `BrightLightsSchema`. S3 adds `LLMClientKit` to it.
  It holds no UI.
- **Normalizing** (for show, performer and room keys): lowercase, fold diacritics, replace every run of
  non-alphanumeric characters with one space, and trim. Nothing cleverer in S1.
- **Performers** are the JSON array string that `Listing` and `TasteRecord` already store. Move the parsing into the
  package (`ListingDisplay.performerNames` keeps formatting for display), so counts and the app read the same names.
- **The rates, the key order and the 3-decision threshold** are ADR-0010 D2, exactly.

### The work

1. **`TasteCounts`,** built once from `[TasteRecord]`. It answers, for a listing and its source's registry ID:
   - the score, and the key that set it (`.show`, `.performer(name)` or `.room`) with its picked and decided
     counts;
   - nil evidence when no key reaches 3 decisions, with the source's rate as the score.

   A record never counts as evidence for its own listing (the same registry ID and stable key).
2. **The evidence line.** One pure function: "Kept 6 of 7 · <performer>", "Kept 0 of 5 · <show title>" or "Kept 3
   of 4 · <room>". It uses the listing's own text for the name, not the normalized key.
3. **The screen.** `ScreenList` sorts its rows likely first (score, then `startsAt`, then ID) and shows the
   evidence line under any row that has one. A toolbar menu switches between **Likely first** and **By date**,
   stored in a device-local `@Shared(.appStorage("brightLightsScreenSort"))` (house law 4). Both entry points, New
   and the capture review, get the sort, so it belongs in `ScreenList` or a function both use, not in
   `NewProjection` alone.
4. **Build the counts once per change of the records,** not once per row or per render.

### Tests (package)

- Normalizing: case, diacritics, punctuation runs and whitespace.
- Rates: the three smoothed formulas, with exact expected values for small hand-made records.
- Key choice: show beats performer, which beats room. Among performers, the one with the most decisions wins, with
  ties going to the name that sorts first. A key with 2 decisions is skipped.
- A listing's own record is excluded.
- The evidence line, for each key type.
- Sorting: likely first breaks ties by date, then ID. With no records, likely first equals by date.
- Performers parse the same as today's display for the existing fixtures.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- Closeout (ADR-0005 D16), with a device gate whose check is § S1 device pass, below.

**Not in S1:** the model, notes, any schema, pre-selecting (ADR-0010 D1), and ranking New's list of sources.
**Merges:** no schema, sync or sharing, so the architect merges on approve.

### S1 device pass (Jon)

After the S1 cutover, and after a week or so of screening on Production:

1. Open New on the iPad and pick a source you've screened before. Rows with evidence show a line such as "Kept 2 of
   5 · …", and the higher rates sit at the top.
2. Switch to **By date**: the rows return to date order. Switch back.
3. Capture a source in the Capture tab and review it: the same sort and lines appear.

## S2 — Taste notes

**Goal:** Jon and Wendy write taste notes in their own words, from a listing or from a notes list, and each sees
the other's. Branch `m3/s2-taste-notes`.

### Decisions pinned in this plan

- **Fields** (ADR-0010 D3): `id`, `householdID` (references `households`, `ON DELETE CASCADE`), `authorID`
  (nullable person ID, no foreign key, as on reactions), `subject` (nullable text), `body` (text, not null),
  `createdAt`, `updatedAt`.
- **Editing.** A person edits and deletes only their own notes. A note with no author (written with no iCloud
  account) is editable by anyone. One pure function, `TasteNote.isEditable(by:)`, decides it.
- **A note from a listing** starts with its subject set to the listing's first performer, or to its title when it
  has none. The subject stays editable.

### The work

1. **Schema: migration "Add taste notes v7".** Create `tasteNotes` with the fields above, `STRICT`, and an index on
   `householdID`. In Swift it's `@Table("tasteNotes") struct TasteNote`. Add it to the `SyncEngine`'s tables, and
   its fields to `cloudkit-expected-fields.txt`.
2. **Household convergence.** In `Household.ensureDefault`, the private rule repoints a loser's notes to the
   survivor. Their IDs are random, so there's no re-keying. The shared rule deletes them with the loser by cascade,
   as it does every other child.
3. **The notes list.** A **Taste notes** screen, newest first. Each row shows the body, the subject when there is
   one, the author's name from `people`, and the date. Add, edit and delete follow the editing rule. Reach it from
   New's toolbar and from a new **Taste** section in Settings.
4. **The editor.** A form with **Subject** (optional) and **Note** (multi-line). It edits a local draft and saves on
   **Save** (jon-platform `swiftui-forms.md`). A body that's empty once trimmed can't be saved. Writes carry the
   current person as author, and failures show in an alert.
5. **From a listing.** `ListingDetailView` gets **Add taste note**, which opens the editor with the subject
   prefilled.

### Tests (package)

- Migration v7 creates `tasteNotes`, and the expected-fields test covers it.
- The private rule repoints notes, and the shared rule deletes the loser's notes.
- `isEditable(by:)`: own, someone else's, and no author.
- The subject prefill: first performer, then the title.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- Closeout (ADR-0005 D16), with a device gate whose check is § S2 device pass, below.

**Not in S2:** the model reading notes (S3), a model proposing notes, importing notes, and categories.
**Escalates:** schema and sync, so Jon merges. At review, the architect runs jon-platform `persistence-and-sync.md`
§ Adding a synced table or column, steps 1 to 6, for `tasteNotes`, and Jon deploys it before the next `testflight`
run, which its expected fields enforce.

### S2 device pass (Jon and Wendy)

1. Jon deploys `tasteNotes` to Production, runs `testflight`, and installs on the iPad and iPhone.
2. On the iPad, open a listing and tap **Add taste note**. The subject is the performer. Save a note.
3. The note shows on Jon's iPhone and on Wendy's phone, with Jon's name.
4. Wendy adds a note from Settings → Taste. On Jon's iPad, it shows her name, and it can't be edited there.

## S3 — The model suggests

**Goal:** A screen asks the user's frontier model about its rows and shows each row's verdict and reason. The
record keeps the verdict beside the decision, and Settings shows how often they agreed. Branch
`m3/s3-model-suggests`.

**Builds on:** S1's `TasteCounts` and evidence lines, and S2's notes.

### Decisions pinned in this plan

- **The verdict** is `TasteSuggestion`, a string-backed enum: `keep`, `clear`, `unsure`. It's stored as text.
- **The prompt budget** is ADR-0010 D5, exactly: 80 notes, 40 examples, 40 rows per request, with clears only as
  counts.
- **No frontier key, no call** (ADR-0010 D4). The tier comes from `FrontierResolver` with the app's key store,
  never a hardcoded provider, and never on-device.
- **Never selects and never writes a reaction** (ADR-0010 D1).

### The work

1. **`TastePrompt`,** a pure function in `BrightLightsTaste` that turns rows, records, notes, people and
   `TasteCounts` into one `ModelRequest` per batch.
   - Notes carry their author's name and subject. If more than 80 exist, it says how many were left out.
   - Each row has a short index, its title, performers, room, date and source, and its evidence lines.
   - The system prompt asks for a verdict per row, and a reason under about 12 words that names an example or a
     note. When there's no basis, the answer is `unsure`.
   - The request uses `responseFormat: .jsonSchema`, shaped as `{"suggestions": [{"index", "verdict",
     "reason"}]}`.
2. **Parsing.** A row missing from the response is `unsure`, with no reason. An unknown index is dropped. A reason
   is trimmed to 120 characters.
3. **The screen.** When a screen opens with a frontier key, it requests suggestions for rows that have no fresh
   cached one.
   - Rows show **Suggesting…** until their batch returns.
   - A failed request shows one line in the screen and doesn't retry by itself, and counts still work.
   - Each row shows its verdict ("Likely keep", "Likely clear", or nothing for unsure) and the reason. S1's evidence
     line stays under it.
   - Likely first puts keep, then unsure or none, then clear, and then S1's score, date and ID.
   - With no key, the screen says "Add a model key in Settings for suggestions" once.
4. **The cache.** Device-local, through `@Shared(.fileStorage(...))`: a listing ID maps to its verdict, its reason
   and when it was suggested. An entry older than 14 days is fetched again. Each write prunes listings that are no
   longer unscreened. It isn't synced.
5. **Schema: migration "Add taste suggestion v8".** `ALTER TABLE "tasteRecords" ADD COLUMN "suggestion" TEXT`. Add
   its fields to `cloudkit-expected-fields.txt`.
6. **Recording.** At Done, `Reaction.screen` receives the shown verdict for each row and passes it to the taste
   record write.
   - The suggestion is written only when the record is first created. Later reaction changes keep what's stored.
   - `Household`'s re-keying copy carries it, as it carries every other field.
   - Reactions made outside a screen write nil.
7. **Settings → Taste.** Show the provider suggestions use (or "none"), then the last 30 days' agreement: suggested
   keep, how many were picked; suggested clear, how many were cleared or passed; and the unsure count. It's one
   pure function over the records.

### Tests (package)

- The prompt's caps: 81 notes give 80 and "1 more not shown", and clears never appear as example rows. Examples that
  share a key come first.
- Batching: 95 rows make three requests of 40, 40 and 15.
- Parsing: missing, unknown and over-long values.
- The likely-first order with verdicts.
- Recording: the suggestion is written on the first decision and kept when the reaction later changes, a reaction
  from outside a screen writes nil, and re-keying keeps it.
- Migration v8, and the expected-fields test.
- Agreement: counts for each verdict over a hand-made record, inside and outside the 30 days.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- The PR shows one rendered prompt from a test fixture, with invented names, so the architect can read what the
  model sees.
- Closeout (ADR-0005 D16), with a device gate whose check is § S3 device pass, below.

**Not in S3:** pre-selecting or clearing by the model (ADR-0010 D1), ranking on the Mac (D8), a model proposing
notes, and per-person taste. **Escalates:** schema, so Jon merges. At review, the architect runs § Adding a synced
table or column, steps 1 to 6, for `tasteRecords.suggestion`, and Jon deploys it before the next `testflight` run.

### S3 device pass (Jon)

1. Jon deploys `tasteRecords.suggestion` to Production, runs `testflight`, and installs.
2. On the iPad, with a frontier key in Settings, open a source in New. Rows show **Suggesting…**, then verdicts
   with reasons that name your notes or past shows. Likely keeps sit first. Press Done.
3. Settings → Taste shows the provider and counts for that screen.
4. With the key removed, the screen says suggestions need a key, and S1's sort still works.
5. After two weeks of screening, read Settings → Taste and tell the architect how often the suggestions agreed.
   That answers whether the model may pre-select or clear (ADR-0010 D1).

## M3 done

New lists likely keeps first, by the household's own record, and says why. Taste notes are shared in their
authors' words. A model suggests keep or clear with a reason, and after a few weeks, Jon has the numbers to decide
whether it may do more.
