import CryptoKit
import Foundation
import SQLiteData

@Table
public struct StayPlanItem: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var stayID: Stay.ID
  public var placeID: Place.ID
  public var day: Date?
  public var meal: Meal?
  public var authorID: UUID?
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, stayID: UUID, placeID: UUID, day: Date? = nil, meal: Meal? = nil,
    authorID: UUID? = nil, createdAt: Date = .now, updatedAt: Date = .now
  ) {
    self.id = id
    self.stayID = stayID
    self.placeID = placeID
    self.day = day
    self.meal = meal
    self.authorID = authorID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static func id(stayID: UUID, placeID: UUID) -> UUID {
    let input = "\(stayID.uuidString)|\(placeID.uuidString)"
    var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }
}

public enum StayPlanOperations {
  @discardableResult
  public static func pin(
    placeID: UUID, to stayID: UUID, day: Date? = nil, meal: Meal? = nil,
    authorID: UUID? = nil, now: Date = .now, in db: Database
  ) throws -> StayPlanItem? {
    guard let stay = try Stay.find(stayID).fetchOne(db),
      let place = try Place.find(placeID).fetchOne(db), place.householdID == stay.householdID else { return nil }
    let id = StayPlanItem.id(stayID: stayID, placeID: placeID)
    let item = StayPlanItem(
      id: id, stayID: stayID, placeID: placeID,
      day: day.map { StayRules.normalized($0, calendar: Calendar(identifier: .gregorian)) },
      meal: meal, authorID: authorID, createdAt: try StayPlanItem.find(id).fetchOne(db)?.createdAt ?? now,
      updatedAt: now
    )
    try StayPlanItem.upsert { StayPlanItem.Draft(item) }.execute(db)
    return item
  }

  public static func remove(placeID: UUID, from stayID: UUID, in db: Database) throws {
    try StayPlanItem.find(StayPlanItem.id(stayID: stayID, placeID: placeID)).delete().execute(db)
  }

  @discardableResult
  public static func moveNotGotToNextStay(
    from stayID: UUID, visits: [PlaceVisit], authorID: UUID?, now: Date = .now, in db: Database
  ) throws -> Int {
    guard let stay = try Stay.find(stayID).fetchOne(db) else { return 0 }
    let calendar = Calendar.newYork
    let start = calendar.startOfDay(for: stay.arrivesOn)
    let end = calendar.startOfDay(for: StayRules.departureDate(stay.departure, arrival: start, calendar: calendar))
    let today = calendar.startOfDay(for: now)
    guard end < today,
      let next = try Stay.where({ $0.householdID.eq(stay.householdID) }).fetchAll(db)
        .filter({ calendar.startOfDay(for: $0.arrivesOn) > end })
        .sorted(by: { $0.arrivesOn < $1.arrivesOn }).first else { return 0 }
    let rows = try StayPlanItem.where { $0.stayID.eq(stayID) }.fetchAll(db)
    var moved = 0
    for row in rows {
      guard !visits.contains(where: {
        $0.placeID == row.placeID && calendar.startOfDay(for: $0.day) >= start && calendar.startOfDay(for: $0.day) <= end
      }),
        try Place.find(row.placeID).fetchOne(db) != nil else { continue }
      _ = try pin(placeID: row.placeID, to: next.id, meal: row.meal, authorID: authorID, now: now, in: db)
      moved += 1
    }
    return moved
  }
}

public struct StayPlanPlace: Identifiable, Sendable {
  public let item: StayPlanItem
  public let place: Place
  public let day: Date?
  public var id: UUID { item.id }
}

public struct StayPlanSeasonalOffer: Identifiable, Sendable {
  public let place: Place
  public let endsOn: Date?
  public var id: UUID { place.id }
}

public struct StayPlanDay: Identifiable, Sendable {
  public let date: Date
  public let bookings: [WhatsOnItem]
  public let places: [StayPlanPlace]
  public var id: Date { date }
}

public struct StayPlanProjection: Sendable {
  public let days: [StayPlanDay]
  public let thisStay: [StayPlanPlace]
  public let onOnlyNow: [StayPlanSeasonalOffer]
  public let didntGetTo: [StayPlanPlace]
  public let nextStay: Stay?
  public let isEnded: Bool

  public init(
    stay: Stay, stays: [Stay], places: [Place], planItems: [StayPlanItem], visits: [PlaceVisit],
    listings: [Listing], sources: [Source], reactions: [Reaction], now: Date, calendar: Calendar
  ) {
    var calendar = calendar
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let start = calendar.startOfDay(for: stay.arrivesOn)
    let end = calendar.startOfDay(for: StayRules.departureDate(stay.departure, arrival: start, calendar: calendar))
    let today = calendar.startOfDay(for: now)
    let sortedStays = stays.sorted { $0.arrivesOn < $1.arrivesOn }
    nextStay = sortedStays.first { calendar.startOfDay(for: $0.arrivesOn) > end }
    isEnded = end < today

    var reactionsByListing: [UUID: Reaction] = [:]
    for reaction in reactions {
      if let old = reactionsByListing[reaction.listingID],
        old.updatedAt > reaction.updatedAt ||
          (old.updatedAt == reaction.updatedAt && old.id.uuidString > reaction.id.uuidString) { continue }
      reactionsByListing[reaction.listingID] = reaction
    }
    let sourceNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let bookings = listings.compactMap { listing -> WhatsOnItem? in
      guard let reaction = reactionsByListing[listing.id], reaction.kind == .booked,
        listing.startsAt >= start, listing.startsAt < calendar.date(byAdding: .day, value: 1, to: end)!
      else { return nil }
      return WhatsOnItem(listing: listing, sourceName: sourceNames[listing.sourceID] ?? "Unknown venue", reaction: reaction, badge: nil)
    }

    let placeByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let rows = planItems.filter { $0.stayID == stay.id }.compactMap { item -> StayPlanPlace? in
      guard let place = placeByID[item.placeID] else { return nil }
      let day = item.day.map(calendar.startOfDay(for:))
      let validDay = day.flatMap { $0 >= start && $0 <= end ? $0 : nil }
      return StayPlanPlace(item: item, place: place, day: validDay)
    }
    let inStayVisits = visits.filter { $0.day >= start && $0.day < calendar.date(byAdding: .day, value: 1, to: end)! }
    let visitedIDs = Set(inStayVisits.map(\.placeID))
    thisStay = rows.filter { $0.day == nil }.sorted(by: Self.placeOrder)
    didntGetTo = isEnded ? rows.filter { !visitedIDs.contains($0.place.id) }.sorted(by: Self.placeOrder) : []

    var dayDates: [Date] = []
    var cursor = start
    while cursor <= end {
      dayDates.append(cursor)
      cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
    }
    let placesByDay = Dictionary(grouping: rows.filter { $0.day != nil }, by: { $0.day! })
    let bookingsByDay = Dictionary(grouping: bookings, by: { calendar.startOfDay(for: $0.listing.startsAt) })
    days = dayDates.map { date in
      StayPlanDay(
        date: date,
        bookings: (bookingsByDay[date] ?? []).sorted { $0.listing.startsAt < $1.listing.startsAt },
        places: (placesByDay[date] ?? []).sorted(by: Self.placeOrder)
      )
    }

    let pinnedIDs = Set(rows.map { $0.place.id })
    onOnlyNow = places.compactMap { place -> StayPlanSeasonalOffer? in
      guard !pinnedIDs.contains(place.id), case .toTry = place.standing, place.when != .always
      else { return nil }
      let endDate = Self.seasonEnd(place, from: start, through: end, calendar: calendar)
      return endDate.map { StayPlanSeasonalOffer(place: place, endsOn: $0) }
    }.sorted {
      if $0.endsOn != $1.endsOn { return ($0.endsOn ?? .distantFuture) < ($1.endsOn ?? .distantFuture) }
      return Self.nameOrder($0.place, $1.place)
    }
  }

  private static func seasonEnd(_ place: Place, from start: Date, through end: Date, calendar: Calendar) -> Date? {
    guard place.when != .always else { return nil }
    var day = start
    var lastEnd: Date?
    while day <= end {
      if case let .inSeason(endsOn) = PlaceSeason.resolve(place.when, today: day, calendar: calendar) {
        lastEnd = endsOn
      }
      day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return lastEnd
  }

  private static func placeOrder(_ lhs: StayPlanPlace, _ rhs: StayPlanPlace) -> Bool {
    if lhs.item.meal != rhs.item.meal { return (lhs.item.meal?.rawValue ?? "") < (rhs.item.meal?.rawValue ?? "") }
    return nameOrder(lhs.place, rhs.place)
  }

  private static func nameOrder(_ lhs: Place, _ rhs: Place) -> Bool {
    let order = lhs.name.localizedStandardCompare(rhs.name)
    return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
  }
}

private extension Calendar {
  static var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
}
