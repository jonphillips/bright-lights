import Dependencies
import DependenciesTestSupport
import Foundation
import BrightLightsSchema
import SQLiteData
import Testing

@Suite(.dependencies { try $0.bootstrapBrightLightsDatabase() })
struct SchemaTests {
  @Dependency(\.defaultDatabase) var database

  @Test func listingTimeRoundTripsThroughColumns() {
    let opens = Date(timeIntervalSince1970: 1_800_000_000)
    let closes = Date(timeIntervalSince1970: 1_800_100_000)
    var listing = Listing(
      id: UUID(), sourceID: UUID(), stableKey: "run", title: "The Play",
      startsAt: opens, rung: .model, capturedBy: .mac
    )
    listing.time = .run(opens: opens, closes: closes)
    #expect(listing.time == .run(opens: opens, closes: closes))
    listing.time = .performance(closes)
    #expect(listing.time == .performance(closes))
  }

  @Test func stayDepartureRoundTripsThroughColumns() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date, departure: .tentative(date))
    #expect(stay.departure == .tentative(date))
    let openStay = Stay(id: UUID(), householdID: UUID(), arrivesOn: date, departure: .open)
    #expect(openStay.departure == .open)
  }

  @Test func registrySeeds44ActiveSourcesAndPreservesCheckHistory() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let seeded = try Source.fetchAll(db)
      #expect(seeded.count == 44)
      #expect(seeded.filter { $0.mode == .automated }.count == 29)
      #expect(seeded.filter { $0.mode == .manual }.count == 15)
      guard let source = seeded.first else { return }
      try Source.find(source.id).update {
        $0.lastCheckedAt = #bind(Date(timeIntervalSince1970: 1_800_000_000))
        $0.lastCheckOutcome = #bind(.failed)
        $0.lastListingCount = #bind(7)
        $0.consecutiveFailures = #bind(3)
      }.execute(db)
      try Source.syncFromRegistry(in: db)
      let updated = try Source.find(source.id).fetchOne(db)
      #expect(updated?.lastCheckOutcome == .failed)
      #expect(updated?.lastListingCount == 7)
      #expect(updated?.consecutiveFailures == 3)
    }
  }

  @Test func offlineRegistryDuplicatesConvergeAndKeepListings() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let sources = try Source.fetchAll(db)
      let original = try #require(sources.first)
      let duplicate = Source(
        id: UUID(), householdID: original.householdID, registryID: original.registryID,
        name: "stale duplicate", type: original.type, priority: original.priority,
        area: original.area, mode: original.mode, method: original.method,
        listingURL: original.listingURL, registeredHosts: original.registeredHosts,
        cadence: original.cadence, createdAt: Date(timeIntervalSince1970: 1)
      )
      try Source.insert { Source.Draft(duplicate) }.execute(db)
      let listing = Listing(
        id: UUID(), sourceID: original.id, stableKey: "source-test:event", title: "Test",
        startsAt: Date(timeIntervalSince1970: 1_800_000_000), rung: .adapter, capturedBy: .mac
      )
      try Listing.insert { Listing.Draft(listing) }.execute(db)
      try Source.syncFromRegistry(in: db)
      let remaining = try Source.where { $0.registryID.eq(original.registryID) }.fetchAll(db)
      let repointed = try Listing.find(listing.id).fetchOne(db)
      #expect(remaining.count == 1)
      #expect(remaining.first?.id == duplicate.id)
      #expect(repointed?.sourceID == duplicate.id)
    }
  }

  @Test func defaultHouseholdConvergesEmptyDuplicates() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let source = try #require(Source.fetchAll(db).first)
      let extra = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
      try Household.insert { Household.Draft(extra) }.execute(db)
      let defaultHousehold = try Household.ensureDefault(in: db)
      #expect(defaultHousehold.id == source.householdID)
      #expect(try Household.fetchAll(db).count == 1)
    }
  }

  @Test func migrationRegistersOneFrozenSchemaStep() {
    #expect(BrightLightsDatabaseMigrations.makeMigrator().migrations.count == 1)
  }
}
