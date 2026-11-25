import BrightLightsSchema
import MapKit

public extension PlaceKind {
  /// Maps the raw `MKPointOfInterestCategory` value `MapPlace` carries (`MKPOICategoryRestaurant`, not
  /// `restaurant`), so the cases are matched through the SDK's own constants.
  init(pointOfInterestCategory rawValue: String?) {
    guard let rawValue else {
      self = .other
      return
    }
    switch MKPointOfInterestCategory(rawValue: rawValue) {
    case .restaurant, .bakery, .foodMarket: self = .food
    case .cafe: self = .coffee
    case .nightlife, .brewery, .winery, .distillery: self = .drink
    case .park, .nationalPark, .beach: self = .park
    case .store: self = .shop
    case .museum, .landmark, .castle, .musicVenue, .theater, .planetarium, .aquarium, .zoo: self = .sight
    case .amusementPark, .bowling, .goKart, .miniGolf, .rockClimbing, .skating, .spa, .fitnessCenter, .stadium:
      self = .activity
    default: self = .other
    }
  }
}
