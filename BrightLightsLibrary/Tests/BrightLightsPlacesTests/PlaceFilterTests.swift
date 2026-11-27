import BrightLightsPlaces
import BrightLightsSchema
import Foundation
import Foundation
import Testing

@Suite struct PlaceFilterTests {
  private let householdID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

  @Test func eachKindFiltersPlacesAndAllKeepsEveryKind() {
    let places = PlaceKind.allCases.map { kind in
      makePlace(name: kind.rawValue, kind: kind)
    }

    for kind in PlaceFilter.Kind.allCases {
      let result = PlaceCheckSheet(
        places: places, visits: [], filter: PlaceFilter(kind: kind)
      ).filteredPlaces
      let expected = kind.placeKind.map { placeKind in
        Set(places.filter { $0.kind == placeKind }.map(\.id))
      } ?? Set(places.map(\.id))
      #expect(Set(result.map(\.id)) == expected)
    }
  }

  @Test func mealChoiceKeepsOnlyFoodPlacesMarkedWithThatMeal() {
    let lunchPlace = makePlace(name: "Lunch", kind: .food, meals: [.lunch])
    let dinnerPlace = makePlace(name: "Dinner", kind: .food, meals: [.dinner])
    let unmarkedFood = makePlace(name: "Unmarked", kind: .food)
    let drink = makePlace(name: "Drink", kind: .drink, meals: [.lunch])
    let projection = PlaceCheckSheet(
      places: [lunchPlace, dinnerPlace, unmarkedFood, drink], visits: [],
      filter: PlaceFilter(kind: .food, meal: .lunch)
    )

    #expect(projection.filteredPlaces.map(\.id) == [lunchPlace.id])
  }

  @Test func mealChoiceIsIgnoredUnderOtherKindsAndAll() {
    let food = makePlace(name: "Food", kind: .food)
    let drink = makePlace(name: "Drink", kind: .drink)
    let park = makePlace(name: "Park", kind: .park)
    let places = [food, drink, park]

    let drinks = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(kind: .drink, meal: .lunch)
    )
    let all = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(kind: .all, meal: .lunch)
    )

    #expect(drinks.filteredPlaces.map(\.id) == [drink.id])
    #expect(Set(all.filteredPlaces.map(\.id)) == Set(places.map(\.id)))
  }

  @Test func standingChoicesFilterOrdinaryPlaces() {
    let toTry = makePlace(name: "To try", standing: .toTry(.high))
    let tried = makePlace(name: "Tried", standing: .tried(.ourPlace))
    let notForUs = makePlace(name: "Not for us", standing: .notForUs)
    let places = [toTry, tried, notForUs]

    let toTryProjection = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(standing: .toTry)
    )
    let triedProjection = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(standing: .tried)
    )
    let everythingProjection = PlaceCheckSheet(places: places, visits: [])

    #expect(toTryProjection.filteredPlaces.map(\.id) == [toTry.id])
    #expect(triedProjection.filteredPlaces.map(\.id) == [tried.id])
    #expect(Set(everythingProjection.filteredPlaces.map(\.id)) == Set([toTry.id, tried.id]))
  }

  @Test func notForUsCanBeAddedUnderEveryStandingChoice() {
    let ordinary = makePlace(name: "Ordinary", standing: .toTry(.normal))
    let notForUs = makePlace(name: "Not for us", standing: .notForUs)

    for standing in PlaceFilter.Standing.allCases {
      let hidden = PlaceCheckSheet(
        places: [ordinary, notForUs], visits: [], filter: PlaceFilter(standing: standing)
      )
      let shown = PlaceCheckSheet(
        places: [ordinary, notForUs], visits: [],
        filter: PlaceFilter(standing: standing, includesNotForUs: true)
      )
      #expect(!hidden.filteredPlaces.contains { $0.id == notForUs.id })
      #expect(shown.filteredPlaces.contains { $0.id == notForUs.id })
    }
  }

  @Test func missingMealsCountFollowsFoodAndStandingFilters() {
    let toTryMissing = makePlace(name: "To try missing", kind: .food, standing: .toTry(.normal))
    let toTrySet = makePlace(name: "To try set", kind: .food, standing: .toTry(.normal), meals: [.lunch])
    let triedMissing = makePlace(name: "Tried missing", kind: .food, standing: .tried(nil))
    let notForUsMissing = makePlace(name: "Not for us missing", kind: .food, standing: .notForUs)
    let drinkMissing = makePlace(name: "Drink missing", kind: .drink)
    let places = [toTryMissing, toTrySet, triedMissing, notForUsMissing, drinkMissing]

    func count(_ filter: PlaceFilter) -> Int {
      PlaceCheckSheet(places: places, visits: [], filter: filter).missingMealsCount
    }

    #expect(count(PlaceFilter(kind: .food, meal: .lunch, standing: .toTry)) == 1)
    #expect(count(PlaceFilter(kind: .food, meal: .dinner, standing: .tried)) == 1)
    #expect(count(PlaceFilter(kind: .food, meal: .lunch, standing: .everything)) == 2)
    #expect(count(PlaceFilter(kind: .food, meal: .lunch, standing: .everything, includesNotForUs: true)) == 3)
    #expect(count(PlaceFilter(kind: .drink, meal: .lunch)) == 0)
    #expect(count(PlaceFilter(kind: .all, meal: .lunch)) == 0)
    #expect(count(PlaceFilter(kind: .food, meal: .any)) == 0)
  }

  @Test func outOfSeasonToggleAndEndedOnceStandingRules() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let today = calendar.date(from: DateComponents(year: 2027, month: 3, day: 10))!
    let summer = makePlace(name: "Summer", standing: .toTry(.normal))
    var summerPlace = summer
    summerPlace.when = .yearly(from: MonthDay(month: 6, day: 1), to: MonthDay(month: 8, day: 31))
    let ended = makePlace(name: "Ended", standing: .toTry(.high))
    var endedPlace = ended
    endedPlace.when = .once(from: calendar.date(byAdding: .day, value: -5, to: today)!, to: calendar.date(byAdding: .day, value: -2, to: today)!)
    let places = [summerPlace, endedPlace]

    let ordinary = PlaceCheckSheet(places: places, visits: [], filter: PlaceFilter(today: today), today: today)
    let toTry = PlaceCheckSheet(places: places, visits: [], filter: PlaceFilter(standing: .toTry, today: today), today: today)
    let hidden = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(hidesOutOfSeason: true, today: today), today: today
    )
    #expect(Set(ordinary.filteredPlaces.map(\.id)) == Set(places.map(\.id)))
    #expect(toTry.filteredPlaces.map(\.id) == [summerPlace.id])
    #expect(hidden.filteredPlaces.isEmpty)
    #expect(ordinary.groups.flatMap(\.rows).first(where: { $0.place.id == summerPlace.id })?.season
      == .outOfSeason(nextOn: calendar.date(from: DateComponents(year: 2027, month: 6, day: 1))!))
  }

  private func makePlace(
    name: String,
    kind: PlaceKind = .food,
    standing: PlaceStanding = .toTry(.normal),
    meals: Set<Meal> = []
  ) -> Place {
    Place(
      id: UUID(), householdID: householdID, name: name,
      latitude: 40.7, longitude: -73.9, kind: kind, meals: Meals(meals), standing: standing
    )
  }
}
