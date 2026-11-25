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
}
