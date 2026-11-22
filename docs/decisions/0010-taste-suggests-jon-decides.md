# ADR-0010: Taste — counts sort a screen, the model suggests, and only a tap decides

*Status: proposed — 2026-11-22, accepted when Jon merges the M3 plan PR. Summary: The taste record (ADR-0006) starts
earning its keep. A screen's rows sort by how often similar listings were kept, with the evidence on the row. Jon and
Wendy write taste notes in their own words. A model reads the notes and the record and suggests keep or clear for
each row, with a reason. It never selects, clears or writes a reaction. Every decision stays a person's tap, and the
record shows how often the model agreed, so Jon can decide later whether it may do more. Amends ADR-0006 point 3 (a
screen's order). Adapts Galavant ADR-0053 D2 and D3.*

## Context

ADR-0006 keeps a `TasteRecord` for every keep, clear, pass, booking and visit, and left the learning to later work.
Its open questions, from `open-questions.md`:

- How the counts and the model rank New, and whether ranking means sorting, pre-selecting rows, or both.
- Whether the model may ever clear a listing without Jon's tap. Jon decides once he's seen its suggestions.
- Where taste notes live.
- How long taste records last, and how many go into one prompt.
- Whether ranking runs on the checking Mac each night.

Four facts shape the answer:

- **The record restarts at the Production cutover** (ADR-0009). When M3 ships, it holds weeks of decisions, not
  months. Every layer has to degrade to today's date order when there's no evidence.
- **Volume is high, and most decisions are clears.** The automated sources bring about 1,500 listings, and a big
  venue's screen can hold 50 rows. Counts mean something here, as they do in Vinyl Fever and not in Galavant.
- **A screen's Done writes a decision for every row** (ADR-0006 point 3): selected rows are kept and the rest are
  cleared. Whatever is selected when Jon presses Done becomes his decision, whether he looked at the row or not.
- **The repo is public.** Fixtures use invented venues, performers and notes. Real notes never go in the repo.

## Decision

### D1 — Only a person's tap decides

No suggestion is ever written as a reaction. In M3 the model doesn't pre-select rows, and nothing is cleared
without Done. A pre-selected row that Jon skims past becomes his keep, and the record would then learn the model's
guess as his taste, a loop that hides its own errors. Pre-selecting and clearing are Jon's call once he's seen
the agreement numbers (D7). They're open questions, not M3 work.

### D2 — Counts sort a screen, with the evidence on the row

A pure function over the household's taste records, with no model:

- **Keys.** Each listing has a **show** key (its normalized title, within its source), a **performer** key for each
  performer (across sources), and a **room** key (its normalized room, within its source). A key's evidence is its
  count of picked decisions (kept, interested, booked, went) and of hidden ones (cleared, pass).
- **Smoothed rates,** so one keep doesn't outrank thirty:
  - The global rate is `(picked + 1) / (decided + 2)`.
  - A source's rate is `(picked + 2·global) / (decided + 2)`.
  - A key's rate is `(picked + 2·source) / (decided + 2)`.
- **A listing's score** is the rate of its most specific key with at least 3 decisions. The order is show, then
  performer (the one with the most decisions), then room. With no such key, it's the source's rate.
- **The row shows the key it used:** "Kept 6 of 7 · Big Thief", or "Kept 0 of 5 · Tuesday Night Standup".
- **The order.** A screen sorts **likely first** (score, then date) by default, and a device-local toggle switches it
  back to **by date**. With no evidence, every row ties and the order is the date order it is today. This amends
  ADR-0006 point 3, which sorted by date only. Both screens, New's and the one after a capture, sort the same way.

Counts are explainable and need no key, no network and no wait, so they run on every device, every time.

### D3 — Taste notes are synced, verbatim, and need no category

Galavant ADR-0053 D2's rules, in Bright Lights' tree:

- A `TasteNote` is a person's own words: about a performer, a venue, a kind of show, or nothing in particular ("late
  shows on a weeknight wear me out"). A model never writes or proposes one in M3.
- It's a child of `Household`, synced and shared, with its author. It has an optional free-text **subject**
  (a performer, venue or show) and no category.
- It refers to no listing or source row, so it outlives them.
- A person edits and deletes only their own notes. Who wrote it is part of what it means.

### D4 — The model suggests in the screen, on demand, through the user's frontier key

- **Where and when.** On the device doing the screening, when a screen opens, for rows with no fresh suggestion.
  Not nightly on the Mac (D8).
- **Which model.** The user's frontier provider, resolved through `FrontierResolver` (jon-platform
  `ai-model-access.md`). The evidence doesn't fit the on-device model's context, so with no frontier key there are no
  suggestions, and the screen says so in one line. Counts still work. It never silently falls back to on-device.
- **What it returns.** Structured output (jon-platform ADR-0004). Each row gets a verdict, **keep**, **clear** or
  **unsure**, and a short reason that names an example or a note ("you kept 6 of 7 Big Thief shows").
- **How it shows.** The verdict and reason sit on the row. Likely first puts suggested keeps first and suggested
  clears last, then orders by D2's score and the date.
- **What's stored.** Suggestions are cached on the device, not synced. The only model output that syncs is the
  verdict recorded beside the decision (D7). There's no stored taste profile and no stored reasoning (ADR-0053 D3).

### D5 — What goes into one prompt

The record outgrows a prompt: a year of clears is thousands of rows. So D2's counts choose what the model reads.

- **Notes:** the 80 most recent. If more exist, the prompt says how many were left out.
- **Evidence per row:** each row's matched keys, with their counts, as one line each.
- **Examples:** up to 40 decided records. First the ones that share a key with a row (most decisions first), then
  the most recent picks and passes that have notes. Clears appear only as counts, never as example rows.
- **Rows:** in batches of 40 per request.

### D6 — Taste records last indefinitely

They're short text rows. Thousands a year costs little in SQLite or CloudKit, and older evidence still counts.
Revisit at 20,000 rows, or when a prompt or a count gets slow.

### D7 — The record keeps the suggestion beside the decision

`TasteRecord` gains a nullable `suggestion`: the model's verdict when the row was first decided, or nil when there
was none. Later reaction changes keep it. Settings → Taste shows the last 30 days: how many suggested keeps were
kept, how many suggested clears were cleared or passed, and how many were unsure. That's the evidence Jon needs for
D1's open questions. It's ADR-0053 D5's rule, that the prediction is kept next to what happened.

### D8 — Not nightly on the Mac, in M3

Ranking every new listing overnight would need a synced table of model output, which is permanent schema. It would
pay for listings that may never be screened. And the suggestions would go stale when a note changes during the day.
A screen's suggestions take seconds on demand. Revisit if waiting on them gets in the way.

## Considered and rejected

- **Pre-selecting likely keeps.** Faster, but a skimmed Done turns guesses into decisions (D1). Decided again once
  D7 has numbers.
- **One weighted score over every key, or embedding similarity.** Ranks a little better, perhaps, but it can't say
  why. A row that names its evidence lets Jon check it at a glance.
- **A stored, model-written taste profile.** Galavant ADR-0053 D3 and Vinyl Fever rejected it: it can't be inspected
  and goes stale. The notes and the record are the profile, and the model reads them fresh.
- **Taste per person.** There are two people, Jon makes about 95% of the decisions, and screening is household state
  (ADR-0006). Authors stay on records and notes, so it can be split later.
- **Suggestions on-device, or through Private Cloud Compute.** The notes and examples don't fit. A small batch with
  counts alone adds little to D2.

## Consequences

- **Two additive CloudKit deploys:** `tasteNotes` (S2) and `tasteRecords.suggestion` (S3). Both are permanent. Both
  slices escalate, so Jon merges.
- **Model cost per screen** on Jon's own key: roughly one request per 40 new rows, once each.
- **Suggestions send listing text, notes and decisions to the user's provider.** That's the house's BYO-key
  pattern, and Settings says which provider is in use.
- **Weak at first.** The record restarts at the cutover, so the first weeks sort mostly by date. That's expected,
  and the device passes say so.

## Slices

[M3 — Taste](../milestones/M3-taste.md): S1 counts sort a screen, S2 taste notes, S3 the model suggests.
