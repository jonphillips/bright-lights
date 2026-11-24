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

  @Test func registryVersionComparesDottedComponents() {
    #expect(RegistryVersion(rawValue: "1.10")! > RegistryVersion(rawValue: "1.9")!)
    #expect(RegistryVersion(rawValue: "1.3")! == RegistryVersion(rawValue: "1.3.0")!)
    #expect(RegistryVersion(rawValue: "2.0")! > RegistryVersion(rawValue: "1.99")!)
    #expect(RegistryVersion(rawValue: "one.two") == nil)
  }

  @Test func productionStorePathIsSeparateAndLivesBesideDefaultStore() {
    let directory = URL(fileURLWithPath: "/tmp/bright-lights-support")
    #expect(BrightLightsStorage.releaseDatabaseURL(applicationSupportDirectory: directory).path
      == directory.appendingPathComponent("BrightLights-Production.sqlite").path)
    #expect(BrightLightsStorage.releaseDatabaseURL(applicationSupportDirectory: directory).lastPathComponent
      != "SQLiteData.db")
  }

  @Test func tasteNoteEditabilityAndSubjectPrefill() {
    let authorID = UUID()
    let note = TasteNote(id: UUID(), householdID: UUID(), authorID: authorID, body: "A note")
    let listing = Listing(
      id: UUID(), sourceID: UUID(), stableKey: "show", title: "The Show",
      startsAt: Date(timeIntervalSince1970: 10), rung: .model, capturedBy: .mac
    )

    #expect(note.isEditable(by: authorID))
    #expect(!note.isEditable(by: UUID()))
    #expect(!note.isEditable(by: nil))
    #expect(TasteNote(id: UUID(), householdID: UUID(), body: "No author").isEditable(by: UUID()))
    #expect(TasteNote.defaultSubject(for: listing, performerNames: ["First Performer", "Second Performer"]) == "First Performer")
    #expect(TasteNote.defaultSubject(for: listing, performerNames: []) == "The Show")
  }

  @Test func personIdentityIsStableAndBindingOnlyFillsAnEmptyName() async throws {
    let recordName = "cloudkit-record-name"
    let household = Household(id: UUID())
    let id = Person.id(householdID: household.id, recordName: recordName)
    #expect(id == Person.id(householdID: household.id, recordName: recordName))
    try await database.write { db in
      try Household.insert { Household.Draft(household) }.execute(db)
      try Person.insert { Person.Draft(Person(
        id: id, householdID: household.id, iCloudUserRecordName: recordName
      )) }.execute(db)
      #expect(try Person.bind(recordName: recordName, participantGivenName: "Wendy", in: household, db: db) == id)
      #expect(try Person.bind(recordName: recordName, participantGivenName: "Changed", in: household, db: db) == id)
      #expect(try Person.find(id).fetchOne(db)?.displayName == "Wendy")
    }
  }

  @Test func sharedHouseholdSurvivorIsIndependentOfInputOrder() {
    let households = [
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: Date(timeIntervalSince1970: 1)),
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: Date(timeIntervalSince1970: 2)),
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, createdAt: Date(timeIntervalSince1970: 3))
    ]
    let states: [UUID: HouseholdSharing] = [
      households[0].id: .private, households[1].id: .sharedByMe, households[2].id: .sharedWithMe
    ]
    let forward = Household.survivor(in: households) { states[$0.id, default: .private] }
    let reverse = Household.survivor(in: Array(households.reversed())) { states[$0.id, default: .private] }
    #expect(forward.id == households[2].id)
    #expect(reverse.id == forward.id)

    let tied = [
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, createdAt: Date(timeIntervalSince1970: 4)),
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, createdAt: Date(timeIntervalSince1970: 4))
    ]
    for state in HouseholdSharing.allCases {
      let expected = tied.map(\.id).min { $0.uuidString < $1.uuidString }!
      let tiedWinner = Household.survivor(in: tied) { _ in state }
      #expect(tiedWinner.id == expected)
    }
    #expect(HouseholdSharing.allCases == [.private, .sharedByMe, .sharedWithMe])

    let pair = [
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, createdAt: Date(timeIntervalSince1970: 1)),
      Household(id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!, createdAt: Date(timeIntervalSince1970: 2))
    ]
    let rank: (HouseholdSharing) -> Int = {
      switch $0 {
      case .private: 0
      case .sharedByMe: 1
      case .sharedWithMe: 2
      }
    }
    for leftState in HouseholdSharing.allCases {
      for rightState in HouseholdSharing.allCases {
        let states = [pair[0].id: leftState, pair[1].id: rightState]
        let winner = Household.survivor(in: pair) { states[$0.id, default: .private] }
        let expected = rank(leftState) == rank(rightState)
          ? pair[0].id
          : (rank(leftState) > rank(rightState) ? pair[0].id : pair[1].id)
        #expect(winner.id == expected)
      }
    }
  }

  @Test func reactionAttributionIsShownOnlyForNamedOtherPeople() {
    #expect(Reaction.attributedTitle(kind: .interested, authorName: "Wendy", isCurrentPerson: false) == "Interested · Wendy")
    #expect(Reaction.attributedTitle(kind: .interested, authorName: "Jon", isCurrentPerson: true) == "Interested")
    #expect(Reaction.attributedTitle(kind: .interested, authorName: "", isCurrentPerson: false) == "Interested")
  }

  @Test func expectedCloudKitFieldsCoverTheMigratedSchema() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let rows = try String(contentsOf: root.appendingPathComponent("cloudkit-expected-fields.txt"), encoding: .utf8)
      .split(whereSeparator: \.isNewline)
    let fields = rows.compactMap { row -> (String, String)? in
      let pieces = row.split(separator: " ")
      guard pieces.count == 2 else { return nil }
      return (String(pieces[0]), String(pieces[1]))
    }
    #expect(fields.count == rows.count)
    let tables = Set(fields.map(\.0))
    #expect(tables == ["households", "sources", "listings", "stays", "reactions", "tasteRecords", "people", "tasteNotes"])
    try await database.read { db in
      for table in tables {
        let listed = Set(fields.filter { $0.0 == table }.map(\.1))
        let columns = Set(try db.columns(in: table).map(\.name))
        let metadataPrefix = "sqlitedata_icloud_userModificationTime_"
        #expect(columns.isSubset(of: listed))
        #expect(listed.subtracting(columns).allSatisfy {
          $0 == "sqlitedata_icloud_userModificationTime"
            || ($0.hasPrefix(metadataPrefix) && columns.contains(String($0.dropFirst(metadataPrefix.count))))
        })
      }
    }
  }

  @Test func migrationV7CreatesTasteNotesWithItsHouseholdIndex() async throws {
    try await database.read { db in
      let columns = Set(try db.columns(in: "tasteNotes").map(\.name))
      #expect(columns == ["id", "householdID", "authorID", "subject", "body", "createdAt", "updatedAt"])
      let index = try db.indexes(on: "tasteNotes").first { $0.name == "index_tasteNotes_on_householdID" }
      #expect(index?.columns == ["householdID"])
      #expect(index?.isUnique == false)
    }
  }

  @Test func migrationV8AddsNullableTasteSuggestion() async throws {
    try await database.read { db in
      let columns = try db.columns(in: "tasteRecords")
      let suggestion = try #require(columns.first { $0.name == "suggestion" })
      #expect(suggestion.isNotNull == false)
    }
  }

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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let updated = try Source.find(source.id).fetchOne(db)
      #expect(updated?.lastCheckOutcome == .failed)
      #expect(updated?.lastListingCount == 7)
      #expect(updated?.consecutiveFailures == 3)
    }
  }

  @Test func sourcePageURLFallsBackToRegistryPage() {
    let source = Source(
      id: UUID(), householdID: UUID(), registryID: "test", name: "Test", type: "venue",
      priority: "core", area: "NYC", mode: .manual, method: "manual",
      listingURL: "https://example.com/events", registeredHosts: "[\"example.com\"]", cadence: "weekly"
    )
    #expect(source.pageURL == source.listingURL)
    #expect(Source(
      id: source.id, householdID: source.householdID, registryID: source.registryID,
      name: source.name, type: source.type, priority: source.priority, area: source.area,
      mode: source.mode, method: source.method, listingURL: source.listingURL,
      startPageURL: "https://example.com/calendar", registeredHosts: source.registeredHosts,
      cadence: "weekly"
    ).pageURL == "https://example.com/calendar")
  }

  @Test func registrySyncPreservesSourceFixesAndClearsStartPageWhenRegistryCatchesUp() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let source = try #require(Source.fetchAll(db).first { $0.registryID == "town-hall" })
      try Source.find(source.id).update {
        $0.startPageURL = #bind("https://thetownhall.org/calendar")
        $0.flaggedAt = #bind(Date(timeIntervalSince1970: 1_800_000_000))
        $0.flagNote = #bind("wrong page")
      }.execute(db)

      try Source.syncFromRegistry(data: registryData(
        id: source.registryID, name: source.name, listingURL: "https://thetownhall.org/calendar"
      ), in: db, sharing: { _ in .private })
      let updated = try #require(try Source.find(source.id).fetchOne(db))
      #expect(updated.startPageURL == nil)
      #expect(updated.flaggedAt == Date(timeIntervalSince1970: 1_800_000_000))
      #expect(updated.flagNote == "wrong page")
    }
  }

  @Test func registrySyncPreservesSourceFixesWhenOtherRegistryFieldsChange() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let source = try #require(Source.fetchAll(db).first { $0.registryID == "town-hall" })
      let startPage = "https://thetownhall.org/calendar"
      let flaggedAt = Date(timeIntervalSince1970: 1_800_000_000)
      try Source.find(source.id).update {
        $0.startPageURL = #bind(startPage)
        $0.flaggedAt = #bind(flaggedAt)
        $0.flagNote = #bind("wrong page")
      }.execute(db)

      try Source.syncFromRegistry(data: registryData(
        id: source.registryID, name: "Town Hall Updated", listingURL: source.listingURL
      ), in: db, sharing: { _ in .private })
      let updated = try #require(try Source.find(source.id).fetchOne(db))
      #expect(updated.name == "Town Hall Updated")
      #expect(updated.startPageURL == startPage)
      #expect(updated.flaggedAt == flaggedAt)
      #expect(updated.flagNote == "wrong page")
    }
  }

  @Test func unchangedRegistrySyncDoesNotTouchSourceSyncMetadata() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      guard let source = try Source.fetchAll(db).first else { return }
      try Source.find(source.id).update {
        $0.startPageURL = #bind("https://example.com/app-page")
        $0.flaggedAt = #bind(Date(timeIntervalSince1970: 1_800_000_000))
        $0.flagNote = #bind("does not read")
      }.execute(db)
    }
    let before = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("sources") }
        .fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }
        .sorted()
    }
    try await database.write { db in
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let household = try Household.ensureDefault(in: db, sharing: { _ in .private })
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
      _ = try Household.ensureDefault(in: db, sharing: { _ in .private })
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let oldest = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
      let newer = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 2))
      try Household.insert {
        Household.Draft(oldest)
        Household.Draft(newer)
      }.execute(db)
      let source = try #require(Source.fetchAll(db).first)
      try Source.find(source.id).update { $0.householdID = #bind(newer.id) }.execute(db)
      let oldPerson = Person(
        id: Person.id(householdID: oldest.id, recordName: "jon-record"), householdID: oldest.id,
        iCloudUserRecordName: "jon-record", displayName: "Jon"
      )
      let newPerson = Person(
        id: Person.id(householdID: newer.id, recordName: "jon-record"), householdID: newer.id,
        iCloudUserRecordName: "jon-record", displayName: ""
      )
      try Person.insert { Person.Draft(oldPerson); Person.Draft(newPerson) }.execute(db)
      let olderTaste = TasteRecord(
        id: TasteRecord.id(householdID: oldest.id, sourceRegistryID: "venue", stableKey: "show"),
        householdID: oldest.id, sourceRegistryID: "venue", sourceName: "Venue", stableKey: "show",
        title: "Older", performers: "", startsAt: Date(timeIntervalSince1970: 1), kind: .kept,
        authorID: oldPerson.id, firstDecidedAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
      let newerTaste = TasteRecord(
        id: TasteRecord.id(householdID: newer.id, sourceRegistryID: "venue", stableKey: "show"),
        householdID: newer.id, sourceRegistryID: "venue", sourceName: "Venue", stableKey: "show",
        title: "Newer", performers: "", startsAt: Date(timeIntervalSince1970: 1), kind: .interested,
        authorID: newPerson.id, firstDecidedAt: Date(timeIntervalSince1970: 2),
        updatedAt: Date(timeIntervalSince1970: 20)
      )
      let nonCollidingTaste = TasteRecord(
        id: TasteRecord.id(householdID: newer.id, sourceRegistryID: "venue", stableKey: "other"),
        householdID: newer.id, sourceRegistryID: "venue", sourceName: "Venue", stableKey: "other",
        title: "Other", performers: "", startsAt: Date(timeIntervalSince1970: 1), kind: .kept,
        authorID: newPerson.id, firstDecidedAt: Date(timeIntervalSince1970: 3),
        updatedAt: Date(timeIntervalSince1970: 30)
      )
      try TasteRecord.insert {
        TasteRecord.Draft(olderTaste)
        TasteRecord.Draft(newerTaste)
        TasteRecord.Draft(nonCollidingTaste)
      }.execute(db)
      let tasteNote = TasteNote(
        id: UUID(), householdID: newer.id, authorID: newPerson.id,
        subject: "The Show", body: "A note written by Wendy",
        createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 20)
      )
      try TasteNote.insert { TasteNote.Draft(tasteNote) }.execute(db)
      let listing = Listing(
        id: UUID(), sourceID: source.id, stableKey: "attributed", title: "Show",
        startsAt: Date(timeIntervalSince1970: 100), rung: .adapter, capturedBy: .mac
      )
      try Listing.insert { Listing.Draft(listing) }.execute(db)
      let reaction = Reaction(
        id: UUID(), listingID: listing.id, kind: .kept, authorID: newPerson.id,
        updatedAt: Date(timeIntervalSince1970: 20)
      )
      try Reaction.insert { Reaction.Draft(reaction) }.execute(db)
      let defaultHousehold = try Household.ensureDefault(in: db, sharing: { _ in .private })
      #expect(defaultHousehold.id == oldest.id)
      #expect(try Household.fetchAll(db).count == 1)
      #expect(try Source.where { $0.householdID.neq(oldest.id) }.fetchCount(db) == 0)
      let rekeyedTasteID = TasteRecord.id(householdID: oldest.id, sourceRegistryID: "venue", stableKey: "show")
      #expect(try TasteRecord.fetchAll(db).filter { $0.stableKey == "show" }.count == 1)
      #expect(try TasteRecord.find(rekeyedTasteID).fetchOne(db)?.title == "Newer")
      let rekeyedPersonID = Person.id(householdID: oldest.id, recordName: "jon-record")
      let rekeyedOtherTasteID = TasteRecord.id(householdID: oldest.id, sourceRegistryID: "venue", stableKey: "other")
      #expect(try TasteRecord.find(rekeyedOtherTasteID).fetchOne(db)?.authorID == rekeyedPersonID)
      #expect(try TasteNote.find(tasteNote.id).fetchOne(db)?.householdID == oldest.id)
      #expect(try TasteNote.find(tasteNote.id).fetchOne(db)?.authorID == rekeyedPersonID)
      #expect(try Person.fetchAll(db).filter { $0.iCloudUserRecordName == "jon-record" }.count == 1)
      #expect(try Reaction.find(reaction.id).fetchOne(db)?.authorID == rekeyedPersonID)
    }
  }

  @Test func participantKeepsTheSharedSeedAndDeletesItsPrivateDuplicate() async throws {
    let privateHousehold = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
    let sharedHousehold = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 2))
    try await database.write { db in
      try Household.insert { Household.Draft(privateHousehold) }.execute(db)
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
      let privateSources = try Source.fetchAll(db)
      #expect(privateSources.count == 44)

      try Household.insert { Household.Draft(sharedHousehold) }.execute(db)
      let sharedSources = privateSources.map { copy($0, to: sharedHousehold.id) }
      for source in sharedSources { try Source.insert { Source.Draft(source) }.execute(db) }

      let privateListing = try makeListing(sourceID: privateSources[0].id, key: "private", title: "Private")
      let sharedListing = try makeListing(sourceID: sharedSources[0].id, key: "shared", title: "Shared")
      try Listing.insert { Listing.Draft(privateListing); Listing.Draft(sharedListing) }.execute(db)
      let privateReaction = Reaction(id: UUID(), listingID: privateListing.id, kind: .kept)
      let sharedReaction = Reaction(id: UUID(), listingID: sharedListing.id, kind: .interested)
      try Reaction.insert { Reaction.Draft(privateReaction); Reaction.Draft(sharedReaction) }.execute(db)

      let states: [UUID: HouseholdSharing] = [
        privateHousehold.id: .private, sharedHousehold.id: .sharedWithMe
      ]
      let sharing: (Household) -> HouseholdSharing = { states[$0.id, default: .private] }
      let survivor = try Household.ensureDefault(in: db, sharing: sharing)
      try Source.syncFromRegistry(in: db, sharing: sharing)

      #expect(survivor.id == sharedHousehold.id)
      #expect(try Household.fetchAll(db).map(\.id) == [sharedHousehold.id])
      let remainingSources = try Source.fetchAll(db)
      #expect(remainingSources.count == 44)
      #expect(Set(remainingSources.map(\.id)) == Set(sharedSources.map(\.id)))
      #expect(Set(remainingSources.map(\.id)).isDisjoint(with: Set(privateSources.map(\.id))))
      #expect(try Listing.find(privateListing.id).fetchOne(db) == nil)
      #expect(try Reaction.find(privateReaction.id).fetchOne(db) == nil)
      let survivingSharedListing = try #require(try Listing.find(sharedListing.id).fetchOne(db))
      #expect(survivingSharedListing.sourceID == sharedListing.sourceID)
      #expect(survivingSharedListing.title == sharedListing.title)
      let survivingSharedReaction = try #require(try Reaction.find(sharedReaction.id).fetchOne(db))
      #expect(survivingSharedReaction.listingID == sharedReaction.listingID)
      #expect(survivingSharedReaction.kind == sharedReaction.kind)
      #expect(try Household.find(sharedHousehold.id).fetchOne(db)?.registryVersion == nil)
    }
  }

  @Test func participantDoesNotSeedOrAdvanceRegistryVersion() async throws {
    let household = Household(
      id: UUID(), createdAt: Date(timeIntervalSince1970: 1), registryVersion: "1.3"
    )
    try await database.write { db in
      try Household.insert { Household.Draft(household) }.execute(db)
      let participant: (Household) -> HouseholdSharing = { _ in .sharedWithMe }
      try Source.syncFromRegistry(
        data: registryData(id: "new-source", name: "New", listingURL: "https://example.com", version: "1.4"),
        in: db, sharing: participant
      )
      #expect(try Source.fetchAll(db).isEmpty)
      #expect(try Household.find(household.id).fetchOne(db)?.registryVersion == "1.3")
    }
  }

  @Test func sharedOwnerDeletesLoserChildrenWithoutReparenting() async throws {
    let privateHousehold = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
    let sharedHousehold = Household(id: UUID(), createdAt: Date(timeIntervalSince1970: 2))
    let stay = Stay(
      id: UUID(), householdID: privateHousehold.id, arrivesOn: Date(timeIntervalSince1970: 10), departure: .open
    )
    let taste = TasteRecord(
      id: TasteRecord.id(householdID: privateHousehold.id, sourceRegistryID: "venue", stableKey: "show"),
      householdID: privateHousehold.id, sourceRegistryID: "venue", sourceName: "Venue", stableKey: "show",
      title: "Show", performers: "", startsAt: Date(timeIntervalSince1970: 100), kind: .kept,
      firstDecidedAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)
    )
    let tasteNote = TasteNote(id: UUID(), householdID: privateHousehold.id, body: "Private note")
    try await database.write { db in
      try Household.insert { Household.Draft(privateHousehold); Household.Draft(sharedHousehold) }.execute(db)
      try Stay.insert { Stay.Draft(stay) }.execute(db)
      try TasteRecord.insert { TasteRecord.Draft(taste) }.execute(db)
      try TasteNote.insert { TasteNote.Draft(tasteNote) }.execute(db)
      let states: [UUID: HouseholdSharing] = [
        privateHousehold.id: .private, sharedHousehold.id: .sharedByMe
      ]
      let sharing: (Household) -> HouseholdSharing = { states[$0.id, default: .private] }
      let survivor = try Household.ensureDefault(in: db, sharing: sharing)
      #expect(survivor.id == sharedHousehold.id)
      #expect(try Household.fetchAll(db).map(\.id) == [sharedHousehold.id])
      #expect(try Stay.fetchAll(db).isEmpty)
      #expect(try TasteRecord.fetchAll(db).isEmpty)
      #expect(try TasteNote.fetchAll(db).isEmpty)
    }
  }

  @Test func registryAddsTheDeclaredPaginationRules() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(in: db, sharing: { _ in .private })
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
      let counts = try Listing.reconcile(
        [extracted("event", title: "New title")], sourceID: sourceID, complete: true,
        now: now, makeID: UUID.init, in: db
      )
      #expect(counts == ListingReconcileCounts(changed: 1))
      #expect(counts.written == 1)
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
      let counts = try Listing.reconcile(
        [extracted("event", title: "Same", rung: .model)], sourceID: sourceID,
        complete: true, now: .now, makeID: UUID.init, in: db
      )
      #expect(counts == ListingReconcileCounts())
      #expect(counts.written == 0)
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

  @Test func reconcileCountsNewChangedRestoredAndMarkedMissingListings() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let changed = try makeListing(sourceID: sourceID, key: "changed", title: "Old title")
    let restored = try makeListing(sourceID: sourceID, key: "restored", title: "Back again")
    let restoredRow = Listing(id: restored.id, sourceID: restored.sourceID, stableKey: restored.stableKey,
      title: restored.title, performers: restored.performers, room: restored.room, ticketURL: restored.ticketURL,
      onSaleAt: restored.onSaleAt, startsAt: restored.startsAt, closesAt: restored.closesAt,
      status: .missing, rung: restored.rung, capturedBy: restored.capturedBy,
      firstSeenAt: restored.firstSeenAt, updatedAt: restored.updatedAt)
    let absent = try makeListing(sourceID: sourceID, key: "absent", title: "No longer listed",
      date: now.addingTimeInterval(86_400))
    try await database.write { db in
      try Listing.insert { Listing.Draft(changed); Listing.Draft(restoredRow); Listing.Draft(absent) }.execute(db)
      let counts = try Listing.reconcile([
        extracted("changed", title: "New title"),
        extracted("restored", title: "Back again"),
        extracted("new", title: "Brand new")
      ], sourceID: sourceID, complete: true, now: now, makeID: UUID.init, in: db)
      #expect(counts.new == 1)
      #expect(counts.changed == 2)
      #expect(counts.markedMissing == 1)
      #expect(counts.written == 4)
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

  @Test func pruningDeletesExpiredListingsAndTheirReactionsButKeepsTasteRecords() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let cutoff = Date(timeIntervalSince1970: 1_900_000_000)
    let expired = try makeListing(sourceID: sourceID, key: "old-reacted", title: "Kept", date: cutoff.addingTimeInterval(-1))
    let future = try makeListing(sourceID: sourceID, key: "future-cleared", title: "Cleared", date: cutoff.addingTimeInterval(86_400))
    let reaction = Reaction(id: UUID(), listingID: expired.id, kind: .kept, updatedAt: cutoff.addingTimeInterval(-100))
    try await database.write { db in
      try Listing.insert { Listing.Draft(expired); Listing.Draft(future) }.execute(db)
      try Reaction.insert { Reaction.Draft(reaction) }.execute(db)
      try Reaction.insert { Reaction.Draft(Reaction(id: UUID(), listingID: future.id, kind: .cleared)) }.execute(db)
      try Listing.pruneExpired(before: cutoff, in: db)
      #expect(try Listing.find(expired.id).fetchOne(db) == nil)
      #expect(try Reaction.where { $0.listingID.eq(expired.id) }.fetchCount(db) == 0)
      #expect(try TasteRecord.fetchCount(db) == 2)
      #expect(try Listing.find(future.id).fetchOne(db) != nil)
    }
  }

  @Test func tasteRecordIDIsStableAndInputSensitiveWithVersionEightBits() {
    let household = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let expected = TasteRecord.id(householdID: household, sourceRegistryID: "venue", stableKey: "event")
    #expect(expected == TasteRecord.id(householdID: household, sourceRegistryID: "venue", stableKey: "event"))
    #expect(expected != TasteRecord.id(householdID: UUID(), sourceRegistryID: "venue", stableKey: "event"))
    #expect(expected != TasteRecord.id(householdID: household, sourceRegistryID: "other", stableKey: "event"))
    #expect(expected != TasteRecord.id(householdID: household, sourceRegistryID: "venue", stableKey: "other"))
    let bytes = withUnsafeBytes(of: expected.uuid) { Array($0) }
    #expect(bytes[6] >> 4 == 8)
    #expect(bytes[8] >> 6 == 2)
  }

  @Test func reactionsUpsertTasteRecordAndPreserveFirstDecisionTime() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let listing = try makeListing(sourceID: sourceID, key: "taste-upsert", title: "Show")
    let first = Date(timeIntervalSince1970: 1_800_000_000)
    let later = first.addingTimeInterval(300)
    try await database.write { db in
      try Listing.insert { Listing.Draft(listing) }.execute(db)
      try Reaction.upsertForListing(Reaction(id: UUID(), listingID: listing.id, kind: .kept, note: "first", updatedAt: first), suggestion: .keep, in: db)
      try Reaction.upsertForListing(Reaction(id: UUID(), listingID: listing.id, kind: .booked, note: "later", updatedAt: later), in: db)
      let household = try #require(try Source.find(sourceID).fetchOne(db)?.householdID)
      let id = TasteRecord.id(householdID: household, sourceRegistryID: sourceID.uuidString, stableKey: listing.stableKey)
      let record = try #require(try TasteRecord.find(id).fetchOne(db))
      #expect(record.kind == .booked)
      #expect(record.note == "later")
      #expect(record.firstDecidedAt == first)
      #expect(record.updatedAt == later)
      #expect(record.title == listing.title)
      #expect(record.suggestion == .keep)
    }
  }

  @Test func screeningWritesKeptAndClearedAndSkipsExistingReactions() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let existing = try makeListing(sourceID: sourceID, key: "already", title: "Already reacted")
    let kept = try makeListing(sourceID: sourceID, key: "kept", title: "Keep")
    let cleared = try makeListing(sourceID: sourceID, key: "cleared", title: "Clear")
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    try await database.write { db in
      try Listing.insert { Listing.Draft(existing); Listing.Draft(kept); Listing.Draft(cleared) }.execute(db)
      try Reaction.insert { Reaction.Draft(Reaction(id: UUID(), listingID: existing.id, kind: .booked)) }.execute(db)
      let written = try Reaction.screen(
        kept: [existing.id, kept.id], cleared: [cleared.id],
        suggestions: [kept.id: .keep, cleared.id: .clear], authorID: nil, now: time, in: db
      )
      #expect(written == 2)
      #expect(try Reaction.where { $0.listingID.eq(existing.id) }.fetchOne(db)?.kind == .booked)
      #expect(try Reaction.where { $0.listingID.eq(kept.id) }.fetchOne(db)?.kind == .kept)
      #expect(try Reaction.where { $0.listingID.eq(cleared.id) }.fetchOne(db)?.kind == .cleared)
      #expect(try TasteRecord.fetchCount(db) == 2)
      #expect(try TasteRecord.where { $0.stableKey.eq("kept") }.fetchOne(db)?.suggestion == .keep)
      #expect(try TasteRecord.where { $0.stableKey.eq("cleared") }.fetchOne(db)?.suggestion == .clear)
    }
  }

  @Test func tasteBackfillIsIdempotent() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let listing = try makeListing(sourceID: sourceID, key: "backfill", title: "Legacy reaction")
    try await database.write { db in
      try Listing.insert { Listing.Draft(listing) }.execute(db)
      try Reaction.insert { Reaction.Draft(Reaction(id: UUID(), listingID: listing.id, kind: .interested)) }.execute(db)
      #expect(try TasteRecord.backfill(in: db) == 1)
      #expect(try TasteRecord.backfill(in: db) == 0)
      #expect(try TasteRecord.fetchCount(db) == 1)
    }
  }

  @Test func recapturingClearedListingDoesNotMakeItNewAgain() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let listing = try makeListing(sourceID: sourceID, key: "screened", title: "Already cleared")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try await database.write { db in
      try Listing.insert { Listing.Draft(listing) }.execute(db)
      try Reaction.upsertForListing(Reaction(id: UUID(), listingID: listing.id, kind: .cleared, updatedAt: now), in: db)
      _ = try Listing.reconcile([extracted("screened", title: listing.title)], sourceID: sourceID,
        complete: false, now: now, makeID: UUID.init, in: db)
      let source = try #require(try Source.find(sourceID).fetchOne(db))
      let currentListing = try #require(try Listing.find(listing.id).fetchOne(db))
      let reaction = try #require(try Reaction.where { $0.listingID.eq(listing.id) }.fetchOne(db))
      let projection = NewProjection(
        listings: [currentListing], sources: [source], reactions: [reaction], tasteRecordIDs: [], now: now
      )
      #expect(projection.total == 0)
    }
  }

  @Test func duplicateListingRowsShareTheScreeningDecision() async throws {
    let sourceID = UUID()
    try await createSource(id: sourceID)
    let first = try makeListing(sourceID: sourceID, key: "duplicate-event", title: "Same event")
    let second = try makeListing(sourceID: sourceID, key: "duplicate-event", title: "Same event")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try await database.write { db in
      try Listing.insert { Listing.Draft(first); Listing.Draft(second) }.execute(db)
      try Reaction.upsertForListing(
        Reaction(id: UUID(), listingID: first.id, kind: .cleared, updatedAt: now), in: db
      )
      let source = try #require(try Source.find(sourceID).fetchOne(db))
      let tasteRecord = try #require(try TasteRecord.fetchAll(db).first)
      let projection = NewProjection(
        listings: [first, second], sources: [source], reactions: [Reaction(id: UUID(), listingID: first.id, kind: .cleared)],
        tasteRecordIDs: [tasteRecord.id], now: now
      )
      #expect(projection.total == 0)
      let written = try Reaction.screen(kept: [], cleared: [second.id], authorID: nil, now: now, in: db)
      #expect(written == 0)
      #expect(try Reaction.where { $0.listingID.eq(second.id) }.fetchOne(db) == nil)
    }
  }

  @Test func registryRetirementAndReturnAreReconciled() async throws {
    let original = Data(#"{"registry_version":"1.3","sources":[{"id":"bowery-ballroom","name":"Bowery Ballroom","source_type":"venue","priority":"core","listing_url":"https://example.com/bowery","registered_hosts":["example.com"],"mode":"automated","method":"structured_html","cadence":"weekly"}]}"#.utf8)
    let retired = Data(#"{"registry_version":"1.3","sources":[]}"#.utf8)
    try await database.write { db in
      try Source.syncFromRegistry(data: original, in: db, sharing: { _ in .private })
      let source = try #require(Source.fetchAll(db).first { $0.registryID == "bowery-ballroom" })
      try Source.syncFromRegistry(data: retired, in: db, sharing: { _ in .private })
      #expect(try Source.find(source.id).fetchOne(db)?.retiredAt != nil)
      try Source.syncFromRegistry(data: original, in: db, sharing: { _ in .private })
      #expect(try Source.find(source.id).fetchOne(db)?.retiredAt == nil)
    }
  }

  @Test func olderRegistryCannotWriteOrRetireAndNewerRegistryCan() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(data: registryData(
        id: "bowery", name: "Original", listingURL: "https://example.com/old", version: "1.3"
      ), in: db, sharing: { _ in .private })
      let source = try #require(Source.fetchAll(db).first { $0.registryID == "bowery" })
      try Source.syncFromRegistry(data: registryData(
        id: "bowery", name: "Older build", listingURL: "https://example.com/older", version: "1.2"
      ), in: db, sharing: { _ in .private })
      let afterOlder = try #require(try Source.find(source.id).fetchOne(db))
      #expect(afterOlder.name == "Original")
      #expect(afterOlder.listingURL == "https://example.com/old")
      #expect(afterOlder.retiredAt == nil)
      #expect(try Household.find(source.householdID).fetchOne(db)?.registryVersion == "1.3")

      try Source.syncFromRegistry(data: registryData(
        id: "bowery", name: "Updated", listingURL: "https://example.com/new", version: "1.4"
      ), in: db, sharing: { _ in .private })
      #expect(try Source.find(source.id).fetchOne(db)?.name == "Updated")
      #expect(try Household.find(source.householdID).fetchOne(db)?.registryVersion == "1.4")
    }
  }

  @Test func olderRegistryStillConvergesDuplicatesButInsertsAndRetiresNothing() async throws {
    try await database.write { db in
      try Source.syncFromRegistry(data: registryData(
        id: "bowery", name: "Original", listingURL: "https://example.com/old", version: "1.3"
      ), in: db, sharing: { _ in .private })
      let original = try #require(Source.fetchAll(db).first { $0.registryID == "bowery" })
      let duplicate = Source(
        id: UUID(), householdID: original.householdID, registryID: original.registryID,
        name: "offline duplicate", type: original.type, priority: original.priority,
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

      try Source.syncFromRegistry(data: registryData(
        id: "townhall", name: "Older build only", listingURL: "https://example.com/townhall", version: "1.2"
      ), in: db, sharing: { _ in .private })

      let remaining = try Source.where { $0.registryID.eq("bowery") }.fetchAll(db)
      #expect(remaining.map(\.id) == [duplicate.id])
      #expect(remaining.first?.retiredAt == nil)
      #expect(try Listing.find(listing.id).fetchOne(db)?.sourceID == duplicate.id)
      #expect(try Source.where { $0.registryID.eq("townhall") }.fetchAll(db).isEmpty)
      #expect(try Household.find(original.householdID).fetchOne(db)?.registryVersion == "1.3")
    }
  }

  private func makeListing(
    sourceID: UUID, key: String, title: String, date: Date = Date(timeIntervalSince1970: 1_900_000_000),
    rung: ExtractionRung = .adapter, firstSeenAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) throws -> Listing {
    Listing(id: UUID(), sourceID: sourceID, stableKey: key, title: title, startsAt: date,
      rung: rung, capturedBy: .mac, firstSeenAt: firstSeenAt)
  }

  private func copy(_ source: Source, to householdID: UUID) -> Source {
    Source(
      id: UUID(), householdID: householdID, registryID: source.registryID, name: source.name,
      type: source.type, priority: source.priority, area: source.area, mode: source.mode,
      method: source.method, adapter: source.adapter, adapterVenue: source.adapterVenue,
      listingURL: source.listingURL, startPageURL: source.startPageURL, feedURL: source.feedURL,
      flaggedAt: source.flaggedAt, flagNote: source.flagNote, registeredHosts: source.registeredHosts,
      excludedHosts: source.excludedHosts, cadence: source.cadence, lastCheckedAt: source.lastCheckedAt,
      lastCheckOutcome: source.lastCheckOutcome, lastListingCount: source.lastListingCount,
      consecutiveFailures: source.consecutiveFailures, pagination: source.pagination,
      retiredAt: source.retiredAt, lastContentHash: source.lastContentHash,
      lastCheckNote: source.lastCheckNote, createdAt: source.createdAt
    )
  }

  private func createSource(id: UUID) async throws {
    try await database.write { db in
      let household = try Household.ensureDefault(in: db, sharing: { _ in .private })
      let source = Source(id: id, householdID: household.id, registryID: id.uuidString, name: "Test source",
        type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
        listingURL: "https://example.com/events", registeredHosts: "[\"example.com\"]", cadence: "weekly")
      try Source.insert { Source.Draft(source) }.execute(db)
    }
  }

  private func extracted(_ key: String, title: String, rung: ExtractedListing.Rung = .adapter) -> ExtractedListing {
    ExtractedListing(stableKey: key, title: title, time: .performance(Date(timeIntervalSince1970: 1_900_000_000)), rung: rung)
  }

  @Test func sourceFixesMigrationAddsNullableFieldsToAV2Database() async throws {
    let legacyDatabase = try SQLiteData.defaultDatabase(configuration: Configuration())
    let migrator = BrightLightsDatabaseMigrations.makeMigrator()
    try migrator.migrate(legacyDatabase, upTo: "Add source checking state v2")
    try await legacyDatabase.write { db in
      try db.execute(sql: """
        INSERT INTO households (id, name, createdAt)
        VALUES ('household', 'Household', '2001-01-01T00:00:00.000Z');
        INSERT INTO sources (
          id, householdID, registryID, name, type, priority, area, mode, method, listingURL,
          registeredHosts, excludedHosts, cadence, lastCheckOutcome, consecutiveFailures, createdAt
        ) VALUES (
          'source', 'household', 'legacy', 'Legacy source', 'venue', 'core', 'NYC', 'manual', 'manual',
          'https://example.com/events', '["example.com"]', '[]', 'weekly', 'never', 0,
          '2001-01-01T00:00:00.000Z'
        );
        """)
    }
    try migrator.migrate(legacyDatabase)
    try await legacyDatabase.write { db in
      try db.execute(sql: """
        CREATE TEMP TABLE migration_assertion (value INTEGER CHECK (value = 1));
        INSERT INTO migration_assertion
        SELECT count(*) = 1 AND sum(startPageURL IS NULL AND flaggedAt IS NULL AND flagNote IS NULL) = 1
        FROM sources WHERE id = 'source';
        INSERT INTO migration_assertion
        SELECT count(*) = 1 AND registryVersion IS NULL FROM households WHERE id = 'household';
        """)
    }
  }

  private func registryData(id: String, name: String, listingURL: String, version: String = "1.3") -> Data {
    let registry: [String: Any] = ["registry_version": version, "sources": [[
      "id": id, "name": name, "source_type": "venue", "area": "NYC", "priority": "core",
      "listing_url": listingURL, "registered_hosts": ["thetownhall.org"], "mode": "manual",
      "method": "manual", "cadence": "weekly"
    ]]]
    return try! JSONSerialization.data(withJSONObject: registry)
  }
}
