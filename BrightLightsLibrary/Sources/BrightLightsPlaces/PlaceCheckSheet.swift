import BrightLightsSchema
import Foundation

public struct PlaceCheckSheet: Equatable, Sendable {
  public struct Row: Identifiable, Equatable, Sendable {
    public var place: Place
    public var lastVisit: Date?
    public var season: PlaceSeason
    public var id: UUID { place.id }
  }

  public struct Group: Identifiable, Equatable, Sendable {
    public var title: String
    public var rows: [Row]
    public var id: String { title }
  }

  public var groups: [Group]
  public var filteredPlaces: [Place]
  public var placesMissingMeals: [Place]
  public var missingMealsCount: Int

  public init(places: [Place], visits: [PlaceVisit], filter: PlaceFilter = PlaceFilter(), today: Date = .now) {
    let filteredPlaces = places.filter(filter.includes)
    self.filteredPlaces = filteredPlaces
    let mealIndependentFilter = PlaceFilter(
      kind: filter.kind, meal: .any, standing: filter.standing, includesNotForUs: filter.includesNotForUs,
      hidesOutOfSeason: filter.hidesOutOfSeason, today: filter.today
    )
    let placesMissingMeals = places.filter(mealIndependentFilter.includes)
      .filter { $0.kind == .food && $0.meals.values.isEmpty }
    self.placesMissingMeals = placesMissingMeals
    missingMealsCount = filter.kind == .food && filter.meal != .any ? placesMissingMeals.count : 0
    let lastVisits = Dictionary(grouping: visits, by: \.placeID).mapValues { $0.map(\.day).max() }
    let priorities: [(title: String, matches: (Place) -> Bool)] = [
      ("High priority", { if case .toTry(.high) = $0.standing { true } else { false } }),
      ("To try", { if case .toTry(.normal) = $0.standing { true } else { false } }),
      ("Someday", { if case .toTry(.someday) = $0.standing { true } else { false } }),
      ("Our place", { if case .tried(.ourPlace) = $0.standing { true } else { false } }),
      ("Would return", { if case .tried(.wouldReturn) = $0.standing { true } else { false } }),
      ("Tried", { if case .tried(nil) = $0.standing { true } else { false } }),
      ("Once was enough", { if case .tried(.onceWasEnough) = $0.standing { true } else { false } }),
      ("Not for us", { $0.standing == .notForUs })
    ]
    groups = priorities.compactMap { title, matches in
      let rows = filteredPlaces.filter(matches).sorted {
        let order = $0.name.localizedStandardCompare($1.name)
        return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
      }.map { Row(place: $0, lastVisit: lastVisits[$0.id] ?? nil, season: PlaceSeason.resolve($0.when, today: today)) }
      return rows.isEmpty ? nil : Group(title: title, rows: rows)
    }
  }
}

public extension PlaceKind {
  var symbol: String {
    switch self {
    case .food: "fork.knife"
    case .drink: "wineglass"
    case .coffee: "cup.and.saucer"
    case .park: "tree"
    case .shop: "bag"
    case .sight: "eye"
    case .activity: "figure.walk"
    case .other: "mappin.and.ellipse"
    }
  }
}
