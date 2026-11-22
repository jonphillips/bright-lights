import CryptoKit
import Foundation
import SQLiteData

@Table("people")
public struct Person: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var iCloudUserRecordName: String
  public var displayName: String
  public var createdAt: Date

  public init(
    id: UUID, householdID: UUID, iCloudUserRecordName: String,
    displayName: String = "", createdAt: Date = .now
  ) {
    self.id = id
    self.householdID = householdID
    self.iCloudUserRecordName = iCloudUserRecordName
    self.displayName = displayName
    self.createdAt = createdAt
  }

  public static func id(householdID: UUID, recordName: String) -> UUID {
    let input = "\(householdID.uuidString)|\(recordName)"
    var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }

  @discardableResult
  public static func bind(
    recordName: String, participantGivenName: String?, in household: Household, db: Database
  ) throws -> UUID {
    let id = id(householdID: household.id, recordName: recordName)
    if let existing = try Person.find(id).fetchOne(db) {
      let givenName = participantGivenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if existing.displayName.isEmpty, !givenName.isEmpty {
        var updated = existing
        updated.displayName = givenName
        try Person.upsert { Person.Draft(updated) }.execute(db)
      }
    } else {
      let givenName = participantGivenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      try Person.insert { Person.Draft(Person(
        id: id, householdID: household.id, iCloudUserRecordName: recordName, displayName: givenName
      )) }.execute(db)
    }
    return id
  }
}
