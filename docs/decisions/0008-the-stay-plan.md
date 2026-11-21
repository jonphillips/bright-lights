# ADR-0008: The stay plan — a list and the days, with errands from Reminders

*Status: accepted — 2026-11-21 (PR #28). Summary: Each stay gets a **plan** view with two parts. **The days** hold what's
fixed: booked listings, places put on a day, and errands with a due date. **This stay** is a list of what we mean
to do sometime during the stay: places pinned to it, and errands. Seasonal places that are on during the stay are
offered there, and one tap pins them. Errands stay in a shared Apple **Reminders** list, which Bright Lights reads
and can tick off but never copies. It's a menu with a few fixed points, not an itinerary.*

## Context

Jon wants a calendar view of an upcoming stay that can hold things to do as well as shows, and he doesn't want to
rebuild Reminders. Talking it through on 2026-11-21 sorted the things to do into three kinds:

- **Places,** lasting or seasonal (ADR-0007). "See the Christmas windows" is a place with a yearly season.
- **The intention to go somewhere during a particular stay,** like "this time we finally go to Peter Luger." That's
  a fact about the stay, not about the place.
- **Errands,** like "buy a sauté pot." Nobody wants them on a map, nothing closes, and Reminders already handles
  them: shared lists, Siri, and a reminder when you arrive somewhere.

Settled things this has to respect:

- **The app doesn't plan stays like an itinerary** (BRAINSTORM, PRODUCT). It gives a short menu with deadlines.
- **The iPad lays a stay out as a calendar** (BRAINSTORM, settled).
- **Galavant's guide lens** (Galavant ADR-0053 D8) shows each trip day's lunch and dinner slots and fills them from
  the guide. That's the closest precedent. Galavant's full itinerary, with stops, alternatives and timing, is more
  than Bright Lights wants.

Jon settled on 2026-11-21: seasonal things are places, errands live in a shared Reminders list, and the stay view
is a list beside the days.

## Decision

1. **Every stay has a plan view.** It covers the stay's days, from arrival through the departure date (tentative
   or booked). An open departure counts as seven days, as `StayRules` already does. It's for the current stay and
   any upcoming one. A past stay's plan stays readable.
2. **The days hold what's fixed:**
   - **Booked listings,** at their times. They come from reactions and aren't copied into the plan.
   - **Places put on a day,** optionally at a meal: "Thursday, dinner: Lilia."
   - **Errands with a due date** that falls inside the stay.

   Nothing here is a timeline. A day is a short list, booked things first, by time.
3. **"This stay" holds what has no day:**
   - **Places pinned to the stay** with no day.
   - **Errands with no due date,** shown on the current stay, or on the next stay when you're not in town. Never
     on more than one stay.
   - **On only now:** to-try places whose season overlaps the stay and aren't pinned yet, with when each ends. These
     are offers, not plan rows. One tap pins one. Nothing is pinned without a tap.

   Dragging a pinned place onto a day, or back off it, is allowed and never required.
4. **`StayPlanItem` is a new synced table.** One row means "this place, this stay":
   - It's a child of `Stay` through its one real foreign key, so it shares with the household
     (jon-platform persistence-and-sync, the single-foreign-key rule). The place is a **loose `placeID` column**,
     not a foreign key.
   - It has an optional **day** and an optional **meal** (ADR-0007 D4's vocabulary). Each is useful alone: "Thursday"
     and "a lunch sometime" are both real plans. It also has an attribution-only author.
   - **Deleting a place deletes its plan items** in the same transaction, and a plan read skips any item whose
     place is missing. Deleting a stay deletes its items by the cascade.
   - **A day outside the stay counts as no day.** If the stay's dates change so the day falls outside, the item shows
     under This stay, and its stored day is left alone.
   - **One row per place per stay.** Pinning a place that's already pinned changes its day or meal. Since unique
     indexes are off limits for synced tables (house rule), the ID is derived from the stay and the place, so two
     devices land on the same row.
5. **Going there logs a visit.** "Went" on a plan item writes an ADR-0007 `PlaceVisit` with the item's day (or
   today) and meal, and moves a to-try place to tried, through ADR-0007 D3's sheet. The plan item stays, so the
   stay's plan reads as what happened.
6. **When a stay ends, what you didn't get to is offered to the next stay.** "Didn't get to: X, Y. Move them to the
   next stay?" Moving creates rows on the next stay and leaves the old ones. Nothing moves without a tap.
7. **Errands live in one shared Reminders list.**
   - Bright Lights reads one Reminders list through EventKit, with full Reminders access. The list is chosen once
     on each device, and the choice is stored on that device, since EventKit list identifiers aren't shared across
     devices.
   - **Nothing from Reminders is stored in Bright Lights' database or synced.** Each device reads its own Reminders,
     which iCloud keeps in step. Wendy sees the errands when the list is shared with her in Reminders.
   - Incomplete reminders are shown (D2, D3). Completed ones aren't. Ticking one in Bright Lights completes it in
     Reminders.
   - A **quick add** in This stay creates a reminder in that list, with a title and an optional due date. Anything
     more (notes, locations, alerts) is done in Reminders, and a reminder opens there.
   - With no list chosen, or access declined, the plan shows no errands and one line offering to set it up. Nothing
     else depends on it.
   - The checking Mac never reads Reminders.

## Considered and rejected

- **Errands as Bright Lights rows.** That rebuilds Reminders, without Siri, location alerts or sharing that already
  works. Jon ruled it out.
- **The whole plan in Reminders,** places included. That loses the map, seasons and the closing warnings, and a
  reminder can't point at a place row.
- **Pinning as a column on `Place`** ("next stay"). A place can be pinned to more than one stay, and a pin needs a
  day and a meal. It also loses the history of what each stay held.
- **Galavant's itinerary model** (stops, alternatives rings, timing). That's for planning trips, and Bright Lights
  deliberately doesn't plan stays that way.
- **Seasonal places pinned automatically.** The app offers and people decide, as everywhere else in the house.
- **Reminders written to Apple Calendar,** or the stay's plan exported there. Reading the shared calendar for home
  commitments is separate later work (BRAINSTORM, Galavant ADR-0034) and doesn't wait on this.

## Consequences

- One more synced table. It goes in the CloudKit Development schema now, and Production waits for TestFlight (M2),
  like the rest. It depends on ADR-0007's `Place`, so the places slices come first.
- A new permission prompt (full Reminders access), the first time someone sets up errands. The usage string goes in
  `project.yml`.
- The plan view is where the iPad's "stay laid out as a calendar" lives, so it's where What's on's While we're here
  should link to on the iPad. The slice plan decides how the two screens meet.
- Wendy's errands work through Reminders sharing, outside Bright Lights' share, so a list shared with only one of
  them shows errands on only that person's devices. Setting it up is a step in inviting Wendy (M2).
