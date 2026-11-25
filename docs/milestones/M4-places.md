# M4 — Places and the stay plan

*Architect, 2026-11-24. Arc: from an app that only follows listings to one that also holds the places Jon and Wendy
care about, on a map and a check sheet, and lays each stay out as its days plus a "this stay" list, with errands
from Reminders. Decisions: [ADR-0007](../decisions/0007-places-and-the-check-sheet.md) and
[ADR-0008](../decisions/0008-the-stay-plan.md). The repo is public, so every fixture uses invented places, people
and notes.*

## Slice ledger

- [x] **S1** — A shared map places kit
- [x] **S2** — Places and the check sheet
- [x] **S3** — The map and its filters
- [ ] **S4** — Seasons
- [ ] **S5** — The stay plan
- [ ] **S6** — Errands from Reminders

Each slice is one dispatch, in this order. S1 and S2 are expanded below. The architect expands each later slice
here before dispatching it. The goals and pinned decisions already written for S3 to S6 are part of this plan.

**Merges:** S2 and S5 add synced tables, so Jon merges them. The architect merges the rest on approve, S1's
jon-platform PR included, once it has rerun that PR's verification.

## The schema, all of it, pinned now

Production's schema is permanent (jon-platform `persistence-and-sync.md` § Schema hygiene), so all three tables are
settled here, before S2 starts, even though `stayPlanItems` lands in S5. Days are `Date` values at the start of the
day in New York, as `StayRules.normalized` makes them for stays.

**`places`** (S2, migration "Add places v8"). It's a child of `households`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | random UUID |
| `householdID` | TEXT NOT NULL | references `households`, `ON DELETE CASCADE` |
| `name` | TEXT NOT NULL | |
| `latitude`, `longitude` | REAL NOT NULL | |
| `address` | TEXT | one line, from Apple Maps |
| `mapItemIdentifier` | TEXT | Apple Maps identity, for finding duplicates at capture. Nil for a dropped pin. |
| `websiteURL` | TEXT | |
| `kind` | TEXT NOT NULL | `PlaceKind` raw value: `food`, `drink`, `coffee`, `park`, `shop`, `sight`, `activity`, `other` |
| `meals` | TEXT NOT NULL DEFAULT '' | the `Meal` raw values `breakfast`, `lunch`, `dinner`, `lateNight`, comma-joined in that order. Empty means not said yet. |
| `standing` | TEXT NOT NULL | `PlaceStanding` raw value (below) |
| `authorID` | TEXT | the last person to set the standing, attribution only, as on reactions |
| `note` | TEXT | |
| `whenKind` | TEXT NOT NULL DEFAULT 'always' | `always`, `yearly` or `once` |
| `seasonStart`, `seasonEnd` | INTEGER | for `yearly`: month × 100 + day, so Nov 20 is 1120 and Jan 5 is 105. A start after the end runs across New Year. |
| `onceStart`, `onceEnd` | TEXT | for `once`: days |
| `createdAt`, `updatedAt` | TEXT NOT NULL | |

Indexes are on `householdID` and `mapItemIdentifier`.

- **`PlaceStanding`** is `.toTry(Priority)`, `.tried(Verdict?)` or `.notForUs`, stored in one column with these
  stable raw values: `toTry.high`, `toTry.normal`, `toTry.someday`, `tried`, `tried.ourPlace`, `tried.wouldReturn`,
  `tried.onceWasEnough` and `notForUs`. A custom `QueryBindable` conformance maps it. An unknown raw value reads as
  `.toTry(.normal)` and reports an issue, so a newer build's value never crashes an older one.
- **`Meals`** is a `QueryBindable` set of `Meal`, so no code handles the comma string.
- **`PlaceWhen`** is `.always`, `.yearly(from: MonthDay, to: MonthDay)` or `.once(from: Date, to: Date)`. It's a
  computed property over the five `when` columns, as `Stay.departure` is over its two, and its setter clears the
  columns the new case doesn't use.

**`placeVisits`** (S2, the same migration). It's a child of `places`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | random UUID |
| `placeID` | TEXT NOT NULL | references `places`, `ON DELETE CASCADE` |
| `day` | TEXT NOT NULL | a day |
| `meal` | TEXT | a `Meal` raw value |
| `note` | TEXT | |
| `authorID` | TEXT | attribution only |
| `createdAt` | TEXT NOT NULL | |

It has an index on `placeID`.

**`stayPlanItems`** (S5, migration "Add stay plan items v9"). It's a child of `stays` (ADR-0008 D4).

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | derived from the stay ID and place ID, the way `TasteRecord` derives its ID, so two devices pinning the same place land on one row |
| `stayID` | TEXT NOT NULL | references `stays`, `ON DELETE CASCADE` |
| `placeID` | TEXT NOT NULL | a loose UUID with no foreign key, under the single-FK rule |
| `day` | TEXT | a day. A day outside the stay counts as no day and is left as stored. |
| `meal` | TEXT | a `Meal` raw value |
| `authorID` | TEXT | attribution only |
| `createdAt`, `updatedAt` | TEXT NOT NULL | |

It has an index on `stayID`.

**What's settled with the schema:**

- **There's no "went" column.** A plan item counts as went when its place has a visit dated inside the stay. The
  stay's "didn't get to" list (ADR-0008 D6) is derived the same way.
- **Duplicate places are caught at capture only.** Capture looks up `mapItemIdentifier` and opens the existing place
  instead of adding another (Galavant ADR-0019). Two devices capturing the same place offline can still make two
  rows. Both show, and either can be deleted. There's no convergence pass, because a duplicate place is clutter, not
  wrong data.
- **Household convergence** (`Household.ensureDefault`): the private rule repoints a losing household's places to
  the survivor. Their IDs are random, so there's no re-keying, and visits follow their place. The shared rule
  deletes them with the loser by cascade, as for every other child. Plan items ride their stays.
- **Not stored:** opening hours, a visited flag, a priority column, a neighborhood, and anything from Reminders.

## S1 — A shared map places kit

**Goal:** Galavant's Apple Maps search, as-you-type completion and map-tap resolution become a domain-free
jon-platform package, `MapPlacesKit`, so Bright Lights captures places with the same parts (ADR-0007 D6). There's no
Bright Lights UI in this slice. Branches: `m4/s1-map-places-kit` in jon-platform and in Bright Lights.

This dispatch's code lands in jon-platform, so it follows jon-platform `agent-collaboration.md` § Dispatches whose
code lands in jon-platform. The package PR comes first. Once it merges, a companion Bright Lights PR adds the
dependency and keeps the records.

### Decisions pinned in this plan

- **What moves** comes from `galavant/GalavantLibrary/Sources/GalavantPlaces/PlaceSearch.swift` and
  `PlaceSearchCompletion.swift`, and from `Galavant/MapPlaceResolver.swift`:
  - `Place` becomes `MapPlace`. It keeps `id`, `name`, `latitude`, `longitude`, `regionName`, `url`, `phone`,
    `address`, `mapItemIdentifier`, `timeZoneIdentifier`, `searchIdentity` and `init(mapItem:)`. `kind: IdeaKind?`
    becomes `pointOfInterestCategory: String?`, the raw `MKPointOfInterestCategory` value, and each app maps it to
    its own kinds.
  - `PlaceSearchViewport` becomes `MapPlaceViewport`.
  - `PlaceSearchScope` becomes `MapPlaceSearchScope`. Galavant's `MapRegion` is domain, so `.regions` and
    `.biasedRegions` take a neutral `MapPlaceRegion` (a center and a span).
  - `PlaceSearchClient` becomes `MapPlaceSearchClient`, with `search`, `complete` and `resolve`, its live and test
    values, and the existing comments on why search and completion are separate requests.
  - `PlaceSuggestion`, `PlaceSearchResult` and the completer plumbing come along.
  - `PlaceSearchModel` becomes `MapPlaceSearchModel`, with suggestions first, then search results.
  - `MapPlaceResolver` comes along with `mapItem(for: MapFeature)` and `place(for:)`, returning `MapPlace`. A
    feature that doesn't resolve becomes a `MapPlace` with the feature's title (or "Pinned Location"), its coordinate
    and its category.
- **What stays in Galavant:** `IdeaKind` and its category mapping, `MapPlaceCapture`, enrichment, images, hours,
  matching and every view. Galavant keeps its own copy until it adopts the kit in a Galavant dispatch. S1 records
  that as owed in `EXTRACTION-NOTES.md` and `SEAM-LEDGER.md`, as `LLMHandoffKit` did. S1 doesn't change Galavant.
- **The package** is `packages/MapPlacesKit`, with one library and target, `MapPlacesKit`, on iOS 26 and macOS 26,
  depending on `swift-dependencies` only. It has no UI target and no SQLiteData.

### The work

1. **jon-platform PR** (`M4 · S1 — Shared map places kit`, linking this section):
   - Create the package with the moved code, renamed as pinned. Keep the comments, swapping Galavant's nouns for
     neutral ones.
   - Move the matching tests from `GalavantPlacesTests` (`PlaceSearchModelTests` and the scope tests), with fixtures
     made neutral.
   - Add the `SEAM-LEDGER.md` row, recorded as lifted with Galavant adoption owed, and the `EXTRACTION-NOTES.md` row.
     List the package in `README.md`'s package tree and its paragraph on shared packages.
2. **Bright Lights companion PR**, after the package PR merges:
   - Add `MapPlacesKit` by path to `BrightLightsLibrary`. A new target, `BrightLightsPlaces`, depends on it and on
     `BrightLightsSchema`. It holds one thing in S1: `PlaceKind(pointOfInterestCategory:)`, the mapping below.
   - Closeout.

**The kind mapping** (`MKPointOfInterestCategory` raw values; anything else is `other`):

| Kind | Categories |
| --- | --- |
| food | restaurant, bakery, foodMarket |
| coffee | cafe |
| drink | nightlife, brewery, winery, distillery |
| park | park, nationalPark, beach |
| shop | store |
| sight | museum, landmark, castle, musicVenue, theater, planetarium, aquarium, zoo |
| activity | amusementPark, bowling, goKart, miniGolf, rockClimbing, skating, spa, fitnessCenter, stadium |

A category name the SDK doesn't have is left out of the table, not worked around.

### Tests

- Package (moved): the search model merges suggestions before results and drops duplicates by `searchIdentity`. A
  viewport scope biases without fencing, and a strict region scope fences. A failure in one half of the search
  doesn't throw.
- Package (new): `MapPlace(mapItem:)` carries the category's raw value.
- Bright Lights: every row of the kind table maps, and nil or an unknown value maps to `other`.

### Done when

- jon-platform: the PR lists what ran, as that section requires: `scripts/quiet-run swift test --package-path
  packages/MapPlacesKit`, and the iOS Simulator compile from `packages/MapPlacesKit`.
- Bright Lights: `scripts/check-drift.sh` passes, and CI is green. Closeout (ADR-0005 D16). There's no device gate.

**Not in S1:** any place UI or schema, Galavant's adoption, the hours extractor, and Galavant's `PlaceSelectionMap`.

## S2 — Places and the check sheet

**Goal:** Jon and Wendy add places by searching Apple Maps, see them as a check sheet grouped by standing, and log
visits. There's no map yet. Branch `m4/s2-places`.

### Decisions pinned in this plan

- **Schema:** `places` and `placeVisits`, exactly as pinned above, including the `when` columns S4 uses. Rows
  default to `.always`.
- **A new screen, Places** (`AppScreen.places`, "Places", `mappin.and.ellipse`), placed after Coming up.
- **Search is biased to New York, not fenced:** `.biasedRegions` around (40.73, −73.96) with a span of 0.35°, so
  a place named outside the city can still be found.
- **New places start as `.toTry(.normal)`.** Capture asks for nothing else: kind comes from the mapping and can be
  changed, and meals are offered only for food.

### The work

1. **Schema.** Migration "Add places v8", the `@Table` structs, `PlaceStanding`, `Meals` and `PlaceWhen`. Add the
   tables to the `SyncEngine` and their fields to `cloudkit-expected-fields.txt`. Update household convergence as
   pinned.
2. **`PlaceOperations`** in `BrightLightsSchema`. These are the only writers:
   - add from a `MapPlace`, or open the existing place with the same `mapItemIdentifier`;
   - set the standing, recording the author;
   - log a visit (ADR-0007 D3): on a to-try place it also sets `.tried(nil)`. Delete a visit.
   - delete a place. Its visits go by the cascade, and S5 adds its plan items to the same transaction.
3. **The check sheet.** Places' root is a list grouped by standing: To try (high, then normal, then someday), then
   Tried (our place, would return, not said yet, once was enough). Within a group it's sorted by name. Not for us is
   hidden behind a toolbar toggle until S3's filters replace it. Each row shows the name, the kind's symbol, the
   meals when set, and for tried places the last visit ("Last visit Aug 12"). An empty list offers **Add place**.
   The grouping, order and last-visit date come from one pure projection in `BrightLightsPlaces`, which S3's
   filters extend.
4. **Add place.** A sheet with a search field over `MapPlaceSearchModel`. Picking a result adds the place, or opens
   the existing one, and lands on its detail.
5. **Place detail.** It shows the name, kind and address (opening Apple Maps), the website, the standing, meals (food
   only), and the note, all editable through a local draft saved on **Save** (jon-platform `swiftui-forms.md`). Below
   them are the visits, newest first, and **Log visit**. **Delete** asks first, and its dialog offers **Mark Not
   for us** as the first choice (ADR-0007 D9).
6. **Log visit.** A sheet with the day (default today), the meal (food only), and a note. When the place was to-try,
   the same sheet then offers the verdict, and skipping it leaves `.tried(nil)`.

### Tests (package)

- Migration v8 creates both tables, and the expected-fields test covers them.
- `PlaceStanding` round-trips every raw value, and an unknown value reads as `.toTry(.normal)`.
- `Meals` round-trips, including empty, and writes the canonical order whatever the insertion order.
- `PlaceWhen` round-trips all three cases, a yearly season across New Year included. Setting `.always` clears the
  other four columns.
- Adding a place whose `mapItemIdentifier` exists returns the existing one and inserts nothing.
- Logging a visit on a to-try place sets `.tried(nil)`. On a tried place it leaves the verdict alone.
- Deleting a place deletes its visits.
- The private convergence rule repoints places, and the shared rule deletes the loser's.
- The check-sheet grouping and order, and the last-visit date.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- Closeout (ADR-0005 D16), with a device gate whose check is § S2 device pass, below.

**Not in S2:** the map, filters, seasons' UI, the stay plan, dropped pins, and filling meals from a website.
**Escalates:** schema and sync, so Jon merges. At review, the architect runs jon-platform `persistence-and-sync.md`
§ Adding a synced table or column, steps 1 to 6, for `places` and `placeVisits`, and Jon deploys them before the
next `testflight` run.

### S2 device pass (Jon and Wendy)

1. Jon deploys `places` and `placeVisits` to Production, runs `testflight`, and installs on the iPad and iPhone.
2. On the iPad, add three places from search: a restaurant, a bar and a park. Each lands in To try with the right
   kind. Searching for the restaurant again opens it instead of adding it twice.
3. Log a visit to the restaurant and pick **Our place**. It moves to Tried with today's date.
4. The places and the visit show on Jon's iPhone and on Wendy's phone. Wendy marks the bar **Not for us**, and it
   leaves Jon's list.

## S3 — The map and its filters

**Goal:** The map and the check sheet become one screen over the same filtered places (ADR-0007 D5), and a tap on
the map can add a place.

Pinned now:
- On a regular width, the list sits beside the map. On a compact width, a **List | Map** control switches between
  them. A selected row and its pin stay in step.
- The filters are exactly ADR-0007 D5's: kind chips with Food first, a meal choice shown only while Food is on, and
  standing (To try, Tried, Everything, with Not for us under More). With a meal chosen, the list says how many food
  places have no meals set and offers to fill them in. Filters are device-local `@Shared(.appStorage)`, never synced.
- Tapping an Apple Maps point of interest explores before it adds (Galavant ADR-0044): Apple's detail shows, with
  an **Add place** action beside it. A long press drops a pin, which becomes a place with no `mapItemIdentifier`.
- Not for us places are never drawn unless the standing filter asks for them.

No schema. The architect merges on approve.

## S4 — Seasons

**Goal:** A place can be on always, every year, or once (ADR-0007 D10). Out-of-season places say when they're next
on, and Coming up warns before a to-try place's season ends. Branch `m4/s4-seasons`.

### Decisions pinned in this plan

- **No schema.** S2 created the five `when` columns and `Place.when`.
- **One pure season function**, `PlaceSeason`, in `BrightLightsSchema` beside `PlaceWhen`, because both Coming up
  (`WhatsOnProjection`) and the check sheet use it. Given a place's `when` and today (New York), it returns
  `.always`, `.inSeason(endsOn: Date?)`, `.outOfSeason(nextOn: Date)` or `.ended(on: Date)`. Every date is a New
  York start of day.
  - **Yearly:** today is in season when its month and day fall from `from` to `to`, inclusive. When `from` is after
    `to`, the season runs across New Year. `endsOn` is the next `to` on or after today, and `nextOn` is the next
    `from` after today. A Feb 29 bound means Feb 28 in other years.
  - **Once:** in season from `from` to `to`, inclusive. Before `from` it's out of season, next on `from`. After `to`
    it's `.ended(on: to)`.
- **The editor** gets a **When** section in place detail: Always, Every year or Once.
  - **Every year:** from and to, each a month picker and a day picker, with the day limited to that month's length
    (Feb allows 29).
  - **Once:** two date pickers in New York time, as in Log visit, with the end not before the start.
  - It saves through `updateDetails`, which takes `when` under the same changed-field rule as the other fields.
    When `when` is unchanged, all five columns stay as stored.
- **The check sheet and map:**
  - An out-of-season row says "Next on Nov 20", and an ended row says "Ended Mar 3", in New York time. An
    out-of-season or ended marker keeps its tint at half opacity.
  - `PlaceFilter` gains **Hide out of season**, a device-local toggle under More, off by default. It hides
    `.outOfSeason` and `.ended` places.
  - An ended `.once` place is left out of the **To try** standing filter whatever its standing. It still shows under
    Tried and Everything, and keeps its visits.
  - `PlaceCheckSheet` takes `today` and gives each row its `PlaceSeason`.
- **Coming up:**
  - The Deadlines section adds a row for each to-try place that's in season now and whose `endsOn` falls inside the
    same window as listings that close (today up to 60 days on). It reads "Ends Jan 5 — your last stay before it
    ends", and tapping it opens the place's detail.
  - The stays count comes from one function that both kinds of row call. Lift the count out of `makeDeadlines`
    into `WhatsOnProjection.staysBefore(_:stays:today:)`, and give `closingNote` the verb ("closes" or "ends").
    Nothing is copied.
  - `WhatsOnProjection.init` takes `places: [Place] = []`. The app passes the household's places, and
    `WhatsOnDeadlines` gains `ending: [(place: Place, endsOn: Date, staysBefore: Int)]`, sorted by `endsOn`, then
    name.

### Tests (package)

- `PlaceSeason`:
  - Always.
  - A yearly season inside one year: today before it, on its first day, inside it, on its last day, and after it.
  - A yearly season across New Year: Dec 31, Jan 1, and the next `from` after it ends.
  - A Feb 29 bound in a non-leap year.
  - Once: before it, inside it, on its last day, and after it.
- `updateDetails`: changing `when` writes the new case and clears the unused columns. An unchanged `when` leaves
  the stored columns alone, even when another device changed them meanwhile.
- `PlaceFilter`: Hide out of season hides out-of-season and ended places only. An ended `.once` to-try place is
  absent under To try and present under Everything.
- `PlaceCheckSheet`: a row carries its season.
- `WhatsOnProjection`:
  - A to-try yearly place ending inside the window is in `ending`, with the same stays count a listing closing that
    day gets.
  - Each of these is absent: a tried place, a place ending after the window, an out-of-season place, and an
    `.always` place.
  - The existing listing-closing tests still pass unchanged.

### Done when

- `scripts/check-drift.sh` passes, and CI is green.
- Closeout (ADR-0005 D16), with a device gate whose check is § S4 device pass, below.

**Not in S4:** offering in-season places to stays (S5), a season on the map's legend, and reminders.

### S4 device pass (Jon)

On the iPad, using places already added:
1. Set a park to Every year, Nov 20 to Jan 5. In late November or December it shows no "Next on". Coming up's
   Deadlines shows "Ends Jan 5", with the right stays count, and tapping it opens the park.
2. Set a bar to Every year, Jun 1 to Aug 31. It shows "Next on Jun 1", and More → Hide out of season hides it.
3. Set a shop to Once, with both dates last week. It leaves the To try filter, shows "Ended" under Everything, and
   its visits are still there.
4. On the iPhone, all three show the same When.

## S5 — The stay plan

**Goal:** Each stay has a plan with two parts, its days and This stay (ADR-0008 D1 to D6), and places can be pinned
to it.

Pinned now:
- Schema: `stayPlanItems`, as pinned above. Pinning a place that's already pinned to the stay updates the row.
  Deleting a place deletes its plan items in the same transaction, and a plan read skips any item whose place is
  missing.
- **The days** list booked listings at their times (read from reactions, never copied), then places put on that day,
  with their meal. **This stay** lists pinned places with no day, then **On only now**: to-try places whose season
  overlaps the stay and aren't pinned, each with when it ends and a one-tap pin.
- **Went** on a plan item opens S2's Log visit sheet with the item's day (or today) and meal.
- When a stay has ended, its plan offers "Didn't get to: …" with **Move to next stay**, which adds rows to the next
  stay and leaves the old ones.
- Stays → a stay opens its plan. On the iPad, While we're here gets a **Plan** button that opens the current stay's
  plan.
- Place detail gets **Add to stay**, which picks a stay (the current or next one by default), a day and a meal,
  all optional.

**Escalates:** schema and sync, so Jon merges, after the same `persistence-and-sync.md` steps for `stayPlanItems`.

## S6 — Errands from Reminders

**Goal:** Errands from one shared Reminders list show on the stay plan, can be ticked off there, and can be added
from it (ADR-0008 D7).

Pinned now:
- An `@Dependency` `RemindersClient` over EventKit, with full Reminders access, and a test value. The chosen list's
  identifier is device-local, `@Shared(.appStorage)`, and nothing from Reminders touches the database.
- Errands due inside a stay go on that day. Undated errands go under This stay, on the current stay, or on the next
  one when no stay is current, and never on more than one stay.
- Ticking an errand completes the reminder. **Quick add** creates one with a title and an optional due date. Opening
  an errand goes to Reminders.
- With no list chosen, or access declined, the plan shows one line offering to set it up. The Mac build never asks
  for Reminders.
- `NSRemindersFullAccessUsageDescription` goes in `project.yml`.

No schema. The architect merges on approve.

## Not in M4

- Opening hours, "open tonight", and filling meals from a place's website (`open-questions.md`).
- Progress by neighborhood, getting home, and places in chat access (`open-questions.md`).
- Galavant adopting `MapPlacesKit`, which is a Galavant dispatch.
- Calendar constraints and "when should we come next?", which are the next milestone's candidates.
