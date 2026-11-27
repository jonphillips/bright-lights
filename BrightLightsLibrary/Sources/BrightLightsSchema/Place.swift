import Foundation
import Dependencies
import MapPlacesKit
import SQLiteData

public enum Priority: String, CaseIterable, Sendable {
  case high
  case normal
  case someday
}

public enum Verdict: String, CaseIterable, Sendable {
  case ourPlace
  case wouldReturn
  case onceWasEnough
}

public enum PlaceStanding: Equatable, Hashable, Sendable, RawRepresentable, QueryBindable {
  case toTry(Priority)
  case tried(Verdict?)
  case notForUs

  public init?(rawValue: String) {
    switch rawValue {
    case "toTry.high": self = .toTry(.high)
    case "toTry.normal": self = .toTry(.normal)
    case "toTry.someday": self = .toTry(.someday)
    case "tried": self = .tried(nil)
    case "tried.ourPlace": self = .tried(.ourPlace)
    case "tried.wouldReturn": self = .tried(.wouldReturn)
    case "tried.onceWasEnough": self = .tried(.onceWasEnough)
    case "notForUs": self = .notForUs
    default:
      reportIssue("Unknown place standing raw value \(rawValue); treating it as toTry.normal")
      self = .toTry(.normal)
    }
  }

  public var rawValue: String {
    switch self {
    case let .toTry(priority): "toTry.\(priority.rawValue)"
    case .tried(nil): "tried"
    case let .tried(.some(verdict)): "tried.\(verdict.rawValue)"
    case .notForUs: "notForUs"
    }
  }
}

public enum Meal: String, QueryBindable, CaseIterable, Sendable {
  case breakfast
  case lunch
  case dinner
  case lateNight

  public var title: String {
    switch self {
    case .breakfast: "Breakfast"
    case .lunch: "Lunch"
    case .dinner: "Dinner"
    case .lateNight: "Late night"
    }
  }
}

public struct Meals: Equatable, Sendable, RawRepresentable, QueryBindable {
  public var values: Set<Meal>

  public init(_ values: Set<Meal> = []) { self.values = values }
  public init(rawValue: String) {
    values = Set(rawValue.split(separator: ",").compactMap { Meal(rawValue: String($0)) })
  }
  public var rawValue: String {
    Meal.allCases.filter(values.contains).map(\.rawValue).joined(separator: ",")
  }
}

public struct MonthDay: Equatable, Sendable {
  public var month: Int
  public var day: Int

  public init(month: Int, day: Int) {
    self.month = month
    self.day = day
  }

  public var storageValue: Int { month * 100 + day }
  public init(storageValue: Int) {
    month = storageValue / 100
    day = storageValue % 100
  }
}

public enum PlaceWhen: Equatable, Sendable {
  case always
  case yearly(from: MonthDay, to: MonthDay)
  case once(from: Date, to: Date)
}

public enum PlaceWhenKind: String, QueryBindable, Equatable, Hashable, Sendable {
  case always
  case yearly
  case once
}

public enum PlaceSeason: Equatable, Sendable {
  case always
  case inSeason(endsOn: Date?)
  case outOfSeason(nextOn: Date)
  case ended(on: Date)

  public static func resolve(_ when: PlaceWhen, today: Date, calendar: Calendar = .current) -> Self {
    var calendar = calendar
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let today = calendar.startOfDay(for: today)
    switch when {
    case .always:
      return .always
    case let .once(from, to):
      let start = calendar.startOfDay(for: from)
      let end = calendar.startOfDay(for: to)
      if today < start { return .outOfSeason(nextOn: start) }
      if today <= end { return .inSeason(endsOn: end) }
      return .ended(on: end)
    case let .yearly(from, to):
      let year = calendar.component(.year, from: today)
      let startThisYear = date(from: from, year: year, calendar: calendar)
      let endThisYear = date(from: to, year: year, calendar: calendar)
      let crossesYear = from.month * 100 + from.day > to.month * 100 + to.day
      let inSeason: Bool
      if crossesYear {
        inSeason = today >= startThisYear || today <= endThisYear
      } else {
        inSeason = today >= startThisYear && today <= endThisYear
      }
      if inSeason {
        var end = endThisYear
        if crossesYear && today > endThisYear { end = date(from: to, year: year + 1, calendar: calendar) }
        return .inSeason(endsOn: end)
      }
      let nextStart = today < startThisYear ? startThisYear : date(from: from, year: year + 1, calendar: calendar)
      return .outOfSeason(nextOn: nextStart)
    }
  }

  private static func date(from monthDay: MonthDay, year: Int, calendar: Calendar) -> Date {
    let month = min(max(monthDay.month, 1), 12)
    let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    let lastDay = calendar.range(of: .day, in: .month, for: first)!.count
    return calendar.date(from: DateComponents(year: year, month: month, day: min(max(monthDay.day, 1), lastDay)))!
  }
}

@Table
public struct Place: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var name: String
  public var latitude: Double
  public var longitude: Double
  public var address: String?
  public var mapItemIdentifier: String?
  public var websiteURL: String?
  public var kind: PlaceKind
  public var meals: Meals
  public var standing: PlaceStanding
  public var authorID: UUID?
  public var note: String?
  public var whenKind: PlaceWhenKind
  public var seasonStart: Int?
  public var seasonEnd: Int?
  public var onceStart: Date?
  public var onceEnd: Date?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, householdID: UUID, name: String, latitude: Double, longitude: Double,
    address: String? = nil, mapItemIdentifier: String? = nil, websiteURL: String? = nil,
    kind: PlaceKind = .other, meals: Meals = Meals(), standing: PlaceStanding = .toTry(.normal),
    authorID: UUID? = nil, note: String? = nil, when: PlaceWhen = .always,
    createdAt: Date = .now, updatedAt: Date = .now
  ) {
    self.id = id; self.householdID = householdID; self.name = name
    self.latitude = latitude; self.longitude = longitude; self.address = address
    self.mapItemIdentifier = mapItemIdentifier; self.websiteURL = websiteURL
    self.kind = kind; self.meals = meals; self.standing = standing; self.authorID = authorID
    self.note = note; self.whenKind = .always; self.seasonStart = nil; self.seasonEnd = nil
    self.onceStart = nil; self.onceEnd = nil; self.createdAt = createdAt; self.updatedAt = updatedAt
    self.when = when
  }

  public var when: PlaceWhen {
    get {
      switch whenKind {
      case .yearly:
        guard let seasonStart, let seasonEnd else { return .always }
        return .yearly(from: MonthDay(storageValue: seasonStart), to: MonthDay(storageValue: seasonEnd))
      case .once:
        guard let onceStart, let onceEnd else { return .always }
        return .once(from: onceStart, to: onceEnd)
      case .always: return .always
      }
    }
    set {
      switch newValue {
      case .always:
        whenKind = .always; seasonStart = nil; seasonEnd = nil; onceStart = nil; onceEnd = nil
      case let .yearly(from, to):
        whenKind = .yearly; seasonStart = from.storageValue; seasonEnd = to.storageValue
        onceStart = nil; onceEnd = nil
      case let .once(from, to):
        whenKind = .once; onceStart = from; onceEnd = to
        seasonStart = nil; seasonEnd = nil
      }
    }
  }
}

@Table
public struct PlaceVisit: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var placeID: Place.ID
  public var day: Date
  public var meal: Meal?
  public var note: String?
  public var authorID: UUID?
  public var createdAt: Date

  public init(id: UUID, placeID: UUID, day: Date, meal: Meal? = nil, note: String? = nil,
    authorID: UUID? = nil, createdAt: Date = .now) {
    self.id = id; self.placeID = placeID; self.day = day; self.meal = meal
    self.note = note; self.authorID = authorID; self.createdAt = createdAt
  }
}

public enum PlaceOperations {
  public static func add(
    _ captured: MapPlace, kind: PlaceKind, householdID: UUID, now: Date = .now, id: UUID = UUID(), in db: Database
  ) throws -> Place {
    if let mapItemIdentifier = captured.mapItemIdentifier,
       let existing = try Place.where({ $0.mapItemIdentifier.eq(mapItemIdentifier) }).fetchAll(db)
      .filter({ $0.householdID == householdID }).sorted(by: { $0.id.uuidString < $1.id.uuidString }).first {
      return existing
    }
    let place = Place(
      id: id, householdID: householdID, name: captured.name, latitude: captured.latitude,
      longitude: captured.longitude, address: captured.address, mapItemIdentifier: captured.mapItemIdentifier,
      websiteURL: captured.url, kind: kind, createdAt: now, updatedAt: now
    )
    try Place.insert { Place.Draft(place) }.execute(db)
    return place
  }

  public static func setStanding(_ standing: PlaceStanding, authorID: UUID?, now: Date = .now,
    for placeID: UUID, in db: Database) throws {
    try Place.find(placeID).update {
      $0.standing = #bind(standing); $0.authorID = #bind(authorID); $0.updatedAt = #bind(now)
    }.execute(db)
  }

  public static func updateDetails(
    name: String, kind: PlaceKind, meals: Meals, address: String?, websiteURL: String?, note: String?, when: PlaceWhen,
    basedOn original: Place, updatedAt: Date, for placeID: UUID, in db: Database
  ) throws {
    guard let current = try Place.find(placeID).fetchOne(db) else { return }
    try Place.find(placeID).update {
      $0.name = #bind(name == original.name ? current.name : name)
      $0.kind = #bind(kind == original.kind ? current.kind : kind)
      $0.meals = #bind(meals == original.meals ? current.meals : meals)
      $0.address = #bind(address == original.address ? current.address : address)
      $0.websiteURL = #bind(websiteURL == original.websiteURL ? current.websiteURL : websiteURL)
      $0.note = #bind(note == original.note ? current.note : note)
      if when != original.when {
        $0.whenKind = #bind(when.kind)
        $0.seasonStart = #bind(when.seasonStart)
        $0.seasonEnd = #bind(when.seasonEnd)
        $0.onceStart = #bind(when.onceStart)
        $0.onceEnd = #bind(when.onceEnd)
      } else {
        $0.whenKind = #bind(current.whenKind)
        $0.seasonStart = #bind(current.seasonStart)
        $0.seasonEnd = #bind(current.seasonEnd)
        $0.onceStart = #bind(current.onceStart)
        $0.onceEnd = #bind(current.onceEnd)
      }
      $0.updatedAt = #bind(updatedAt)
    }.execute(db)
  }

  public static func logVisit(_ visit: PlaceVisit, verdict: Verdict? = nil, in db: Database) throws {
    guard let place = try Place.find(visit.placeID).fetchOne(db) else { return }
    let normalizedVisit = PlaceVisit(
      id: visit.id, placeID: visit.placeID,
      day: StayRules.normalized(visit.day, calendar: Calendar(identifier: .gregorian)),
      meal: visit.meal, note: visit.note, authorID: visit.authorID, createdAt: visit.createdAt
    )
    try PlaceVisit.insert { PlaceVisit.Draft(normalizedVisit) }.execute(db)
    if case .toTry = place.standing {
      try setStanding(.tried(verdict), authorID: visit.authorID, now: visit.createdAt, for: place.id, in: db)
    }
  }

  public static func deleteVisit(_ id: UUID, in db: Database) throws {
    try PlaceVisit.find(id).delete().execute(db)
  }

  public static func deletePlace(_ id: UUID, in db: Database) throws {
    try Place.find(id).delete().execute(db)
  }
}

private extension PlaceWhen {
  var kind: PlaceWhenKind {
    switch self { case .always: .always; case .yearly: .yearly; case .once: .once }
  }
  var seasonStart: Int? { if case let .yearly(from, _) = self { from.storageValue } else { nil } }
  var seasonEnd: Int? { if case let .yearly(_, to) = self { to.storageValue } else { nil } }
  var onceStart: Date? { if case let .once(from, _) = self { from } else { nil } }
  var onceEnd: Date? { if case let .once(_, to) = self { to } else { nil } }
}
