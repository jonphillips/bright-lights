import BrightLightsSchema
import Foundation

public struct PlaceFilter: Equatable, Sendable {
  public enum Kind: String, CaseIterable, Sendable {
    case all
    case food
    case drink
    case coffee
    case park
    case shop
    case sight
    case activity
    case other

    public static var allCases: [Self] { [.food, .all, .drink, .coffee, .park, .shop, .sight, .activity, .other] }

    public var placeKind: PlaceKind? { self == .all ? nil : PlaceKind(rawValue: rawValue) }
    public var title: String { self == .all ? "All" : rawValue.capitalized }
  }

  public enum MealChoice: String, CaseIterable, Sendable {
    case any
    case lunch
    case dinner
    case breakfast
    case lateNight

    public static var visibleCases: [Self] { [.any, .lunch, .dinner] }
    public static var moreCases: [Self] { [.breakfast, .lateNight] }
    public var meal: Meal? { self == .any ? nil : Meal(rawValue: rawValue) }
    public var title: String { self == .any ? "Any meal" : meal?.title ?? rawValue.capitalized }
  }

  public enum Standing: String, CaseIterable, Sendable {
    case toTry
    case tried
    case everything

    public var title: String {
      switch self {
      case .toTry: "To try"
      case .tried: "Tried"
      case .everything: "Everything"
      }
    }
  }

  public var kind: Kind
  public var meal: MealChoice
  public var standing: Standing
  public var includesNotForUs: Bool
  public var hidesOutOfSeason: Bool
  public var today: Date

  public init(
    kind: Kind = .all,
    meal: MealChoice = .any,
    standing: Standing = .everything,
    includesNotForUs: Bool = false,
    hidesOutOfSeason: Bool = false,
    today: Date = .now
  ) {
    self.kind = kind
    self.meal = meal
    self.standing = standing
    self.includesNotForUs = includesNotForUs
    self.hidesOutOfSeason = hidesOutOfSeason
    self.today = today
  }

  func includes(_ place: Place) -> Bool {
    let season = PlaceSeason.resolve(place.when, today: today)
    if hidesOutOfSeason, case .outOfSeason = season { return false }
    if hidesOutOfSeason, case .ended = season { return false }
    if standing == .toTry, case .ended = season, case .once = place.when { return false }
    guard kind.placeKind == nil || place.kind == kind.placeKind else { return false }
    if place.standing == .notForUs {
      return includesNotForUs
    }
    switch standing {
    case .toTry:
      guard case .toTry = place.standing else { return false }
    case .tried:
      guard case .tried = place.standing else { return false }
    case .everything:
      break
    }
    guard kind == .food, let meal = meal.meal else { return true }
    return place.kind == .food && place.meals.values.contains(meal)
  }
}
