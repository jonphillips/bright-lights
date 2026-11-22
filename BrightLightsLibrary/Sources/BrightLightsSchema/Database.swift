import Dependencies
import Foundation
import SQLiteData

public enum BrightLightsStorage {
  public static func releaseDatabaseURL(applicationSupportDirectory: URL) -> URL {
    applicationSupportDirectory.appendingPathComponent("BrightLights-Production.sqlite")
  }
}

extension DependencyValues {
  public mutating func bootstrapBrightLightsDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.attachMetadatabase(containerIdentifier: "iCloud.com.jonphillips.BrightLights")
    }
    let database: any DatabaseWriter
    #if DEBUG
      database = try SQLiteData.defaultDatabase(configuration: configuration)
    #else
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      database = try SQLiteData.defaultDatabase(
        path: BrightLightsStorage.releaseDatabaseURL(applicationSupportDirectory: support).path,
        configuration: configuration
      )
    #endif
    try BrightLightsDatabaseMigrations.makeMigrator().migrate(database)
    defaultDatabase = database
    defaultSyncEngine = try SyncEngine(
      for: database,
      tables: Household.self, Source.self, Listing.self, Stay.self, Reaction.self, TasteRecord.self, Person.self,
      containerIdentifier: "iCloud.com.jonphillips.BrightLights",
      startImmediately: false
    )
  }
}
