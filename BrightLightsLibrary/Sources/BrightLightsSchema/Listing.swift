import Foundation
import BrightLightsExtraction
import SQLiteData

public enum ListingStatus: String, QueryBindable, CaseIterable, Sendable {
  case listed
  case soldOut
  case cancelled
  case missing
}

public enum ExtractionRung: String, QueryBindable, CaseIterable, Sendable {
  case jsonLD
  case adapter
  case model
}

public enum ListingCaptureSource: String, QueryBindable, CaseIterable, Sendable {
  case mac
  case browser
}

@Table
public struct Listing: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var sourceID: Source.ID
  public var stableKey: String
  public var title: String
  public var performers: String
  public var room: String?
  public var ticketURL: String?
  public var onSaleAt: Date?
  public var startsAt: Date
  public var closesAt: Date?
  public var status: ListingStatus
  public var rung: ExtractionRung
  public var capturedBy: ListingCaptureSource
  public var firstSeenAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, sourceID: UUID, stableKey: String, title: String, performers: String = "[]",
    room: String? = nil, ticketURL: String? = nil, onSaleAt: Date? = nil,
    startsAt: Date, closesAt: Date? = nil, status: ListingStatus = .listed,
    rung: ExtractionRung, capturedBy: ListingCaptureSource, firstSeenAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id; self.sourceID = sourceID; self.stableKey = stableKey; self.title = title
    self.performers = performers; self.room = room; self.ticketURL = ticketURL
    self.onSaleAt = onSaleAt; self.startsAt = startsAt; self.closesAt = closesAt
    self.status = status; self.rung = rung; self.capturedBy = capturedBy
    self.firstSeenAt = firstSeenAt; self.updatedAt = updatedAt
  }

  public var time: ExtractedListing.Time {
    get { closesAt.map { .run(opens: startsAt, closes: $0) } ?? .performance(startsAt) }
    set {
      switch newValue {
      case let .performance(start): startsAt = start; closesAt = nil
      case let .run(opens, closes): startsAt = opens; closesAt = closes
      }
    }
  }
}

public extension Listing {
  /// One deterministic representative per `(sourceID, stableKey)`.
  static var canonical: Where<Listing> {
    Listing.where { listing in
      !Listing.as(EarlierListing.self).where { candidate in
        candidate.sourceID.eq(listing.sourceID)
          && candidate.stableKey.eq(listing.stableKey)
          && (candidate.firstSeenAt.lt(listing.firstSeenAt)
            || (candidate.firstSeenAt.eq(listing.firstSeenAt) && candidate.id.lt(listing.id)))
      }.exists()
    }
  }
}

private enum EarlierListing: AliasName {}
