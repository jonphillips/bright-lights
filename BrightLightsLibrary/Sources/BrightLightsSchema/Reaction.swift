import Foundation
import SQLiteData

public enum ReactionKind: String, QueryBindable, CaseIterable, Sendable {
  case interested
  case booked
  case pass
  case went
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
  }
}
