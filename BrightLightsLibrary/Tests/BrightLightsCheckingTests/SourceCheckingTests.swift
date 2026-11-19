@testable import BrightLightsChecking
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

  @Test func robotsRulesSupportGroupedAgentsGlobsAnchorsQueriesAndDelay() {
    let rules = RobotsRules(text: """
      User-agent: *
      User-agent: Googlebot
      Disallow: /private
      Disallow: /*?sort=
      Disallow: /exact$
      Crawl-delay: 3
      User-agent: BrightLights
      Disallow: /members
      """)
    #expect(!rules.allows(URL(string: "https://example.com/private/list")!))
    #expect(!rules.allows(URL(string: "https://example.com/a?sort=latest")!))
    #expect(!rules.allows(URL(string: "https://example.com/exact")!))
    #expect(rules.allows(URL(string: "https://example.com/exact/child")!))
    #expect(!rules.allows(URL(string: "https://example.com/members/list")!))
    #expect(rules.allows(URL(string: "https://example.com/events")!))
    #expect(rules.crawlDelay == 3)
  }

  @Test func challengeDetectionIgnoresNewsletterRecaptcha() {
    #expect(!SourceChecker.isChallengePage("<html><title>Events</title><form>Newsletter reCAPTCHA</form></html>"))
    #expect(SourceChecker.isChallengePage("<html><title>Just a moment...</title><script src='/cdn-cgi/challenge-platform'></script></html>"))
    #expect(SourceChecker.isChallengePage("<html><title>Access denied</title></html>"))
  }

  @Test func challengePageFailsButNewsletterRecaptchaCanSucceed() async throws {
    let challenged = try await insertSource(registryID: "cloudflare", listingURL: "https://example.com/events", method: "rendered_scrape")
    let challengeClient = SourceCheckClient(fetch: { url, _ in
      FetchedPage(document: "<html><title>Just a moment...</title><div>cf-chl</div></html>", statusCode: 200,
        effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let challengeReport = await runPass(client: challengeClient, apiKey: nil, now: .now)
    #expect(challengeReport.first?.sourceID == challenged.id)
    #expect(challengeReport.first?.outcome == .failed)
    #expect(challengeReport.first?.note == "bot-challenge page")

    let newsletter = try await insertSource(registryID: "newsletter", listingURL: "https://example.com/newsletter", method: "rendered_scrape")
    let newsletterClient = SourceCheckClient(fetch: { url, _ in
      FetchedPage(document: "<html><title>Events</title><form>Newsletter reCAPTCHA</form></html>", statusCode: 200,
        effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let newsletterReports = await runPass(client: newsletterClient, apiKey: "test-key", now: .now)
    #expect(newsletterReports.contains { $0.sourceID == newsletter.id && $0.outcome == .succeeded })
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

  @Test func stayIncludesEveryHourOfDepartureDayInNewYork() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let departure = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_900_000_000))
    let now = calendar.date(byAdding: .hour, value: 1, to: departure)!
    let source = Source(id: UUID(), householdID: UUID(), registryID: "weekly", name: "Weekly",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "html",
      listingURL: "https://example.com", registeredHosts: "[]", cadence: "weekly",
      lastCheckedAt: now.addingTimeInterval(-2 * 24 * 60 * 60))
    let stay = Stay(id: UUID(), householdID: source.householdID,
      arrivesOn: calendar.date(byAdding: .day, value: -3, to: departure)!,
      departure: .tentative(departure))
    #expect(SourceCadence.isDue(source, at: now, stays: [stay]))
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
    source.lastCheckOutcome = .succeeded
    #expect(!source.needsManualLook)
    source.lastCheckOutcome = .failed
    #expect(source.needsManualLook)
  }

  @Test func leaseRejectsANonHolderAndClaimWritesAllLeaseFields() async throws {
    let holderID = UUID(); let deviceID = UUID(); let claimedAt = Date(timeIntervalSince1970: 1_900_000_000)
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      try Household.find(household.id).update { $0.checkerDeviceID = #bind(holderID) }.execute(db)
      #expect(try !CheckerLease.mayCheck(deviceID: deviceID, checkerEnabled: true, syncEnabled: true, in: db))
      try CheckerLease.claim(deviceID: deviceID, name: "Jon's Mac", at: claimedAt, in: db)
      let claimed = try #require(try Household.canonical.fetchOne(db))
      #expect(claimed.checkerDeviceID == deviceID)
      #expect(claimed.checkerDeviceName == "Jon's Mac")
      #expect(claimed.checkerClaimedAt == claimedAt)
      #expect(try CheckerLease.mayCheck(deviceID: deviceID, checkerEnabled: true, syncEnabled: true, in: db))
    }
  }

  @Test func disablingCheckerStopsChecksButLeavesHouseholdLease() async throws {
    let deviceID = UUID(); let claimedAt = Date(timeIntervalSince1970: 1_900_000_000)
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      try CheckerLease.claim(deviceID: deviceID, name: "Jon's Mac", at: claimedAt, in: db)
      #expect(try CheckerLease.holds(deviceID: deviceID, in: db))
      #expect(try !CheckerLease.mayCheck(deviceID: deviceID, checkerEnabled: false, syncEnabled: true, in: db))
      let unchanged = try #require(try Household.find(household.id).fetchOne(db))
      #expect(unchanged.checkerDeviceID == deviceID)
      #expect(unchanged.checkerClaimedAt == claimedAt)
    }
  }

  @Test func fixturePassUpsertsOnceAndSecondPassWritesNoListings() async throws {
    let boweryID = UUID(); let steelID = UUID(); let caveatID = UUID(); let standID = UUID(); let unionID = UUID()
    let bowery = try fixtureText("bowery-ballroom.html")
    let steel = try fixtureText("brooklyn-steel.json")
    let caveat = try fixtureText("caveat.json")
    let unionHall = #"<html><script type="application/ld+json">{"@type":"Event","name":"Union Hall Show","startDate":"2030-03-12T20:00:00-04:00","url":"https://unionhallny.com/event/1"}</script></html>"#
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
          feedURL: "https://aegwebprod.blob.core.windows.net/json/resources/8/events/d099bg4x01/events.json",
          registeredHosts: "[\"bowerypresents.com\",\"aegwebprod.blob.core.windows.net\"]", cadence: "weekly"),
        Source(id: caveatID, householdID: household.id, registryID: "caveat",
          name: "Caveat", type: "venue", priority: "core", area: "Lower East Side",
          mode: .automated, method: "platform_feed", adapter: "caveatJSON",
          listingURL: "https://caveat.nyc/events/", feedURL: "https://caveat.nyc/api/events/listings",
          registeredHosts: "[\"caveat.nyc\"]", cadence: "weekly"),
        Source(id: standID, householdID: household.id, registryID: "the-stand",
          name: "The Stand NYC", type: "venue", priority: "core", area: "Union Square",
          mode: .automated, method: "structured_html", listingURL: "https://thestandnyc.com/shows",
          registeredHosts: "[\"thestandnyc.com\"]", cadence: "nightly",
          pagination: #"{"kind":"months","template":"https://thestandnyc.com/shows/{yyyy-MM}","months_ahead":1}"#),
        Source(id: unionID, householdID: household.id, registryID: "union-hall",
          name: "Union Hall", type: "venue", priority: "core", area: "Park Slope",
          mode: .automated, method: "platform_feed", listingURL: "https://unionhallny.com/events",
          registeredHosts: "[\"unionhallny.com\"]", cadence: "weekly")
      ]
      for source in sources { try Source.insert { Source.Draft(source) }.execute(db) }
    }
    let emptyPageClient = SourceCheckClient(fetch: { url, _ in
      Self.fixtureResponse(for: url, emptyBoweryPage: true, bowery: bowery, steel: steel, caveat: caveat, unionHall: unionHall)
    }, wait: { _ in })
    let fullPagesClient = SourceCheckClient(fetch: { url, _ in
      Self.fixtureResponse(for: url, emptyBoweryPage: false, bowery: bowery, steel: steel, caveat: caveat, unionHall: unionHall)
    }, wait: { _ in })
    let now = Date.now
    let reports = await withDependencies {
      $0.sourceCheckClient = emptyPageClient
      $0.uuid = .incrementing
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: now)
    }
    #expect(reports.count == 5)
    let boweryReport = reports.first { $0.sourceID == boweryID }
    let steelReport = reports.first { $0.sourceID == steelID }
    let caveatReport = reports.first { $0.sourceID == caveatID }
    let standReport = reports.first { $0.sourceID == standID }
    let unionReport = reports.first { $0.sourceID == unionID }
    #expect(boweryReport?.outcome == .succeeded)
    #expect(boweryReport?.listingCount == 20)
    #expect(boweryReport?.rowsWritten == 20)
    #expect(boweryReport?.pagesRead == 1)
    #expect(steelReport?.listingCount == 4)
    #expect(caveatReport?.listingCount == 4)
    #expect(unionReport?.listingCount == 1)
    #expect(unionReport?.modelCalls == 0)
    #expect(standReport?.outcome == .succeeded)
    #expect(standReport?.pagesRead == 3)
    #expect(standReport?.modelCalls == 3)
    let firstRows = try await database.read { db in try Listing.fetchAll(db) }
    #expect(firstRows.count == 29)
    #expect(firstRows.filter { $0.sourceID == boweryID }.count == 20)
    let metadataBefore = try await database.read { db in
      try SyncMetadata.where { $0.recordType.eq("listings") }.fetchAll(db)
        .map { "\($0.id.recordPrimaryKey):\($0.userModificationTime)" }.sorted()
    }
    let repeated = await withDependencies {
      $0.sourceCheckClient = fullPagesClient
      $0.uuid = .incrementing
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
    #expect(repeated.first { $0.sourceID == boweryID }?.pagesRead == 2)
    #expect(repeated.first { $0.sourceID == standID }?.modelCalls == 0)
    #expect(metadataAfter == metadataBefore)
  }

  @Test func pagesPaginationStopsAtMaxAndDoesNotMarkUnseenListingsMissing() async throws {
    let source = try await insertSource(registryID: "bowery-ballroom", listingURL: "https://mercuryeastpresents.com/boweryballroom/",
      adapter: "mercuryEast", pagination: #"{"kind":"pages","template":"https://mercuryeastpresents.com/boweryballroom/page/{n}/","first":2,"max":3}"#)
    let unseen = Listing(id: UUID(), sourceID: source.id, stableKey: "unseen", title: "Unseen",
      startsAt: Date(timeIntervalSince1970: 2_000_000_000), rung: .adapter, capturedBy: .mac)
    try await database.write { db in try Listing.insert { Listing.Draft(unseen) }.execute(db) }
    let bowery = try fixtureText("bowery-ballroom.html")
    let requests = URLRecorder()
    let client = SourceCheckClient(fetch: { url, _ in
      await requests.record(url)
      if url.path == "/robots.txt" {
        return FetchedPage(document: "User-agent: *", statusCode: 200, effectiveURL: url)
      }
      return FetchedPage(document: bowery, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let reports = await runPass(client: client, apiKey: nil, now: Date(timeIntervalSince1970: 1_900_000_000))
    #expect(reports.count == 1)
    #expect(reports[0].pagesRead == 3)
    let pagePaths = await requests.urls().filter { $0.path.contains("/page/") }.map(\.path)
    #expect(pagePaths.count == 2)
    #expect(pagePaths.allSatisfy { $0.contains("/page/2") || $0.contains("/page/3") })
    #expect(try await database.read { try Listing.find(unseen.id).fetchOne($0)?.status } == .listed)
  }

  @Test func emptyFirstPageDoesNotStopPagesPagination() async throws {
    let source = try await insertSource(registryID: "bowery-ballroom", listingURL: "https://mercuryeastpresents.com/boweryballroom/",
      adapter: "mercuryEast", pagination: #"{"kind":"pages","template":"https://mercuryeastpresents.com/boweryballroom/page/{n}/","first":2,"max":4}"#)
    let bowery = try fixtureText("bowery-ballroom.html")
    let requests = URLRecorder()
    let client = SourceCheckClient(fetch: { url, _ in
      await requests.record(url)
      let document = url.path == "/robots.txt" ? "User-agent: *" :
        (url.path == "/boweryballroom/" ? "<html></html>" :
          (url.path.contains("/page/2") ? bowery : "<html></html>"))
      return FetchedPage(document: document, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let reports = await runPass(client: client, apiKey: "test-key", now: .now)
    let requestedPaths = await requests.urls().map(\.path)
    #expect(requestedPaths.contains { $0.contains("/page/2") })
    #expect(reports.first?.sourceID == source.id)
    #expect(reports.first?.outcome == .succeeded)
    #expect(reports.first?.listingCount == 20)
    #expect(reports.first?.pagesRead == 2)
  }

  @Test func emptyPageOneUsesTheZeroDropFailureRule() async throws {
    let source = try await insertSource(registryID: "empty-bowery", listingURL: "https://mercuryeastpresents.com/boweryballroom/",
      adapter: "mercuryEast", pagination: #"{"kind":"pages","template":"https://mercuryeastpresents.com/boweryballroom/page/{n}/","first":2,"max":3}"#,
      lastListingCount: 3)
    let client = SourceCheckClient(fetch: { url, _ in
      FetchedPage(document: url.path == "/robots.txt" ? "User-agent: *" : "<html></html>",
        statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let reports = await runPass(client: client, apiKey: "test-key", now: .now)
    #expect(reports.first?.outcome == .failed)
    #expect(reports.first?.note == "returned no listings (was 3)")
    let updated = try await database.read { try Source.find(source.id).fetchOne($0) }
    #expect(updated?.needsManualLook == true)
    #expect(updated?.lastListingCount == 3)
  }

  @Test func monthlyPaginationReadsPastAnEmptyMonth() async throws {
    _ = try await insertSource(registryID: "the-stand", listingURL: "https://thestandnyc.com/shows",
      method: "rendered_scrape", pagination: #"{"kind":"months","template":"https://thestandnyc.com/shows/{yyyy-MM}","months_ahead":2}"#)
    let requests = URLRecorder()
    let december = #"<html><script type="application/ld+json">{"@type":"Event","name":"December Show","startDate":"2026-12-12T20:00:00-05:00","url":"https://thestandnyc.com/shows/show/12"}</script></html>"#
    let client = SourceCheckClient(fetch: { url, _ in
      await requests.record(url)
      if url.path == "/robots.txt" {
        return FetchedPage(document: "User-agent: *", statusCode: 200, effectiveURL: url)
      }
      return FetchedPage(document: url.path == "/shows/2026-12" ? december : "<html></html>",
        statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let now = ISO8601DateFormatter().date(from: "2026-11-19T12:00:00Z")!
    let reports = await runPass(client: client, apiKey: "test-key", now: now)
    let months = await requests.urls().map(\.path).filter { $0.hasPrefix("/shows/20") }
    #expect(months == ["/shows/2026-11", "/shows/2026-12", "/shows/2027-01"])
    #expect(reports.first?.pagesRead == 4)
    #expect(reports.first?.listingCount == 1)
  }

  @Test func laterPageFailureIsPartialAndDoesNotMarkListingsMissing() async throws {
    let source = try await insertSource(registryID: "bowery-ballroom", listingURL: "https://mercuryeastpresents.com/boweryballroom/",
      adapter: "mercuryEast", pagination: #"{"kind":"pages","template":"https://mercuryeastpresents.com/boweryballroom/page/{n}/","first":2,"max":3}"#)
    let unseen = Listing(id: UUID(), sourceID: source.id, stableKey: "unseen", title: "Unseen",
      startsAt: Date(timeIntervalSince1970: 2_000_000_000), rung: .adapter, capturedBy: .mac)
    try await database.write { db in try Listing.insert { Listing.Draft(unseen) }.execute(db) }
    let bowery = try fixtureText("bowery-ballroom.html")
    let client = SourceCheckClient(fetch: { url, _ in
      if url.path == "/robots.txt" { return FetchedPage(document: "User-agent: *", statusCode: 200, effectiveURL: url) }
      if url.path.contains("/page/3") { throw SourceCheckError.fetchFailed("fixture failure") }
      return FetchedPage(document: bowery, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let reports = await runPass(client: client, apiKey: nil, now: Date(timeIntervalSince1970: 1_900_000_000))
    #expect(reports[0].outcome == .succeeded)
    #expect(reports[0].note?.contains("partial check") == true)
    #expect(try await database.read { try Listing.find(unseen.id).fetchOne($0)?.status } == .listed)
  }

  @Test func unreachableRobotsFileDoesNotPreventTheSourceFetch() async throws {
    let source = try await insertSource(registryID: "jsonld", listingURL: "https://example.com/events")
    let event = #"<script type="application/ld+json">{"@type":"Event","name":"Event","startDate":"2030-03-12T20:00:00-04:00","url":"https://example.com/event/1"}</script>"#
    let client = SourceCheckClient(fetch: { url, _ in
      if url.path == "/robots.txt" { throw SourceCheckError.fetchFailed("robots unavailable") }
      return FetchedPage(document: event, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }, wait: { _ in })
    let reports = await runPass(client: client, apiKey: nil, now: .now)
    #expect(reports.first?.sourceID == source.id)
    #expect(reports.first?.outcome == .succeeded)
  }

  @Test func changedModelHashCallsTheModelAgain() async throws {
    let source = try await insertSource(registryID: "model", listingURL: "https://example.com/events", method: "rendered_scrape")
    let modelCalls = ModelCallCounter()
    let client = SourceCheckClient(fetch: { _, _ in
      FetchedPage(document: "<main>Changed show</main>", statusCode: 200,
        effectiveURL: URL(string: "https://example.com/events")!, contentType: "text/html")
    }, wait: { _ in })
    let model = StubModelClient { _ in
      await modelCalls.increment()
      return ModelResponse(text: #"{"listings":[]}"#)
    }
    let first = await withDependencies {
      $0.sourceCheckClient = client
      $0.uuid = .incrementing
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = model
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: .now)
    }
    #expect(first.first?.modelCalls == 1)
    let updatedClient = SourceCheckClient(fetch: { _, _ in
      FetchedPage(document: "<main>Changed show tonight</main>", statusCode: 200,
        effectiveURL: URL(string: "https://example.com/events")!, contentType: "text/html")
    }, wait: { _ in })
    let second = await withDependencies {
      $0.sourceCheckClient = updatedClient
      $0.uuid = .incrementing
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = model
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: .now.addingTimeInterval(60))
    }
    #expect(second.first?.sourceID == source.id)
    #expect(second.first?.modelCalls == 1)
    #expect(await modelCalls.count() == 2)
  }

  private func fixtureText(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func insertSource(
    registryID: String, listingURL: String, method: String = "structured_html", adapter: String? = nil,
    pagination: String? = nil, lastListingCount: Int? = nil
  ) async throws -> Source {
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      let registeredHosts = URL(string: listingURL)?.host.map { "[\"\($0)\"]" } ?? "[]"
      let source = Source(id: UUID(), householdID: household.id, registryID: registryID, name: registryID,
        type: "venue", priority: "core", area: "NYC", mode: .automated, method: method,
        adapter: adapter, listingURL: listingURL, registeredHosts: registeredHosts, cadence: "weekly",
        lastListingCount: lastListingCount, pagination: pagination)
      try Source.insert { Source.Draft(source) }.execute(db)
      return source
    }
  }

  private func runPass(client: SourceCheckClient, apiKey: String?, now: Date) async -> [SourceCheckReport] {
    await withDependencies {
      $0.sourceCheckClient = client
      $0.uuid = .incrementing
      $0.apiKeyStore = APIKeyStore(read: { _ in apiKey }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      await SourceChecker().runPass(in: database, checkAll: true, now: now)
    }
  }

  private static func fixtureResponse(
    for url: URL, emptyBoweryPage: Bool, bowery: String, steel: String, caveat: String, unionHall: String
  ) -> FetchedPage {
    if url.path == "/robots.txt" {
      return FetchedPage(document: "User-agent: *", statusCode: 200, effectiveURL: url, contentType: "text/plain")
    }
    if url.host == "mercuryeastpresents.com" {
      let html = emptyBoweryPage && url.path.contains("/page/") ? "<html></html>" : bowery
      return FetchedPage(document: html, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }
    if url.absoluteString == "https://aegwebprod.blob.core.windows.net/json/resources/8/events/d099bg4x01/events.json" {
      return FetchedPage(document: steel, statusCode: 200, effectiveURL: url, contentType: "application/json")
    }
    if url.absoluteString == "https://caveat.nyc/api/events/listings" {
      return FetchedPage(document: caveat, statusCode: 200, effectiveURL: url, contentType: "application/json")
    }
    if url.host == "unionhallny.com" {
      return FetchedPage(document: unionHall, statusCode: 200, effectiveURL: url, contentType: "text/html")
    }
    return FetchedPage(document: "<html></html>", statusCode: 200, effectiveURL: url, contentType: "text/html")
  }
}

private actor URLRecorder {
  private var recorded: [URL] = []
  func record(_ url: URL) { recorded.append(url) }
  func urls() -> [URL] { recorded }
}

private actor ModelCallCounter {
  private var calls = 0
  func increment() { calls += 1 }
  func count() -> Int { calls }
}
