import BrightLightsPlaces
import BrightLightsSchema
import MapKit
import Testing

@Suite struct PlaceKindTests {
  @Test func mapsMapKitCategoriesToPlaceKinds() {
    let cases: [(category: MKPointOfInterestCategory, kind: PlaceKind)] = [
      (.restaurant, .food),
      (.bakery, .food),
      (.foodMarket, .food),
      (.cafe, .coffee),
      (.nightlife, .drink),
      (.brewery, .drink),
      (.winery, .drink),
      (.distillery, .drink),
      (.park, .park),
      (.nationalPark, .park),
      (.beach, .park),
      (.store, .shop),
      (.museum, .sight),
      (.landmark, .sight),
      (.castle, .sight),
      (.musicVenue, .sight),
      (.theater, .sight),
      (.planetarium, .sight),
      (.aquarium, .sight),
      (.zoo, .sight),
      (.amusementPark, .activity),
      (.bowling, .activity),
      (.goKart, .activity),
      (.miniGolf, .activity),
      (.rockClimbing, .activity),
      (.skating, .activity),
      (.spa, .activity),
      (.fitnessCenter, .activity),
      (.stadium, .activity)
    ]

    for (category, kind) in cases {
      #expect(PlaceKind(pointOfInterestCategory: category.rawValue) == kind)
    }
  }

  @Test func unknownAndMissingCategoriesMapToOther() {
    #expect(PlaceKind(pointOfInterestCategory: nil) == .other)
    #expect(PlaceKind(pointOfInterestCategory: MKPointOfInterestCategory.hotel.rawValue) == .other)
    #expect(PlaceKind(pointOfInterestCategory: "MKPOICategoryFutureCategory") == .other)
  }

  @Test func checkSheetGroupsByStandingAndShowsLastVisitOnlyInTriedGroups() {
    let householdID = UUID()
    let groups: [(PlaceStanding, String)] = [
      (.toTry(.high), "High"), (.toTry(.normal), "Normal"), (.toTry(.someday), "Someday"),
      (.tried(.ourPlace), "Our place"), (.tried(.wouldReturn), "Would return"),
      (.tried(nil), "Tried"), (.tried(.onceWasEnough), "Once was enough"), (.notForUs, "Not for us")
    ]
    let places = groups.flatMap { standing, prefix in
      [
        Place(id: UUID(), householdID: householdID, name: "Zulu \(prefix)", latitude: 0, longitude: 0, standing: standing),
        Place(id: UUID(), householdID: householdID, name: "Alpha \(prefix)", latitude: 0, longitude: 0, standing: standing)
      ]
    }
    let ourPlace = places.first { $0.standing == .tried(.ourPlace) }!
    let lastVisit = Date(timeIntervalSince1970: 1_800_000_000)
    let projection = PlaceCheckSheet(
      places: places, visits: [PlaceVisit(id: UUID(), placeID: ourPlace.id, day: lastVisit)]
    )
    let expectedTitles = ["High priority", "To try", "Someday", "Our place", "Would return", "Tried", "Once was enough"]
    #expect(projection.groups.map(\.title) == expectedTitles)
    #expect(projection.groups.first?.rows.map(\.place.name) == ["Alpha High", "Zulu High"])
    #expect(projection.groups.first { $0.title == "Our place" }?.rows.first { $0.place.id == ourPlace.id }?.lastVisit == lastVisit)
    let showingNotForUs = PlaceCheckSheet(
      places: places, visits: [], filter: PlaceFilter(includesNotForUs: true)
    )
    #expect(showingNotForUs.groups.map(\.title) == expectedTitles + ["Not for us"])
    #expect(showingNotForUs.groups.last?.rows.map(\.place.name) == ["Alpha Not for us", "Zulu Not for us"])
  }
}
