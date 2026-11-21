import BrightLightsExtraction
import Foundation
import SQLiteData

public struct ListingReconcileCounts: Equatable, Sendable {
  public var new: Int
  public var changed: Int
  public var markedMissing: Int
  public var written: Int { new + changed + markedMissing }

  public init(new: Int = 0, changed: Int = 0, markedMissing: Int = 0) {
    self.new = new; self.changed = changed; self.markedMissing = markedMissing
  }
}

public extension Listing {
  /// Applies one completed extraction inside its caller's write transaction.
  /// Duplicate rows converge before any content changes are written.
  static func reconcile(
    _ extracted: [ExtractedListing],
    sourceID: Source.ID,
    capturedBy: ListingCaptureSource = .mac,
    complete: Bool,
    now: Date,
    makeID: () -> UUID,
    in db: Database
  ) throws -> ListingReconcileCounts {
    let existing = try Listing.where { $0.sourceID.eq(sourceID) }.fetchAll(db)
    let grouped = Dictionary(grouping: existing, by: \.stableKey)
    var returnedKeys = Set<String>()
    var counts = ListingReconcileCounts()

    for item in extracted {
      returnedKeys.insert(item.stableKey)
      let duplicates = grouped[item.stableKey, default: []].sorted {
        $0.firstSeenAt == $1.firstSeenAt ? $0.id.uuidString < $1.id.uuidString : $0.firstSeenAt < $1.firstSeenAt
      }
      let current = duplicates.first
      if let current {
        for loser in duplicates.dropFirst() {
          try Reaction.where { $0.listingID.eq(loser.id) }.update { $0.listingID = #bind(current.id) }.execute(db)
          try Listing.find(loser.id).delete().execute(db)
        }
      }

      let performers = String(decoding: try JSONEncoder().encode(item.performers), as: UTF8.self)
      let startsAt: Date
      let closesAt: Date?
      switch item.time {
      case let .performance(date): startsAt = date; closesAt = nil
      case let .run(opens, closes): startsAt = opens; closesAt = closes
      }
      let status = ListingStatus(rawValue: item.status.rawValue) ?? .listed
      let contentChanged = current.map {
        $0.title != item.title || $0.performers != performers || $0.room != item.room
          || $0.ticketURL != item.ticketURL?.absoluteString || $0.onSaleAt != item.onSaleDate
          || $0.startsAt != startsAt || $0.closesAt != closesAt
          || ($0.status != status && $0.status != .missing) || $0.status == .missing
      } ?? true
      guard contentChanged else { continue }
      let row = Listing(
        id: current?.id ?? makeID(), sourceID: sourceID, stableKey: item.stableKey,
        title: item.title, performers: performers, room: item.room,
        ticketURL: item.ticketURL?.absoluteString, onSaleAt: item.onSaleDate,
        startsAt: startsAt, closesAt: closesAt, status: status,
        rung: ExtractionRung(rawValue: item.rung.rawValue) ?? .model,
        capturedBy: capturedBy, firstSeenAt: current?.firstSeenAt ?? now, updatedAt: now
      )
      if current == nil { try Listing.insert { Listing.Draft(row) }.execute(db) }
      else { try Listing.upsert { Listing.Draft(row) }.execute(db) }
      if current == nil { counts.new += 1 } else { counts.changed += 1 }
    }

    if complete {
      for row in existing where !returnedKeys.contains(row.stableKey)
        && (row.closesAt ?? row.startsAt) > now && row.status != .missing {
        try Listing.find(row.id).update {
          $0.status = #bind(ListingStatus.missing); $0.updatedAt = #bind(now)
        }.execute(db)
        counts.markedMissing += 1
      }
    }
    return counts
  }

  /// Removes listings 30 days after their end date. Taste records keep decisions alive.
  static func pruneExpired(before cutoff: Date, in db: Database) throws {
    _ = try TasteRecord.backfill(in: db)
    try #sql(
      """
      DELETE FROM \(Listing.self)
      WHERE COALESCE(\(Listing.closesAt), \(Listing.startsAt)) < \(cutoff)
      """
    ).execute(db)
  }
}
