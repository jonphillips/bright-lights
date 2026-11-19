import Foundation

public enum WhatsOnFilter: String, CaseIterable, Hashable, Sendable {
  case all
  case interestedAndBooked
  case booked

  public var title: String {
    switch self {
    case .all: "All"
    case .interestedAndBooked: "Interested & booked"
    case .booked: "Booked"
    }
  }
}

public struct WhatsOnItem: Identifiable, Sendable {
  public let listing: Listing
  public let sourceName: String
  public let reaction: Reaction?
  public let badge: String?
  public var id: Listing.ID { listing.id }

  public init(listing: Listing, sourceName: String, reaction: Reaction?, badge: String?) {
    self.listing = listing
    self.sourceName = sourceName
    self.reaction = reaction
    self.badge = badge
  }
}

public struct WhatsOnDay: Identifiable, Sendable {
  public let date: Date
  public let items: [WhatsOnItem]
  public var id: Date { date }

  public init(date: Date, items: [WhatsOnItem]) {
    self.date = date
    self.items = items
  }
}

public struct WhatsOnStayGroup: Identifiable, Sendable {
  public let stay: Stay?
  public let title: String
  public let note: String?
  public let days: [WhatsOnDay]
  public let running: [WhatsOnItem]
  public var id: String { stay?.id.uuidString ?? title }

  public init(stay: Stay?, title: String, note: String?, days: [WhatsOnDay], running: [WhatsOnItem]) {
    self.stay = stay
    self.title = title
    self.note = note
    self.days = days
    self.running = running
  }
}

public struct WhatsOnDeadlines: Sendable {
  public let onSale: [WhatsOnItem]
  public let closing: [(item: WhatsOnItem, staysBeforeClose: Int)]
}

/// A view-ready, non-persisted projection of listings against the household's stays.
public struct WhatsOnProjection: Sendable {
  public let currentStay: Stay?
  public let nextStay: Stay?
  public let whileHere: WhatsOnStayGroup?
  public let comingUp: [WhatsOnStayGroup]
  public let deadlines: WhatsOnDeadlines
  public let passedCount: Int

  public init(
    listings: [Listing], sources: [Source], stays: [Stay], reactions: [Reaction],
    now: Date, calendar: Calendar
  ) {
    var calendar = calendar
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let today = calendar.startOfDay(for: now)
    let sortedStays = stays.sorted {
      if $0.arrivesOn != $1.arrivesOn { return $0.arrivesOn < $1.arrivesOn }
      return $0.id.uuidString < $1.id.uuidString
    }
    let current = sortedStays.first {
      $0.arrivesOn <= today && Self.endDate($0, calendar: calendar) >= today
    }
    let next = sortedStays.first { $0.arrivesOn > today }
    currentStay = current
    nextStay = next
    let allItems = Self.items(listings: listings, sources: sources, reactions: reactions)
    let visible = Self.visibleItems(allItems, now: now, calendar: calendar)
    passedCount = allItems.filter { $0.reaction?.kind == .pass && Self.isOn($0.listing, at: now, calendar: calendar) }.count
    whileHere = Self.whileHereGroup(visible, stay: current, now: now, today: today, calendar: calendar)
    let windowEnd = calendar.date(byAdding: .day, value: 60, to: today)!
    let futureStays = sortedStays.filter { $0.arrivesOn <= windowEnd && Self.endDate($0, calendar: calendar) >= today }
    comingUp = Self.comingUpGroups(visible, stays: futureStays, current: current, today: today, windowEnd: windowEnd, calendar: calendar)
    let deadlineItems = allItems.filter { $0.reaction?.kind != .pass }
    deadlines = Self.makeDeadlines(deadlineItems, stays: sortedStays, now: now, today: today, windowEnd: windowEnd, calendar: calendar)
  }

  private static func items(listings: [Listing], sources: [Source], reactions: [Reaction]) -> [WhatsOnItem] {
    var latestReaction: [Listing.ID: Reaction] = [:]
    for reaction in reactions {
      if let existing = latestReaction[reaction.listingID],
        existing.updatedAt > reaction.updatedAt ||
          (existing.updatedAt == reaction.updatedAt && existing.id.uuidString > reaction.id.uuidString) { continue }
      latestReaction[reaction.listingID] = reaction
    }
    let sourceNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    return listings.map { listing in
      let reaction = latestReaction[listing.id]
      let badge: String?
      switch listing.status {
      case .listed: badge = nil
      case .soldOut: badge = "Sold out"
      case .cancelled: badge = reaction == nil ? nil : "Cancelled"
      case .missing: badge = reaction == nil ? nil : "No longer listed"
      }
      return WhatsOnItem(listing: listing, sourceName: sourceNames[listing.sourceID] ?? "Unknown venue", reaction: reaction, badge: badge)
    }
  }

  private static func visibleItems(_ items: [WhatsOnItem], now: Date, calendar: Calendar) -> [WhatsOnItem] {
    items.filter { item in
      guard item.listing.status == .listed || item.listing.status == .soldOut || item.reaction != nil else { return false }
      guard item.reaction?.kind != .pass else { return false }
      return isOn(item.listing, at: now, calendar: calendar)
    }.sorted(by: itemOrder)
  }

  private static func whileHereGroup(_ items: [WhatsOnItem], stay: Stay?, now: Date, today: Date, calendar: Calendar) -> WhatsOnStayGroup? {
    guard let stay else { return nil }
    let end = endDate(stay, calendar: calendar)
    let displayEnd = stay.departureKind == .booked ? end : calendar.date(byAdding: .day, value: 1, to: end)!
    let afterDisplayEnd = calendar.date(byAdding: .day, value: 1, to: displayEnd)!
    let justStarted = now.addingTimeInterval(-2 * 60 * 60)
    let days = dayGroups(items.filter { $0.listing.closesAt == nil && $0.listing.startsAt >= justStarted && $0.listing.startsAt < afterDisplayEnd }, calendar: calendar)
    let running = items.filter { item in
      guard let close = item.listing.closesAt else { return false }
      return item.listing.startsAt < afterDisplayEnd && close >= today
    }
    return WhatsOnStayGroup(stay: stay, title: "While we're here", note: nil, days: days, running: running)
  }

  private static func comingUpGroups(_ visible: [WhatsOnItem], stays: [Stay], current: Stay?, today: Date, windowEnd: Date, calendar: Calendar) -> [WhatsOnStayGroup] {
    let coming = visible.filter { item in
      item.listing.startsAt < windowEnd && (item.listing.startsAt >= today || (item.listing.closesAt.map { $0 >= today } ?? false))
    }
    guard !stays.isEmpty else { return weekGroups(coming, today: today, calendar: calendar, note: "Add your next stay to narrow this") }
    return stays.map { stay in
      let start = stay.id == current?.id ? calendar.date(byAdding: .day, value: 1, to: today)! : max(stay.arrivesOn, today)
      let end = endDate(stay, calendar: calendar)
      let group = coming.filter { item in
        guard item.listing.startsAt <= end else { return false }
        return item.listing.closesAt.map { $0 >= start } ?? (item.listing.startsAt >= start)
      }
      return WhatsOnStayGroup(stay: stay, title: stayTitle(stay, calendar: calendar), note: stay.departureKind == .booked ? nil : stay.departureKind.rawValue.capitalized, days: dayGroups(group.filter { $0.listing.closesAt == nil }, calendar: calendar), running: group.filter { $0.listing.closesAt != nil })
    }
  }

  private static func makeDeadlines(_ items: [WhatsOnItem], stays: [Stay], now: Date, today: Date, windowEnd: Date, calendar: Calendar) -> WhatsOnDeadlines {
    let saleEnd = calendar.date(byAdding: .day, value: 14, to: now)!
    let onSale = items.filter { item in
      guard let date = item.listing.onSaleAt else { return false }
      return date >= now && date < saleEnd
    }.sorted { ($0.listing.onSaleAt ?? .distantFuture) < ($1.listing.onSaleAt ?? .distantFuture) }
    let closing = items.compactMap { item -> (WhatsOnItem, Int)? in
      guard let close = item.listing.closesAt, close >= today, close < windowEnd else { return nil }
      let count = stays.filter { $0.arrivesOn > today && $0.arrivesOn <= close }.count
      return (item, count)
    }.sorted { ($0.0.listing.closesAt ?? .distantFuture) < ($1.0.listing.closesAt ?? .distantFuture) }
    return WhatsOnDeadlines(onSale: onSale, closing: closing)
  }

  public func filtered(_ items: [WhatsOnItem], by filter: WhatsOnFilter) -> [WhatsOnItem] {
    items.filter { item in
      switch filter {
      case .all: true
      case .interestedAndBooked: item.reaction?.kind == .interested || item.reaction?.kind == .booked
      case .booked: item.reaction?.kind == .booked
      }
    }
  }

  private static func endDate(_ stay: Stay, calendar: Calendar) -> Date {
    let date: Date
    switch stay.departure {
    case let .booked(value), let .tentative(value): date = value
    case .open: date = calendar.date(byAdding: .day, value: 7, to: stay.arrivesOn)!
    }
    return calendar.startOfDay(for: date)
  }

  private static func isOn(_ listing: Listing, at now: Date, calendar: Calendar) -> Bool {
    if let closes = listing.closesAt {
      return calendar.startOfDay(for: listing.startsAt) <= calendar.startOfDay(for: now)
        ? closes >= calendar.startOfDay(for: now)
        : listing.startsAt <= now
    }
    return listing.startsAt >= now.addingTimeInterval(-2 * 60 * 60)
  }

  private static func itemOrder(_ lhs: WhatsOnItem, _ rhs: WhatsOnItem) -> Bool {
    if lhs.listing.startsAt != rhs.listing.startsAt { return lhs.listing.startsAt < rhs.listing.startsAt }
    if lhs.sourceName != rhs.sourceName { return lhs.sourceName < rhs.sourceName }
    return lhs.listing.id.uuidString < rhs.listing.id.uuidString
  }

  private static func dayGroups(_ items: [WhatsOnItem], calendar: Calendar) -> [WhatsOnDay] {
    Dictionary(grouping: items) { calendar.startOfDay(for: $0.listing.startsAt) }
      .map { WhatsOnDay(date: $0.key, items: $0.value.sorted(by: itemOrder)) }
      .sorted { $0.date < $1.date }
  }

  private static func weekGroups(_ items: [WhatsOnItem], today: Date, calendar: Calendar, note: String?) -> [WhatsOnStayGroup] {
    Dictionary(grouping: items) { item -> Date in
      let date = max(today, calendar.startOfDay(for: item.listing.startsAt))
      return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }.keys.sorted().map { start in
      let end = calendar.date(byAdding: .day, value: 7, to: start)!
      let groupItems = items.filter {
        let date = max(today, calendar.startOfDay(for: $0.listing.startsAt))
        return date >= start && date < end
      }
      return WhatsOnStayGroup(stay: nil, title: monthDay(start, calendar: calendar) + "–" + dayOfMonth(end.addingTimeInterval(-1), calendar: calendar), note: note, days: dayGroups(groupItems, calendar: calendar), running: [])
    }
  }

  private static func stayTitle(_ stay: Stay, calendar: Calendar) -> String {
    let end = endDate(stay, calendar: calendar)
    let from = monthDay(stay.arrivesOn, calendar: calendar)
    let to = dayOfMonth(end, calendar: calendar)
    return "\(from)–\(to)"
  }

  private static func monthDay(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
  }

  private static func dayOfMonth(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "d"
    return formatter.string(from: date)
  }
}
