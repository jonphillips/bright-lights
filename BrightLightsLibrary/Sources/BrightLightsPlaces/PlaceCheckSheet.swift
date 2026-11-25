import BrightLightsSchema
import Foundation

public struct PlaceCheckSheet: Equatable, Sendable {
  public struct Row: Identifiable, Equatable, Sendable {
    public var place: Place
    public var lastVisit: Date?
    public var id: UUID { place.id }
  }

  public struct Group: Identifiable, Equatable, Sendable {
    public var title: String
    public var rows: [Row]
    public var id: String { title }
  }

  public var groups: [Group]

  public init(places: [Place], visits: [PlaceVisit], showingNotForUs: Bool = false) {
    let lastVisits = Dictionary(grouping: visits, by: \.placeID).mapValues { $0.map(\.day).max() }
    let shown = places.filter { showingNotForUs || $0.standing != .notForUs }
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
      let rows = shown.filter(matches).sorted {
        let order = $0.name.localizedStandardCompare($1.name)
        return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
      }.map { Row(place: $0, lastVisit: lastVisits[$0.id] ?? nil) }
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
