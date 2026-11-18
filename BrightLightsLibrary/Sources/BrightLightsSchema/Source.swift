import Foundation
import SQLiteData

public enum SourceMode: String, QueryBindable, CaseIterable, Sendable {
  case automated
  case manual
  case skip
}

public enum SourceCheckOutcome: String, QueryBindable, CaseIterable, Sendable {
  case never
  case succeeded
  case failed
}

@Table
public struct Source: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var registryID: String
  public var name: String
  public var type: String
  public var priority: String
  public var area: String
  public var mode: SourceMode
  public var method: String
  public var adapter: String?
  public var adapterVenue: String?
  public var listingURL: String
  public var registeredHosts: String
  public var excludedHosts: String
  public var cadence: String
  public var lastCheckedAt: Date?
  public var lastCheckOutcome: SourceCheckOutcome
  public var lastListingCount: Int?
  public var consecutiveFailures: Int
  public var createdAt: Date

  public init(
    id: UUID, householdID: UUID, registryID: String, name: String, type: String,
    priority: String, area: String, mode: SourceMode, method: String, adapter: String? = nil,
    adapterVenue: String? = nil, listingURL: String, registeredHosts: String,
    excludedHosts: String = "[]", cadence: String, lastCheckedAt: Date? = nil,
    lastCheckOutcome: SourceCheckOutcome = .never, lastListingCount: Int? = nil,
    consecutiveFailures: Int = 0, createdAt: Date = .now
  ) {
    self.id = id; self.householdID = householdID; self.registryID = registryID
    self.name = name; self.type = type; self.priority = priority; self.area = area
    self.mode = mode; self.method = method; self.adapter = adapter; self.adapterVenue = adapterVenue
    self.listingURL = listingURL; self.registeredHosts = registeredHosts
    self.excludedHosts = excludedHosts; self.cadence = cadence
    self.lastCheckedAt = lastCheckedAt; self.lastCheckOutcome = lastCheckOutcome
    self.lastListingCount = lastListingCount; self.consecutiveFailures = consecutiveFailures
    self.createdAt = createdAt
  }
}
