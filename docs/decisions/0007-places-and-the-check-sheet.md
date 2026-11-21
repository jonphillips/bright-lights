# ADR-0007: Places — a map and an ideas list, with one shared standing per place

*Status: proposed — 2026-11-21. Summary: A **place** is anything with a spot on the map that Jon and Wendy hold an
opinion about: a restaurant, a bar, a park, a shop, a walk, the Cyclone. Each place has one shared **standing**,
which is the check sheet: to try (high, normal or someday), tried (our place, would return, or once was enough), or
not for us. Visits are a dated log under the place. A place can have a **season**, like the Christmas windows or
the Cyclone, and then it behaves like a listing with a closing date. Food places record which meals they serve, so
the map can filter to Food, then Lunch or Dinner. Venues aren't places and don't join the check sheet.*

## Context

Jon wants a map and an ideas list soon. Bright Lights is about a place they live in for a week each month, not a
trip, so he also wants something like a check sheet: been here, would return, need to go, high or low priority.

PRODUCT.md had places as "only if wanted," and `open-questions.md` asked whether they were in scope. Galavant has
places already, and they shape this decision in three ways:

- **Galavant keeps pre-visit interest and visiting apart.** `Interest` runs from Must Do to Do Not Do and is set
  before going. `Idea.visited` is a single flag.
- **The flag turned out too coarse.** Galavant ADR-0053 D7 says `visited` "can't carry dining or hotel history,"
  and moved history into notes. A home base makes this worse, because the places you love get visited again and
  again.
- **Galavant's lists are filters.** ADR-0053 D6: *Want to Go* and *Not for Me* are interest levels, and there's no
  list entity.

Jon settled these on 2026-11-21:
- The standing is **shared**: one per place, for both of them. Disagreements go in notes.
- **Anything can be a place.** It isn't limited to restaurants and bars. Something that's only on for a while,
  like the Christmas windows, is a place with a season, not a separate kind of item.
- **Venues don't join the check sheet.** Sources stay sources.
- The map needs an **easy filter for food, and for lunch or dinner**.

## Decision

1. **A place is anything with a location.** It might be an Apple Maps point of interest, an address, or a dropped
   pin, and its location is what puts it on the map. A place has a name, a location, a **kind** (D4), an optional
   note, a standing (D2), and a **when** (D10).
2. **One shared standing per place, with seven values in three groups:**
   - **To try:** high, normal or someday. That's the priority.
   - **Tried:** our place, would return, once was enough, or not said yet.
   - **Not for us:** been or not. It's hidden from the map and the list unless a filter asks for it.

   In code it's an enum with associated values, `.toTry(Priority)`, `.tried(Verdict?)` and `.notForUs`, stored as a
   single string column with stable raw values. There's no separate "visited" flag, because "tried" already says it.
   The standing is household state like a reaction (ADR-0002): one value for both of them, with an attribution-only
   author and no ownership.
3. **Visits are a dated log.** A `PlaceVisit` row holds a day, an optional meal (D4), an optional note, and an
   attribution-only author. It's a child of its place.
   - **Logging a visit to a to-try place moves it to tried**, with the verdict not yet said. The same sheet then
     offers the verdict, and skipping it is allowed.
   - **A place can be tried with no visits.** That covers "we've been, a while ago." Visits are the history, and the
     standing is the answer.
   - **The last visit date is the reminder for favorites.** "Our place, last visit four months ago" is worked out
     from the log. It's never stored as a priority.
4. **Kinds and meals.**
   - A place's **kind** is one of a short fixed list, with stable string raw values: food, drink, coffee, park,
     shop, sight, activity, other. At capture it's mapped from the Apple Maps category, as Galavant's `IdeaKind`
     is, and it can always be changed. The list can grow later. Cases are never renamed or removed.
   - **A food place records which meals it serves:** breakfast, lunch, dinner and late night, the vocabulary of
     Galavant's `Meal`. It's a set in one column. An empty set means not said yet. It can be filled in from the
     place's own website hours when capture can read them (Galavant's `HoursExtractor` path), and a hand edit
     always wins. Opening hours themselves aren't stored yet (`open-questions.md`).
5. **The map and the ideas list are one screen over the same filtered places,** as in Galavant. The check sheet is
   that list, grouped by standing. The filters are:
   - **Kind:** All, Food, Drink and the rest, as chips. Food is the first chip.
   - **Meal**, shown only while Food is on: Any, Lunch or Dinner, with Breakfast and Late night under More.
     Choosing Lunch shows food places marked lunch. Places with no meals set aren't shown, but the list says how
     many there are and offers to fill them in.
   - **Standing:** To try, Tried, or Everything. Not for us is under More.

   Filter choices are device-local view state and never synced.
6. **Capture comes from Galavant.** That means searching Apple Maps, tapping a map point to look before you save
   (Galavant ADR-0044), deduplicating by Apple Maps identity (Galavant ADR-0019), and an address or dropped pin for
   anything Apple Maps doesn't know. The parts are lifted into jon-platform, never copied. The first places slice
   records the `SEAM-LEDGER.md` rows and decides the package boundary, since `GalavantPlaces` depends on
   `GalavantSchema` today.
7. **Venues stay out.** A `Source` is never a place, and there's no link between the two. A `went` reaction to a
   listing doesn't log a visit anywhere.
8. **Places aren't taste records.** ADR-0006's `TasteRecord` stays about listings. A place's standing, note and
   visits are their own evidence. Places are never pruned, so none of that needs to outlive anything.
9. **Sharing and schema.** `Place` is a child of `Household`, and `PlaceVisit` a child of `Place`. Both are new
   record types in the CloudKit Development schema, and deploying them to Production waits for TestFlight (M2), as
   for every M1 table. Wendy sees and edits all of it (ADR-0002). Deleting a place deletes its visits, so the app
   offers Not for us first.
10. **A place's when: always, every year, or once.** It's an enum with associated values:
    - `.always`, which is most places.
    - `.yearly(from: MonthDay, to: MonthDay)`, for a season that comes back each year: the Christmas windows from
      about Nov 20 to Jan 5, or the Cyclone in summer. A season can run across New Year.
    - `.once(from: Date, to: Date)`, for something on only once: a pop-up, an installation.

    A place out of season stays on the map and the list, marked with when it's next on, and filters can hide it.
    A to-try place in season is offered to every stay its season overlaps (ADR-0008), and the end of its season
    gets the same warning as a listing's close in Coming up ("ends Jan 5, and you're only in town once more before
    then"). Being good for one visit needs nothing new: after the visit it's tried, and a yearly place marked
    *would return* comes back next season. A `.once` place whose dates have passed drops out of to-try views and
    keeps its history. Like everything else on a place, it's never pruned.

## Considered and rejected

- **Priority as its own column beside a verdict.** It allows "tried, our place, someday" and "not for us, high,"
  which mean nothing. One enum can't hold those.
- **A `visited` flag beside interest.** That's Galavant's arrangement, which its ADR-0053 D7 calls too coarse.
- **A verdict for each person.** Jon chose one shared standing (Context). Galavant's per-planner interest exists
  for a group deciding together, and Bright Lights has no voting.
- **Named lists** ("Date night", "Brunch"). Filters cover the asks so far. A list entity can be added later if a
  filter can't express something, and adding one is cheaper than removing one.
- **Venues as places.** Jon ruled it out. It would also put about 25 venues on the check sheet that are already
  followed for their listings.
- **A separate one-off item** for things like the Christmas windows. They have a place and they're done once,
  which a place with a season and *once was enough* already covers. A second kind of item would split the map, the
  list and the filters.
- **Storing opening hours now.** Lunch and dinner only need meals. Hours ("open Monday night?") are a larger,
  permanent column, so they wait until they're wanted.

## Consequences

- PRODUCT.md moves places from "only if wanted" to planned. A milestone or effort brief dispatches the slices
  later. This ADR dispatches nothing.
- Two new synced tables, each one permanent once deployed to Production. Their column names follow house schema
  hygiene.
- The meal filter is only as good as the meals filled in. The count of places with no meals set is what keeps it
  honest.
- Pinning a place to a stay is ADR-0008's stay plan.
- Later work, kept in `open-questions.md`: opening hours and "open tonight," progress by
  neighborhood, travel time from the apartment (BRAINSTORM's "getting home"), and places in chat access.
