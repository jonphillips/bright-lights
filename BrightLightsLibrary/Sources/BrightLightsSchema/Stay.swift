import Foundation
import SQLiteData

public enum StayDeparture: Equatable, Sendable {
  case booked(Date)
  case tentative(Date)
  case open
}

public enum StayDepartureKind: String, QueryBindable, CaseIterable, Sendable {
  case booked
  case tentative
  case open
}

@Table
public struct Stay: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var arrivesOn: Date
  public var departureKind: StayDepartureKind
  public var departsOn: Date?

  public init(id: UUID, householdID: UUID, arrivesOn: Date, departure: StayDeparture) {
    self.id = id; self.householdID = householdID; self.arrivesOn = arrivesOn
    switch departure {
    case let .booked(date): departureKind = .booked; departsOn = date
    case let .tentative(date): departureKind = .tentative; departsOn = date
    case .open: departureKind = .open; departsOn = nil
    }
  }

  public var departure: StayDeparture {
    get {
      switch departureKind {
      case .booked: departsOn.map(StayDeparture.booked) ?? .open
      case .tentative: departsOn.map(StayDeparture.tentative) ?? .open
      case .open: .open
      }
    }
    set {
      switch newValue {
      case let .booked(date): departureKind = .booked; departsOn = date
      case let .tentative(date): departureKind = .tentative; departsOn = date
      case .open: departureKind = .open; departsOn = nil
      }
    }
  }
}
