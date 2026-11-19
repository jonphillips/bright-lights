import Foundation
import SQLiteData

public enum SourceMode: String, QueryBindable, CaseIterable, Sendable {
  case automated
  case manual
}

public enum SourceCheckOutcome: String, QueryBindable, CaseIterable, Sendable {
  case never
  case succeeded
  case failed
}

@Table
public struct Source: Identifiable, Equatable, Sendable {
  public static let manualLookFailureThreshold = 3 // The M1 S3 consecutive-failure rule.
  public static let checkNoteCharacterLimit = 500 // The M1 S3 persisted note limit.
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
  public var feedURL: String?
  public var registeredHosts: String
  public var excludedHosts: String
  public var cadence: String
  public var lastCheckedAt: Date?
  public var lastCheckOutcome: SourceCheckOutcome
  public var lastListingCount: Int?
  public var consecutiveFailures: Int
  public var pagination: String?
  public var retiredAt: Date?
  public var lastContentHash: String?
  public var lastCheckNote: String?
  public var createdAt: Date

  public init(
    id: UUID, householdID: UUID, registryID: String, name: String, type: String,
    priority: String, area: String, mode: SourceMode, method: String, adapter: String? = nil,
    adapterVenue: String? = nil, listingURL: String, feedURL: String? = nil, registeredHosts: String,
    excludedHosts: String = "[]", cadence: String, lastCheckedAt: Date? = nil,
    lastCheckOutcome: SourceCheckOutcome = .never, lastListingCount: Int? = nil,
    consecutiveFailures: Int = 0, pagination: String? = nil, retiredAt: Date? = nil,
    lastContentHash: String? = nil, lastCheckNote: String? = nil, createdAt: Date = .now
  ) {
    self.id = id; self.householdID = householdID; self.registryID = registryID
    self.name = name; self.type = type; self.priority = priority; self.area = area
    self.mode = mode; self.method = method; self.adapter = adapter; self.adapterVenue = adapterVenue
    self.listingURL = listingURL; self.feedURL = feedURL; self.registeredHosts = registeredHosts
    self.excludedHosts = excludedHosts; self.cadence = cadence
    self.lastCheckedAt = lastCheckedAt; self.lastCheckOutcome = lastCheckOutcome
    self.lastListingCount = lastListingCount; self.consecutiveFailures = consecutiveFailures
    self.pagination = pagination; self.retiredAt = retiredAt
    self.lastContentHash = lastContentHash; self.lastCheckNote = lastCheckNote
    self.createdAt = createdAt
  }

  public var needsManualLook: Bool {
    consecutiveFailures >= Self.manualLookFailureThreshold
      || (lastCheckOutcome == .failed && lastCheckNote?.hasPrefix("returned no listings (was") == true)
  }
}

public extension Source {
  static var active: Where<Source> {
    Source.canonical.where { $0.retiredAt.is(nil) }
  }

  /// One stable representative per registry identity. This read-time convergence
  /// also hides duplicate seeds arriving from another device before the next launch.
  static var canonical: Where<Source> {
    Source.where { source in
      !Source.as(EarlierSource.self).where { candidate in
        candidate.registryID.eq(source.registryID)
          && (candidate.createdAt.lt(source.createdAt)
            || (candidate.createdAt.eq(source.createdAt) && candidate.id.lt(source.id)))
      }.exists()
    }
  }
}

private enum EarlierSource: AliasName {}
