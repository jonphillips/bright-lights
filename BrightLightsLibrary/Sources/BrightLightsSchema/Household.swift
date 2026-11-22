import Foundation
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

  public static func ensureDefault(in db: Database) throws -> Household {
    let households = try Household.fetchAll(db).sorted {
      $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
    }
    if households.count == 1 { return households[0] }
    if let survivor = households.first {
      let losers = households.filter { $0.id != survivor.id }
      for loser in losers {
        try Source.where { $0.householdID.eq(loser.id) }
          .update { $0.householdID = #bind(survivor.id) }.execute(db)
        try Stay.where { $0.householdID.eq(loser.id) }
          .update { $0.householdID = #bind(survivor.id) }.execute(db)
        try Household.find(loser.id).delete().execute(db)
      }
      return survivor
    }
    let created = Household(id: UUID())
    try Household.insert { Household.Draft(created) }.execute(db)
    return created
  }

}

public extension Household {
  static var canonical: Where<Household> {
    Household.where { household in
      !Household.as(EarlierHousehold.self).where { candidate in
        candidate.createdAt.lt(household.createdAt)
          || (candidate.createdAt.eq(household.createdAt) && candidate.id.lt(household.id))
      }.exists()
    }
  }
}

private enum EarlierHousehold: AliasName {}
