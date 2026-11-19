import Foundation

public enum StayValidationError: Error, Equatable, Sendable {
  case departureBeforeArrival
  case overlaps(Stay.ID)
}

/// Pure date and overlap rules for stay edits.
public enum StayRules {
  public static func normalized(_ date: Date, calendar: Calendar) -> Date {
    var newYork = calendar
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    return newYork.startOfDay(for: date)
  }

  public static func validate(
    arrival: Date,
    departure: StayDeparture,
    editing stayID: Stay.ID? = nil,
    against stays: [Stay],
    calendar: Calendar
  ) throws {
    let arrival = normalized(arrival, calendar: calendar)
    let end = normalized(departureDate(departure, arrival: arrival, calendar: calendar), calendar: calendar)
    guard end >= arrival else { throw StayValidationError.departureBeforeArrival }

    for stay in stays where stay.id != stayID {
      let otherStart = normalized(stay.arrivesOn, calendar: calendar)
      let otherEnd = normalized(departureDate(stay.departure, arrival: otherStart, calendar: calendar), calendar: calendar)
      if arrival <= otherEnd && otherStart <= end { throw StayValidationError.overlaps(stay.id) }
    }
  }

  public static func departureDate(_ departure: StayDeparture, arrival: Date, calendar: Calendar) -> Date {
    switch departure {
    case let .booked(date), let .tentative(date): date
    case .open: calendar.date(byAdding: .day, value: 7, to: arrival)!
    }
  }
}
