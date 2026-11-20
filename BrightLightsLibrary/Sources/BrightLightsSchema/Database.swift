import Dependencies
import SQLiteData

extension DependencyValues {
  public mutating func bootstrapBrightLightsDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.attachMetadatabase(containerIdentifier: "iCloud.com.jonphillips.BrightLights")
    }
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    try BrightLightsDatabaseMigrations.makeMigrator().migrate(database)
    defaultDatabase = database
    defaultSyncEngine = try SyncEngine(
      for: database,
      tables: Household.self, Source.self, Listing.self, Stay.self, Reaction.self, TasteRecord.self,
      containerIdentifier: "iCloud.com.jonphillips.BrightLights",
      startImmediately: false
    )
  }
}
