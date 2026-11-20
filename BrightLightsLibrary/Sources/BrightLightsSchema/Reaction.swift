import Foundation
import SQLiteData

public enum ReactionKind: String, QueryBindable, CaseIterable, Sendable {
  case kept
  case interested
  case booked
  case went
  case pass
  case cleared

  public var isPicked: Bool { self == .kept || self == .interested || self == .booked || self == .went }
  public var isHidden: Bool { self == .pass || self == .cleared }
  public var title: String { rawValue.capitalized }
}

@Table
public struct Reaction: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var listingID: Listing.ID
  public var kind: ReactionKind
  public var note: String?
  public var authorID: UUID?
  public var updatedAt: Date

  public init(id: UUID, listingID: UUID, kind: ReactionKind, note: String? = nil,
    authorID: UUID? = nil, updatedAt: Date = .now) {
    self.id = id; self.listingID = listingID; self.kind = kind; self.note = note
    self.authorID = authorID; self.updatedAt = updatedAt
  }
}

public extension Reaction {
  /// Reactions are household state: edits replace the one row for a listing.
  /// Converges any offline duplicates before writing the replacement.
  static func upsertForListing(_ reaction: Reaction, in db: Database) throws {
    let matches = try Reaction.where { $0.listingID.eq(reaction.listingID) }.fetchAll(db)
    let existing = matches.sorted { lhs, rhs in
      if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
    if let survivor = existing.first {
      for duplicate in existing.dropFirst() {
        try Reaction.find(duplicate.id).delete().execute(db)
      }
      let replacement = Reaction(
        id: survivor.id, listingID: reaction.listingID, kind: reaction.kind,
        note: reaction.note, authorID: reaction.authorID, updatedAt: reaction.updatedAt
      )
      try Reaction.upsert { Reaction.Draft(replacement) }.execute(db)
    } else {
      try Reaction.insert { Reaction.Draft(reaction) }.execute(db)
    }
    try TasteRecord.upsertForReaction(reaction, in: db)
  }

  @discardableResult
  static func screen(kept: Set<Listing.ID>, cleared: Set<Listing.ID>, authorID: UUID?, now: Date, in db: Database) throws -> Int {
    var writes = 0
    for (ids, kind) in [(kept, ReactionKind.kept), (cleared, .cleared)] {
      for listingID in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
        guard try Reaction.where({ $0.listingID.eq(listingID) }).fetchOne(db) == nil,
          try Listing.find(listingID).fetchOne(db) != nil else { continue }
        let reaction = Reaction(id: UUID(), listingID: listingID, kind: kind, authorID: authorID, updatedAt: now)
        try upsertForListing(reaction, in: db)
        writes += 1
      }
    }
    return writes
  }
}
