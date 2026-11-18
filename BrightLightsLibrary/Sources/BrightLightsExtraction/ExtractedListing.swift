import Foundation

public struct ExtractedListing: Codable, Sendable, Equatable, Identifiable {
  public enum Time: Codable, Sendable, Equatable {
    case performance(Date)
    case run(opens: Date, closes: Date)
  }

  public enum Status: String, Codable, Sendable {
    case listed
    case soldOut
    case cancelled
  }

  public enum Rung: String, Codable, Sendable {
    case jsonLD
    case adapter
    case model
  }

  public var id: String { stableKey }
  public var stableKey: String
  public var title: String
  public var performers: [String]
  public var room: String?
  public var time: Time
  public var ticketURL: URL?
  public var onSaleDate: Date?
  public var status: Status
  public var rung: Rung

  public init(
    stableKey: String,
    title: String,
    performers: [String] = [],
    room: String? = nil,
    time: Time,
    ticketURL: URL? = nil,
    onSaleDate: Date? = nil,
    status: Status = .listed,
    rung: Rung
  ) {
    self.stableKey = stableKey
    self.title = title
    self.performers = performers
    self.room = room
    self.time = time
    self.ticketURL = ticketURL
    self.onSaleDate = onSaleDate
    self.status = status
    self.rung = rung
  }
}

public struct ExtractionResult: Sendable, Equatable {
  public var listings: [ExtractedListing]
  public var warnings: [String]

  public init(listings: [ExtractedListing], warnings: [String] = []) {
    self.listings = listings
    self.warnings = warnings
  }
}

public struct SourceDescriptor: Sendable, Equatable {
  public enum Adapter: String, Sendable, Codable {
    case mercuryEast
    case aegAXS
    case caveatJSON
  }

  public var id: String
  public var adapter: Adapter?
  public var registeredHosts: [String]
  public var excludedHosts: [String]
  public var adapterVenue: String?

  public init(
    id: String,
    adapter: Adapter? = nil,
    registeredHosts: [String] = [],
    excludedHosts: [String] = [],
    adapterVenue: String? = nil
  ) {
    self.id = id
    self.adapter = adapter
    self.registeredHosts = registeredHosts
    self.excludedHosts = excludedHosts
    self.adapterVenue = adapterVenue
  }
}

public enum PageDocument: Sendable, Equatable {
  case html(String)
  case json(String)

  var rawValue: String {
    switch self {
    case let .html(value), let .json(value): value
    }
  }
}
