import Foundation
import CloudKit
import SQLiteData

@Table
public struct Household: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name = "Our Household"
  public var createdAt: Date
  public var checkerDeviceID: UUID?
  public var checkerDeviceName: String?
  public var checkerClaimedAt: Date?
  public var registryVersion: String?

  public init(id: UUID, name: String = "Our Household", createdAt: Date = .now,
    checkerDeviceID: UUID? = nil, checkerDeviceName: String? = nil, checkerClaimedAt: Date? = nil,
    registryVersion: String? = nil) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.checkerDeviceID = checkerDeviceID
    self.checkerDeviceName = checkerDeviceName
    self.checkerClaimedAt = checkerClaimedAt
    self.registryVersion = registryVersion
  }

  public static func ensureDefault(
    in db: Database, sharing: (Household) -> HouseholdSharing
  ) throws -> Household {
    let households = try Household.fetchAll(db)
    if households.isEmpty {
      let created = Household(id: UUID())
      try Household.insert { Household.Draft(created) }.execute(db)
      return created
    }
    let survivor = Household.survivor(in: households, sharing: sharing)
    let losers = households.filter { $0.id != survivor.id }
    if losers.isEmpty { return survivor }

    let survivorSharing = sharing(survivor)
    for loser in losers {
      if survivorSharing == .sharedWithMe || survivorSharing == .sharedByMe {
        // Children of a shared root stay in its CloudKit zone. Re-parenting would
        // move local data across a share boundary and leak it to the other person.
      } else {
        try repoint(loser, to: survivor, in: db)
      }
      try Household.find(loser.id).delete().execute(db)
    }
    return survivor
  }

  public static func canonical(
    in db: Database, sharing: (Household) -> HouseholdSharing
  ) throws -> Household? {
    let households = try Household.fetchAll(db)
    guard !households.isEmpty else { return nil }
    return survivor(in: households, sharing: sharing)
  }

  public static func sharingLookup(in db: Database) throws -> (Household) -> HouseholdSharing {
    let metadata = try SyncMetadata.where { $0.recordType.eq("households") }.fetchAll(db)
    var states: [UUID: HouseholdSharing] = [:]
    for item in metadata {
      guard let id = UUID(uuidString: item.recordPrimaryKey) else { continue }
      if item.ownerName != CKCurrentUserDefaultName { states[id] = .sharedWithMe }
      else { states[id] = item.isShared ? .sharedByMe : .private }
    }
    return { household in states[household.id, default: .private] }
  }

  public static func syncMetadata(for household: Household, in db: Database) throws -> SyncMetadata? {
    try SyncMetadata.where {
      $0.recordType.eq("households") && $0.recordPrimaryKey.eq(household.id.uuidString.lowercased())
    }.fetchOne(db)
  }

  public static func survivor(
    in households: [Household], sharing: (Household) -> HouseholdSharing
  ) -> Household {
    households.sorted { lhs, rhs in
      let left = sharing(lhs).priority
      let right = sharing(rhs).priority
      if left != right { return left > right }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }[0]
  }

  public static func sharingState(of household: Household, metadata: [SyncMetadata]) -> HouseholdSharing {
    guard let item = metadata.first(where: {
      $0.recordType == "households" && UUID(uuidString: $0.recordPrimaryKey) == household.id
    }) else { return .private }
    if item.ownerName != CKCurrentUserDefaultName { return .sharedWithMe }
    return item.isShared ? .sharedByMe : .private
  }

  private static func repoint(_ loser: Household, to survivor: Household, in db: Database) throws {
    try Source.where { $0.householdID.eq(loser.id) }
      .update { $0.householdID = #bind(survivor.id) }.execute(db)
    try Stay.where { $0.householdID.eq(loser.id) }
      .update { $0.householdID = #bind(survivor.id) }.execute(db)
    try TasteNote.where { $0.householdID.eq(loser.id) }
      .update { $0.householdID = #bind(survivor.id) }.execute(db)

    for record in try TasteRecord.where({ $0.householdID.eq(loser.id) }).fetchAll(db) {
      let id = TasteRecord.id(
        householdID: survivor.id, sourceRegistryID: record.sourceRegistryID, stableKey: record.stableKey
      )
      if let existing = try TasteRecord.find(id).fetchOne(db) {
        if record.updatedAt > existing.updatedAt {
          let replacement = copy(record, id: id, householdID: survivor.id)
          try TasteRecord.upsert { TasteRecord.Draft(replacement) }.execute(db)
        }
        try TasteRecord.find(record.id).delete().execute(db)
      } else {
        let replacement = copy(record, id: id, householdID: survivor.id)
        try TasteRecord.upsert { TasteRecord.Draft(replacement) }.execute(db)
      }
    }

    for person in try Person.where({ $0.householdID.eq(loser.id) }).fetchAll(db) {
      let newID = Person.id(householdID: survivor.id, recordName: person.iCloudUserRecordName)
      if let existing = try Person.find(newID).fetchOne(db) {
        if existing.displayName.isEmpty, !person.displayName.isEmpty {
          var replacement = existing
          replacement.displayName = person.displayName
          try Person.upsert { Person.Draft(replacement) }.execute(db)
        }
        try Reaction.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
        try TasteRecord.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
        try TasteNote.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
        try Person.find(person.id).delete().execute(db)
      } else {
        let replacement = Person(
          id: newID, householdID: survivor.id, iCloudUserRecordName: person.iCloudUserRecordName,
          displayName: person.displayName, createdAt: person.createdAt
        )
        try Person.upsert { Person.Draft(replacement) }.execute(db)
        try Reaction.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
        try TasteRecord.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
        try TasteNote.where { $0.authorID.eq(person.id) }
          .update { $0.authorID = #bind(newID) }.execute(db)
      }
    }
  }

  private static func copy(_ record: TasteRecord, id: UUID, householdID: UUID) -> TasteRecord {
    TasteRecord(
      id: id, householdID: householdID, sourceRegistryID: record.sourceRegistryID,
      sourceName: record.sourceName, stableKey: record.stableKey, title: record.title,
      performers: record.performers, room: record.room, startsAt: record.startsAt,
      closesAt: record.closesAt, kind: record.kind, suggestion: record.suggestion, note: record.note, authorID: record.authorID,
      firstDecidedAt: record.firstDecidedAt, updatedAt: record.updatedAt
    )
  }
}

public enum HouseholdSharing: Equatable, CaseIterable, Sendable {
  case `private`
  case sharedByMe
  case sharedWithMe

  fileprivate var priority: Int {
    switch self {
    case .private: 0
    case .sharedByMe: 1
    case .sharedWithMe: 2
    }
  }
}
