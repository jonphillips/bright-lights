import BrightLightsChecking
import BrightLightsSchema
import Dependencies
import DependenciesTestSupport
import Foundation
import LLMClientKit
import SQLiteData
import Testing

@Suite(.serialized, .dependencies { try $0.bootstrapBrightLightsDatabase() })
struct SourceCheckingTests {
  @Dependency(\.defaultDatabase) var database

  @Test func robotsRulesMatchSpecificAgentAndWildcardAndDelay() {
    let rules = RobotsRules(text: """
      User-agent: *
      Disallow: /private
      Crawl-delay: 3
      User-agent: BrightLights
      Disallow: /members
      """)
    #expect(!rules.allows(URL(string: "https://example.com/private/list")!))
    #expect(!rules.allows(URL(string: "https://example.com/members/list")!))
    #expect(rules.allows(URL(string: "https://example.com/events")!))
    #expect(rules.crawlDelay == 3)
  }

  @Test func nightlyAndWeeklyCadenceBecomeNightlyDuringStay() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let oldCheck = now.addingTimeInterval(-21 * 60 * 60)
    let source = Source(id: UUID(), householdID: UUID(), registryID: "nightly", name: "Club",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "html",
      listingURL: "https://example.com", registeredHosts: "[]", cadence: "nightly", lastCheckedAt: oldCheck)
    #expect(SourceCadence.isDue(source, at: now, stays: []))
    let recentCheck = now.addingTimeInterval(-5 * 24 * 60 * 60)
    var weekly = source; weekly.cadence = "weekly"; weekly.lastCheckedAt = recentCheck
    #expect(!SourceCadence.isDue(weekly, at: now, stays: []))
    let stay = Stay(id: UUID(), householdID: source.householdID,
      arrivesOn: Calendar.current.date(byAdding: .day, value: -1, to: now)!, departure: .open)
    #expect(SourceCadence.isDue(weekly, at: now, stays: [stay]))
  }

  @Test func threeFailuresAndZeroDropRequireAManualLook() {
    var source = Source(id: UUID(), householdID: UUID(), registryID: "example", name: "Example",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "html",
      listingURL: "https://example.com", registeredHosts: "[]", cadence: "weekly")
    #expect(!source.needsManualLook)
    source.consecutiveFailures = Source.manualLookFailureThreshold
    #expect(source.needsManualLook)
    source.consecutiveFailures = 0
    source.lastCheckNote = "returned no listings (was 4)"
    #expect(source.needsManualLook)
  }

  @Test func fixturePassUpsertsOnceAndSecondPassWritesNoListings() async throws {
    let boweryID = UUID(); let steelID = UUID(); let caveatID = UUID(); let standID = UUID()
    let bowery = try fixtureText("bowery-ballroom.html")
    let steel = try fixtureText("brooklyn-steel.json")
    let caveat = try fixtureText("caveat.json")
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      let sources = [
        Source(id: boweryID, householdID: household.id, registryID: "bowery-ballroom",
        name: "Bowery Ballroom", type: "venue", priority: "core", area: "Lower East Side",
        mode: .automated, method: "structured_html", adapter: "mercuryEast",
        listingURL: "https://mercuryeastpresents.com/boweryballroom/",
        registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly",
        pagination: #"{"kind":"pages","template":"https://mercuryeastpresents.com/boweryballroom/page/{n}/","first":2,"max":2}"#),
        Source(id: steelID, householdID: household.id, registryID: "brooklyn-steel",
          name: "Brooklyn Steel", type: "venue", priority: "core", area: "East Williamsburg",
          mode: .automated, method: "platform_feed", adapter: "aegAXS", adapterVenue: "Brooklyn Steel",
          listingURL: "https://www.bowerypresents.com/brooklyn-steel/",
          registeredHosts: "[\"bowerypresents.com\"]", cadence: "weekly"),
        Source(id: caveatID, householdID: household.id, registryID: "caveat",
          name: "Caveat", type: "venue", priority: "core", area: "Lower East Side",
          mode: .automated, method: "platform_feed", adapter: "caveatJSON",
          listingURL: "https://caveat.nyc/events/", registeredHosts: "[\"caveat.nyc\"]", cadence: "weekly"),
        Source(id: standID, householdID: household.id, registryID: "the-stand",
          name: "The Stand NYC", type: "venue", priority: "core", area: "Union Square",
          mode: .automated, method: "structured_html", listingURL: "https://thestandnyc.com/shows",
          registeredHosts: "[\"thestandnyc.com\"]", cadence: "nightly",
          pagination: #"{"kind":"months","template":"https://thestandnyc.com/shows/{yyyy-MM}","months_ahead":1}"#)
      ]
      for source in sources { try Source.insert { Source.Draft(source) }.execute(db) }
    }
    let emptyPageClient = SourceCheckClient(fetch: { url, _ in
      Self.fixtureResponse(for: url, emptyBoweryPage: true, bowery: bowery, steel: steel, caveat: caveat)
    }, wait: { _ in })
    let fullPagesClient = SourceCheckClient(fetch: { url, _ in
      Self.fixtureResponse(for: url, emptyBoweryPage: false, bowery: bowery, steel: steel, caveat: caveat)
    }, wait: { _ in })
    let now = Date.now
    let reports = await withDependencies {
      $0.sourceCheckClient = emptyPageClient
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: now)
    }
    #expect(reports.count == 4)
    let boweryReport = reports.first { $0.sourceID == boweryID }
    let steelReport = reports.first { $0.sourceID == steelID }
    let caveatReport = reports.first { $0.sourceID == caveatID }
    let standReport = reports.first { $0.sourceID == standID }
    #expect(boweryReport?.outcome == .succeeded)
    #expect(boweryReport?.listingCount == 20)
    #expect(boweryReport?.rowsWritten == 20)
    #expect(boweryReport?.pagesRead == 1)
    #expect(steelReport?.listingCount == 4)
    #expect(caveatReport?.listingCount == 4)
    #expect(standReport?.outcome == .succeeded)
    #expect(standReport?.pagesRead == 3)
    #expect(standReport?.modelCalls == 3)
    let firstRows = try await database.read { db in try Listing.fetchAll(db) }
    #expect(firstRows.count == 28)
    #expect(firstRows.filter { $0.sourceID == boweryID }.count == 20)
    let metadataBefore = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("listings") }.fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }.sorted()
    }
    let repeated = await withDependencies {
      $0.sourceCheckClient = fullPagesClient
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: now.addingTimeInterval(100))
    }
    let metadataAfter = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("listings") }.fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }.sorted()
    }
    #expect(repeated.allSatisfy { $0.rowsWritten == 0 })
    #expect(repeated.first { $0.sourceID == boweryID }?.pagesRead == 3)
    #expect(repeated.first { $0.sourceID == standID }?.modelCalls == 0)
    #expect(metadataAfter == metadataBefore)
  }

  private func fixtureText(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  private static func fixtureResponse(
    for url: URL, emptyBoweryPage: Bool, bowery: String, steel: String, caveat: String
  ) -> FetchedPage {
    if url.path == "/robots.txt" {
      return FetchedPage(document: "User-agent: *", statusCode: 200, effectiveURL: url, contentType: "text/plain")
    }
    if url.host == "mercuryeastpresents.com" {
      let html = emptyBoweryPage && url.path.contains("/page/") ? "<html></html>" : bowery
      return FetchedPage(document: html, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }
    if url.host?.hasSuffix("bowerypresents.com") == true {
      return FetchedPage(document: steel, statusCode: 200, effectiveURL: url, contentType: "application/json")
    }
    if url.host == "caveat.nyc" {
      return FetchedPage(document: caveat, statusCode: 200, effectiveURL: url, contentType: "application/json")
    }
    return FetchedPage(document: "<html></html>", statusCode: 200, effectiveURL: url, contentType: "text/html")
  }
}
