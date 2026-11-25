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
    let high = Place(id: UUID(), householdID: householdID, name: "High", latitude: 0, longitude: 0,
      standing: .toTry(.high))
    let ourPlace = Place(id: UUID(), householdID: householdID, name: "Favorite", latitude: 0, longitude: 0,
      standing: .tried(.ourPlace))
    let hidden = Place(id: UUID(), householdID: householdID, name: "Hidden", latitude: 0, longitude: 0,
      standing: .notForUs)
    let lastVisit = Date(timeIntervalSince1970: 1_800_000_000)
    let projection = PlaceCheckSheet(
      places: [ourPlace, hidden, high], visits: [PlaceVisit(id: UUID(), placeID: ourPlace.id, day: lastVisit)]
    )
    #expect(projection.groups.map(\.title) == ["High priority", "Our place"])
    #expect(projection.groups[0].rows.first?.place.id == high.id)
    #expect(projection.groups[1].rows.first?.lastVisit == lastVisit)
    #expect(PlaceCheckSheet(places: [hidden], visits: []).groups.map(\.title) == [])
    #expect(PlaceCheckSheet(places: [hidden], visits: [], showingNotForUs: true).groups.map(\.title) == ["Not for us"])
  }
}
