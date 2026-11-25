import BrightLightsSchema

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

  public init(
    kind: Kind = .all,
    meal: MealChoice = .any,
    standing: Standing = .everything,
    includesNotForUs: Bool = false
  ) {
    self.kind = kind
    self.meal = meal
    self.standing = standing
    self.includesNotForUs = includesNotForUs
  }

  func includes(_ place: Place) -> Bool {
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
