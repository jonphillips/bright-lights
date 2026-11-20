import CryptoKit
import Foundation
import SQLiteData

@Table
public struct TasteRecord: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var sourceRegistryID: String
  public var sourceName: String
  public var stableKey: String
  public var title: String
  public var performers: String
  public var room: String?
  public var startsAt: Date
  public var closesAt: Date?
  public var kind: ReactionKind
  public var note: String?
  public var authorID: UUID?
  public var firstDecidedAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, householdID: UUID, sourceRegistryID: String, sourceName: String,
    stableKey: String, title: String, performers: String, room: String? = nil,
    startsAt: Date, closesAt: Date? = nil, kind: ReactionKind, note: String? = nil,
    authorID: UUID? = nil, firstDecidedAt: Date, updatedAt: Date
  ) {
    self.id = id; self.householdID = householdID; self.sourceRegistryID = sourceRegistryID
    self.sourceName = sourceName; self.stableKey = stableKey; self.title = title
    self.performers = performers; self.room = room; self.startsAt = startsAt
    self.closesAt = closesAt; self.kind = kind; self.note = note; self.authorID = authorID
    self.firstDecidedAt = firstDecidedAt; self.updatedAt = updatedAt
  }

  public static func id(householdID: UUID, sourceRegistryID: String, stableKey: String) -> UUID {
    let input = "\(householdID.uuidString)|\(sourceRegistryID)|\(stableKey)"
    var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }

  static func upsertForReaction(_ reaction: Reaction, in db: Database) throws {
    guard let listing = try Listing.find(reaction.listingID).fetchOne(db),
      let source = try Source.find(listing.sourceID).fetchOne(db) else { return }
    let id = id(householdID: source.householdID, sourceRegistryID: source.registryID, stableKey: listing.stableKey)
    let existing = try TasteRecord.find(id).fetchOne(db)
    let record = TasteRecord(
      id: id, householdID: source.householdID, sourceRegistryID: source.registryID,
      sourceName: source.name, stableKey: listing.stableKey, title: listing.title,
      performers: listing.performers, room: listing.room, startsAt: listing.startsAt,
      closesAt: listing.closesAt, kind: reaction.kind, note: reaction.note,
      authorID: reaction.authorID, firstDecidedAt: existing?.firstDecidedAt ?? reaction.updatedAt,
      updatedAt: reaction.updatedAt
    )
    if existing == nil { try TasteRecord.insert { TasteRecord.Draft(record) }.execute(db) }
    else { try TasteRecord.upsert { TasteRecord.Draft(record) }.execute(db) }
  }

  @discardableResult
  public static func backfill(in db: Database) throws -> Int {
    let reactions = try Reaction.fetchAll(db).sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString > $1.id.uuidString
    }
    var writes = 0
    for reaction in reactions {
      guard let listing = try Listing.find(reaction.listingID).fetchOne(db),
        let source = try Source.find(listing.sourceID).fetchOne(db) else { continue }
      let id = id(householdID: source.householdID, sourceRegistryID: source.registryID, stableKey: listing.stableKey)
      guard try TasteRecord.find(id).fetchOne(db) == nil else { continue }
      try upsertForReaction(reaction, in: db)
      writes += 1
    }
    return writes
  }
}
