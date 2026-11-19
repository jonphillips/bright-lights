import BrightLightsSchema
import Foundation
import SQLiteData

public enum CheckerLease {
  public static func holds(deviceID: UUID, in db: Database) throws -> Bool {
    try Household.canonical.fetchOne(db)?.checkerDeviceID == deviceID
  }

  public static func mayCheck(
    deviceID: UUID, checkerEnabled: Bool, syncEnabled: Bool, in db: Database
  ) throws -> Bool {
    guard checkerEnabled, syncEnabled else { return false }
    return try holds(deviceID: deviceID, in: db)
  }

  public static func claim(deviceID: UUID, name: String, at date: Date, in db: Database) throws {
    let household = try Household.ensureDefault(in: db)
    try Household.find(household.id).update {
      $0.checkerDeviceID = #bind(deviceID)
      $0.checkerDeviceName = #bind(name)
      $0.checkerClaimedAt = #bind(date)
    }.execute(db)
  }
}
