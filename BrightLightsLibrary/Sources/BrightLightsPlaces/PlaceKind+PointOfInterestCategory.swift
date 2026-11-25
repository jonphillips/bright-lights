import BrightLightsSchema

public extension PlaceKind {
  init(pointOfInterestCategory category: String?) {
    switch category {
    case "restaurant", "bakery", "foodMarket": self = .food
    case "cafe": self = .coffee
    case "nightlife", "brewery", "winery", "distillery": self = .drink
    case "park", "nationalPark", "beach": self = .park
    case "store": self = .shop
    case "museum", "landmark", "castle", "musicVenue", "theater", "planetarium",
      "aquarium", "zoo": self = .sight
    case "amusementPark", "bowling", "goKart", "miniGolf", "rockClimbing", "skating",
      "spa", "fitnessCenter", "stadium": self = .activity
    default: self = .other
    }
  }
}
