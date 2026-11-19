import Dependencies
import DependenciesTestSupport
import Foundation
import BrightLightsExtraction
import BrightLightsSchema
import SQLiteData
import Testing

@Suite(.serialized, .dependencies { try $0.bootstrapBrightLightsDatabase() })
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

  @Test func unchangedRegistrySyncDoesNotTouchSourceSyncMetadata() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
    }
    let before = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("sources") }
        .fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }
        .sorted()
    }
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
    }
    let after = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("sources") }
        .fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }
        .sorted()
    }
    #expect(!before.isEmpty)
    #expect(after == before)
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
      let canonicalBeforeConvergence = try Source.canonical.fetchAll(db)
      #expect(canonicalBeforeConvergence.count == 44)
      #expect(canonicalBeforeConvergence.first { $0.registryID == original.registryID }?.id == duplicate.id)
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

  @Test func convergenceQueuesHouseholdAndSourceLoserDeletionsForCloudKit() async throws {
    let loserHouseholdID = UUID()
    let loserSourceID = UUID()
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let household = try Household.ensureDefault(in: db)
      let source = try #require(Source.fetchAll(db).first)
      let loserHousehold = Household(id: loserHouseholdID, createdAt: household.createdAt.addingTimeInterval(1))
      let loserSource = Source(
        id: loserSourceID, householdID: loserHousehold.id, registryID: source.registryID,
        name: "duplicate source", type: source.type, priority: source.priority, area: source.area,
        mode: source.mode, method: source.method, adapter: source.adapter, adapterVenue: source.adapterVenue,
        listingURL: source.listingURL, registeredHosts: source.registeredHosts,
        excludedHosts: source.excludedHosts, cadence: source.cadence,
        createdAt: source.createdAt.addingTimeInterval(1)
      )
      try Household.insert { Household.Draft(loserHousehold) }.execute(db)
      try Source.insert { Source.Draft(loserSource) }.execute(db)
    }

    try await database.write { db in
      _ = try Household.ensureDefault(in: db)
      try Source.syncFromRegistry(in: db)
    }

    let deletedRecordIDs = try await database.read { db in
      try SyncMetadata.where { $0._isDeleted }
        .fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.recordType)" }
    }
    #expect(deletedRecordIDs.contains("\(loserHouseholdID.uuidString.lowercased()):households"))
    #expect(deletedRecordIDs.contains("\(loserSourceID.uuidString.lowercased()):sources"))
  }

  @Test func defaultHouseholdChoosesOldestAndRepointsSources() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let oldest = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
      let newer = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 2))
      try Household.insert {
        Household.Draft(oldest)
        Household.Draft(newer)
      }.execute(db)
      let source = try #require(Source.fetchAll(db).first)
      try Source.find(source.id).update { $0.householdID = #bind(newer.id) }.execute(db)
      let defaultHousehold = try Household.ensureDefault(in: db)
      #expect(defaultHousehold.id == oldest.id)
      #expect(try Household.fetchAll(db).count == 1)
      #expect(try Source.where { $0.householdID.neq(oldest.id) }.fetchCount(db) == 0)
    }
  }

  @Test func registryAddsTheDeclaredPaginationRules() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db)
      let sources = try Source.fetchAll(db)
      #expect(sources.first { $0.registryID == "bowery-ballroom" }?.pagination?.contains("mercuryeastpresents.com") == true)
      #expect(sources.first { $0.registryID == "the-stand" }?.pagination?.contains("months_ahead") == true)
      #expect(sources.first { $0.registryID == "ny-comedy-club" }?.pagination?.contains("months_ahead") == true)
      #expect(sources.first { $0.registryID == "brooklyn-steel" }?.feedURL == "https://aegwebprod.blob.core.windows.net/json/resources/8/events/d099bg4x01/events.json")
      #expect(sources.first { $0.registryID == "caveat" }?.feedURL == "https://caveat.nyc/api/events/listings")
    }
  }

  @Test func changedListingContentUpdatesTheExistingRow() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let old = try makeListing(sourceID: sourceID, key: "event", title: "Old title")
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    try await database.write { db in
      try Listing.insert { Listing.Draft(old) }.execute(db)
      let writes = try Listing.reconcile(
        [extracted("event", title: "New title")], sourceID: sourceID, complete: true,
        now: now, makeID: UUID.init, in: db
      )
      #expect(writes == 1)
      let updated = try #require(try Listing.find(old.id).fetchOne(db))
      #expect(updated.id == old.id)
      #expect(updated.title == "New title")
      #expect(updated.updatedAt == now)
    }
  }

  @Test func provenanceOnlyChangeDoesNotWrite() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let old = try makeListing(sourceID: sourceID, key: "event", title: "Same", rung: .adapter)
    try await database.write { db in
      try Listing.insert { Listing.Draft(old) }.execute(db)
      let writes = try Listing.reconcile(
        [extracted("event", title: "Same", rung: .model)], sourceID: sourceID,
        complete: true, now: .now, makeID: UUID.init, in: db
      )
      #expect(writes == 0)
      #expect(try Listing.find(old.id).fetchOne(db)?.rung == .adapter)
    }
  }

  @Test func missingListingIsRestoredWhenItReturnsAndPartialChecksLeaveItAlone() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let retained = try makeListing(sourceID: sourceID, key: "retained", title: "Retained", date: now.addingTimeInterval(86_400))
    let absent = try makeListing(sourceID: sourceID, key: "absent", title: "Absent", date: now.addingTimeInterval(86_400))
    try await database.write { db in
      try Listing.insert { Listing.Draft(retained); Listing.Draft(absent) }.execute(db)
      _ = try Listing.reconcile([extracted("retained", title: "Retained")], sourceID: sourceID,
        complete: false, now: now, makeID: UUID.init, in: db)
      #expect(try Listing.find(absent.id).fetchOne(db)?.status == .listed)
      _ = try Listing.reconcile([extracted("retained", title: "Retained")], sourceID: sourceID,
        complete: true, now: now, makeID: UUID.init, in: db)
      #expect(try Listing.find(absent.id).fetchOne(db)?.status == .missing)
      _ = try Listing.reconcile([extracted("retained", title: "Retained"), extracted("absent", title: "Absent")],
        sourceID: sourceID, complete: true, now: now, makeID: UUID.init, in: db)
      #expect(try Listing.find(absent.id).fetchOne(db)?.status == .listed)
    }
  }

  @Test func duplicateListingsConvergeAndKeepTheirReaction() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let earlier = Date(timeIntervalSince1970: 1_800_000_000)
    let survivor = try makeListing(sourceID: sourceID, key: "event", title: "Show", firstSeenAt: earlier)
    let loser = try makeListing(sourceID: sourceID, key: "event", title: "Show", firstSeenAt: earlier.addingTimeInterval(1))
    try await database.write { db in
      try Listing.insert { Listing.Draft(survivor); Listing.Draft(loser) }.execute(db)
      let reaction = Reaction(id: UUID(), listingID: loser.id, kind: .booked)
      try Reaction.insert { Reaction.Draft(reaction) }.execute(db)
      _ = try Listing.reconcile([extracted("event", title: "Show")], sourceID: sourceID,
        complete: true, now: .now, makeID: UUID.init, in: db)
      #expect(try Listing.where { $0.sourceID.eq(sourceID) }.fetchCount(db) == 1)
      #expect(try Reaction.find(reaction.id).fetchOne(db)?.listingID == survivor.id)
    }
  }

  @Test func pruningDeletesOnlyPastListingsWithoutReactions() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let cutoff = Date(timeIntervalSince1970: 1_900_000_000)
    let unreacted = try makeListing(sourceID: sourceID, key: "old-unreacted", title: "Old", date: cutoff.addingTimeInterval(-1))
    let reacted = try makeListing(sourceID: sourceID, key: "old-reacted", title: "Kept", date: cutoff.addingTimeInterval(-1))
    try await database.write { db in
      try Listing.insert { Listing.Draft(unreacted); Listing.Draft(reacted) }.execute(db)
      try Reaction.insert { Reaction.Draft(Reaction(id: UUID(), listingID: reacted.id, kind: .went)) }.execute(db)
      try Listing.pruneExpired(before: cutoff, in: db)
      #expect(try Listing.find(unreacted.id).fetchOne(db) == nil)
      #expect(try Listing.find(reacted.id).fetchOne(db) != nil)
    }
  }

  @Test func registryRetirementAndReturnAreReconciled() async throws {
    let original = Data(#"{"sources":[{"id":"bowery-ballroom","name":"Bowery Ballroom","source_type":"venue","priority":"core","listing_url":"https://example.com/bowery","registered_hosts":["example.com"],"mode":"automated","method":"structured_html","cadence":"weekly"}]}"#.utf8)
    let retired = Data(#"{"sources":[]}"#.utf8)
    try await database.write { db in
      try Source.syncFromRegistry(data: original, in: db)
      let source = try #require(Source.fetchAll(db).first { $0.registryID == "bowery-ballroom" })
      try Source.syncFromRegistry(data: retired, in: db)
      #expect(try Source.find(source.id).fetchOne(db)?.retiredAt != nil)
      try Source.syncFromRegistry(data: original, in: db)
      #expect(try Source.find(source.id).fetchOne(db)?.retiredAt == nil)
    }
  }

  private func makeListing(
    sourceID: UUID, key: String, title: String, date: Date = Date(timeIntervalSince1970: 1_900_000_000),
    rung: ExtractionRung = .adapter, firstSeenAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) throws -> Listing {
    Listing(id: UUID(), sourceID: sourceID, stableKey: key, title: title, startsAt: date,
      rung: rung, capturedBy: .mac, firstSeenAt: firstSeenAt)
  }

  private func createSource(id: UUID) async throws {
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      let source = Source(id: id, householdID: household.id, registryID: id.uuidString, name: "Test source",
        type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
        listingURL: "https://example.com/events", registeredHosts: "[\"example.com\"]", cadence: "weekly")
      try Source.insert { Source.Draft(source) }.execute(db)
    }
  }

  private func extracted(_ key: String, title: String, rung: ExtractedListing.Rung = .adapter) -> ExtractedListing {
    ExtractedListing(stableKey: key, title: title, time: .performance(Date(timeIntervalSince1970: 1_900_000_000)), rung: rung)
  }

  @Test func migrationRegistersTheFrozenS2SchemaAndCheckingSchema() {
    #expect(BrightLightsDatabaseMigrations.makeMigrator().migrations.count == 2)
  }
}
