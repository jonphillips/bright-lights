@testable import BrightLightsChecking
import BrightLightsExtraction
import BrightLightsSchema
import Dependencies
import DependenciesTestSupport
import Foundation
import LLMClientKit
import SQLiteData
import Testing

@Suite(.serialized, .dependencies { try $0.bootstrapBrightLightsDatabase() })
struct RoundsAndBrowserCaptureTests {
  @Dependency(\.defaultDatabase) var database

  @Test func roundsOrderNeverCheckedOverdueAndUpToDateSources() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let never = source("Never", mode: .manual)
    let overdue = source("Overdue", mode: .manual, lastCheckedAt: now.addingTimeInterval(-20 * 24 * 60 * 60))
    let recent = source("Recent", mode: .manual, lastCheckedAt: now.addingTimeInterval(-60))
    var failing = source("Failing", mode: .automated)
    failing.consecutiveFailures = 4
    let result = RoundsProjection(sources: [recent, overdue, never, failing], stays: [], now: now)
    #expect(result.due.map(\.name) == ["Never", "Overdue"])
    #expect(result.notReadingAutomatically.map(\.name) == ["Failing"])
    #expect(result.upToDate.map(\.name) == ["Recent"])
    #expect(result.badgeCount == 3)
  }

  @Test func nextSourceSkipsCurrentAndMovesFromDueToManualLook() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let first = source("A due", mode: .manual)
    let current = source("B due", mode: .manual)
    var failed = source("C failed", mode: .automated)
    failed.consecutiveFailures = Source.manualLookFailureThreshold
    let result = RoundsProjection(sources: [first, current, failed], stays: [], now: now)

    #expect(result.next(after: nil)?.id == first.id)
    #expect(result.next(after: first.id)?.id == current.id)
    #expect(result.next(after: current.id)?.id == first.id)

    let lastDue = RoundsProjection(sources: [current, failed], stays: [], now: now)
    #expect(lastDue.next(after: current.id)?.id == failed.id)
  }

  @Test func nextSourceStartsAtTopAfterCurrentLeavesDue() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let checked = source("Already checked", mode: .manual, lastCheckedAt: now)
    let due = source("Still due", mode: .manual)
    let result = RoundsProjection(sources: [checked, due], stays: [], now: now)

    #expect(result.due.map(\.id) == [due.id])
    #expect(result.next(after: checked.id)?.id == due.id)
  }

  @Test func nextSourceIsNilWhenGroupsAreEmptyOrOnlyContainCurrent() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let current = source("Current", mode: .manual)
    let due = RoundsProjection(sources: [current], stays: [], now: now)
    let empty = RoundsProjection(sources: [], stays: [], now: now)

    #expect(due.next(after: current.id) == nil)
    #expect(empty.next(after: nil) == nil)
  }

  @Test func manualWeeklySourcesUseNightlyCadenceDuringStay() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let checked = now.addingTimeInterval(-24 * 60 * 60)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let arrival = calendar.startOfDay(for: now)
    let stay = Stay(id: UUID(), householdID: UUID(), arrivesOn: arrival, departure: .open)
    let manual = source("Manual", mode: .manual, cadence: "weekly", lastCheckedAt: checked)
    #expect(RoundsProjection(sources: [manual], stays: [], now: now).due.isEmpty)
    #expect(RoundsProjection(sources: [manual], stays: [stay], now: now).due.count == 1)
  }

  @Test func pageMatchingUsesHostCurrentSourceThenListingPrefix() {
    let first = source("A", mode: .manual, listingURL: "https://www.example.com/a", hosts: "[\"www.example.com\"]")
    let second = source("B", mode: .manual, listingURL: "https://example.com/b", hosts: "[\"example.com\"]")
    let page = URL(string: "https://www.example.com/b/show?utm_source=x")!
    #expect(SourcePageMatcher.source(for: page, among: [first, second])?.id == second.id)
    #expect(SourcePageMatcher.source(for: page, among: [first, second], currentSource: first)?.id == first.id)
    #expect(SourcePageMatcher.source(for: URL(string: "https://elsewhere.test/events")!, among: [first, second]) == nil)
  }

  @Test func listingPageIgnoresTrailingSlashQueryAndFragment() {
    let venue = source("Venue", mode: .manual, listingURL: "https://example.com/events/", hosts: "[\"example.com\"]")
    #expect(SourcePageMatcher.isListingPage(URL(string: "https://www.example.com/events?month=2#top")!, for: venue))
    #expect(!SourcePageMatcher.isListingPage(URL(string: "https://example.com/events/artist")!, for: venue))
  }

  @Test func listingMatchAndTieBreakUseAnAppSetStartPage() {
    let source = Source(
      id: UUID(), householdID: UUID(), registryID: "test", name: "Test", type: "venue",
      priority: "core", area: "NYC", mode: .manual, method: "manual",
      listingURL: "https://example.com/home", startPageURL: "https://example.com/events/calendar",
      registeredHosts: "[\"example.com\"]", cadence: "weekly"
    )
    #expect(SourcePageMatcher.isListingPage(URL(string: "https://example.com/events/calendar?month=2")!, for: source))
    #expect(!SourcePageMatcher.isListingPage(URL(string: source.listingURL)!, for: source))
    let other = Source(
      id: UUID(), householdID: source.householdID, registryID: "other", name: "A Other", type: "venue",
      priority: "core", area: "NYC", mode: .manual, method: "manual",
      listingURL: "https://example.com/events/archive", registeredHosts: source.registeredHosts, cadence: "weekly"
    )
    #expect(SourcePageMatcher.source(
      for: URL(string: "https://example.com/events/calendar/tonight")!, among: [other, source]
    )?.id == source.id)
    #expect(SourcePageMatcher.canUseAsStartPage(URL(string: "https://sub.example.com/events")!, for: source))
    #expect(!SourcePageMatcher.canUseAsStartPage(URL(string: "https://other.test/events")!, for: source))
  }

  @Test func browserCaptureWritesBrowserRowsAndRecordsOnlyNonemptyListingPage() async throws {
    let fixtureURL = try #require(Bundle.module.url(forResource: "bowery-ballroom", withExtension: "html", subdirectory: "Fixtures"))
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let householdID = try await database.write { try Household.ensureDefault(in: $0).id }
    let venue = Source(id: UUID(), householdID: householdID, registryID: "bowery-ballroom", name: "Bowery Ballroom",
      type: "venue", priority: "core", area: "NYC", mode: .manual, method: "structured_html",
      adapter: "mercuryEast", adapterVenue: "Bowery Ballroom", listingURL: "https://mercuryeastpresents.com/bowery-ballroom/",
      registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly")
    let absent = Listing(id: UUID(), sourceID: venue.id, stableKey: "not-on-page", title: "Still listed",
      startsAt: Date(timeIntervalSince1970: 2_100_000_000), rung: .adapter, capturedBy: .mac)
    try await database.write { db in try Source.insert { Source.Draft(venue) }.execute(db) }
    try await database.write { db in try Listing.insert { Listing.Draft(absent) }.execute(db) }
    let time = Date(timeIntervalSince1970: 1_900_000_000)
    let engine = BrowserCapture()
    let report = try await withDependencies {
      $0.apiKeyStore = APIKeyStore(read: { _ in nil }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      try await engine.capture(source: venue,
        pageURL: URL(string: "https://mercuryeastpresents.com/bowery-ballroom/?view=all")!, html: html,
        in: database, now: time)
    }
    #expect(!report.listings.isEmpty)
    #expect(report.newListings == report.listings.count)
    #expect(try await database.read { db in
      try Listing.where { $0.sourceID.eq(venue.id) }.fetchAll(db).filter { $0.id != absent.id }
        .allSatisfy { $0.capturedBy == .browser }
    })
    let updated = try await database.read { try Source.find(venue.id).fetchOne($0) }
    #expect(updated?.lastCheckedAt == time)
    #expect(updated?.lastCheckNote?.hasPrefix("Captured in the browser") == true)
    #expect(updated?.lastContentHash == nil)
    #expect(try await database.read { try Listing.find(absent.id).fetchOne($0)?.status == .listed })

    let repeatReport = try await engine.capture(source: venue,
      pageURL: URL(string: "https://mercuryeastpresents.com/bowery-ballroom/?view=all")!, html: html,
      in: database, now: time.addingTimeInterval(10))
    #expect(repeatReport.rowsWritten == 0)
    #expect(repeatReport.newListings == 0)

    try await database.write { db in
      try Listing.where { $0.sourceID.eq(venue.id) }.update { $0.capturedBy = #bind(ListingCaptureSource.mac) }.execute(db)
    }
    let macOverlap = try await engine.capture(source: venue,
      pageURL: URL(string: "https://mercuryeastpresents.com/bowery-ballroom/?mac-copy=1")!, html: html,
      in: database, now: time.addingTimeInterval(20))
    #expect(macOverlap.rowsWritten == 0)
    #expect(macOverlap.newListings == 0)
  }

  @Test func browserCaptureOnAnotherPageAndWithNoListingsDoesNotRecordACheck() async throws {
    let fixtureURL = try #require(Bundle.module.url(forResource: "bowery-ballroom", withExtension: "html", subdirectory: "Fixtures"))
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let householdID = try await database.write { try Household.ensureDefault(in: $0).id }
    let priorCheck = Date(timeIntervalSince1970: 1_899_000_000)
    let venue = Source(id: UUID(), householdID: householdID, registryID: "bowery-other-page", name: "Bowery Ballroom",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
      adapter: "mercuryEast", adapterVenue: "Bowery Ballroom", listingURL: "https://mercuryeastpresents.com/bowery-ballroom/",
      registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly", lastCheckedAt: priorCheck,
      lastCheckOutcome: .failed, consecutiveFailures: 3, lastCheckNote: "challenge")
    try await database.write { db in try Source.insert { Source.Draft(venue) }.execute(db) }
    let engine = BrowserCapture()
    let result = try await withDependencies {
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = StubModelClient.constant(#"{"listings":[]}"#)
    } operation: {
      let otherPage = try await engine.capture(source: venue,
        pageURL: URL(string: "https://mercuryeastpresents.com/artist/liana-flores")!, html: html, in: database)
      let emptyPage = try await engine.capture(source: venue,
        pageURL: URL(string: "https://mercuryeastpresents.com/bowery-ballroom/")!, html: "<html><body>Nothing</body></html>", in: database)
      return (otherPage, emptyPage)
    }
    #expect(!result.0.listings.isEmpty)
    #expect(result.1.listings.isEmpty)
    let updated = try await database.read { try Source.find(venue.id).fetchOne($0) }
    #expect(updated?.lastCheckedAt == priorCheck)
    #expect(updated?.lastCheckOutcome == .failed)
    #expect(updated?.consecutiveFailures == 0)
    #expect(updated?.needsManualLook == false)
  }

  @Test func browserCaptureCachesModelRungBySourceURLAndPageHash() async throws {
    let source = self.source("Model source", mode: .manual)
    let pageURL = URL(string: source.listingURL)!
    let calls = CaptureModelCallCounter()
    let engine = BrowserCapture()
    let reports = try await withDependencies {
      $0.apiKeyStore = APIKeyStore(read: { _ in "test-key" }, write: { _, _ in })
      $0.modelClient = StubModelClient { _ in
        await calls.increment()
        return ModelResponse(text: #"{"listings":[]}"#)
      }
    } operation: {
      let first = try await engine.capture(source: source, pageURL: pageURL, html: "<main>New show</main>", in: database)
      let repeated = try await engine.capture(source: source, pageURL: pageURL, html: "<main>New show</main>", in: database)
      let changed = try await engine.capture(source: source, pageURL: pageURL, html: "<main>Changed show</main>", in: database)
      return (first, repeated, changed)
    }
    #expect(reports.0.modelCalls == 1)
    #expect(reports.1.modelCalls == 1)
    #expect(reports.1.rowsWritten == 0)
    #expect(reports.2.modelCalls == 1)
    #expect(await calls.count() == 2)
  }

  @Test func passiveCaptureRulesAllowVenuesAndPresentersButNotAggregators() async throws {
    let fixtureURL = try #require(Bundle.module.url(forResource: "bowery-ballroom", withExtension: "html", subdirectory: "Fixtures"))
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let venue = source("Venue", mode: .manual)
    let presenter = Source(id: UUID(), householdID: UUID(), registryID: "presenter", name: "Presenter",
      type: "presenter", priority: "core", area: "NYC", mode: .manual, method: "structured_html",
      listingURL: "https://example.com/events", registeredHosts: "[\"example.com\"]", cadence: "weekly")
    let householdID = try await database.write { try Household.ensureDefault(in: $0).id }
    let aggregator = Source(id: UUID(), householdID: householdID, registryID: "aggregator", name: "Aggregator",
      type: "aggregator", priority: "core", area: "NYC", mode: .manual, method: "structured_html",
      adapter: "mercuryEast", adapterVenue: "Bowery Ballroom",
      listingURL: "https://mercuryeastpresents.com/bowery-ballroom/",
      registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly")
    #expect(SourcePageMatcher.allowsPassiveCapture(venue))
    #expect(SourcePageMatcher.allowsPassiveCapture(presenter))
    #expect(!SourcePageMatcher.allowsPassiveCapture(aggregator))
    try await database.write { db in try Source.insert { Source.Draft(aggregator) }.execute(db) }
    let requested = try await BrowserCapture().capture(source: aggregator,
      pageURL: URL(string: aggregator.listingURL)!, html: html, in: database)
    #expect(!requested.listings.isEmpty)
  }

  @Test func feedSourceCapturesItsHTMLListingPageAsHTML() async throws {
    let fixtureURL = try #require(Bundle.module.url(forResource: "bowery-ballroom", withExtension: "html", subdirectory: "Fixtures"))
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let householdID = try await database.write { try Household.ensureDefault(in: $0).id }
    let webSource = Source(id: UUID(), householdID: householdID, registryID: "html-with-feed", name: "Venue with feed",
      type: "venue", priority: "core", area: "NYC", mode: .manual, method: "platform_feed",
      adapter: "mercuryEast", adapterVenue: "Bowery Ballroom",
      listingURL: "https://mercuryeastpresents.com/bowery-ballroom/",
      feedURL: "https://mercuryeastpresents.com/api/events.json",
      registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly")
    try await database.write { db in try Source.insert { Source.Draft(webSource) }.execute(db) }
    let report = try await BrowserCapture().capture(source: webSource,
      pageURL: URL(string: webSource.listingURL)!, html: html, in: database)
    #expect(!report.listings.isEmpty)
  }

  @Test func sourceExtractionDescriptorPreservesTheCheckersAdapterKeys() throws {
    let fixtureURL = try #require(Bundle.module.url(forResource: "bowery-ballroom", withExtension: "html", subdirectory: "Fixtures"))
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)
    let source = Source(id: UUID(), householdID: UUID(), registryID: "bowery-ballroom", name: "Bowery Ballroom",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
      adapter: "mercuryEast", listingURL: "https://mercuryeastpresents.com/boweryballroom/",
      registeredHosts: "[\"mercuryeastpresents.com\"]", cadence: "weekly")
    let listings = ExtractionEngine().deterministicListings(.html(html),
      sourceURL: URL(string: source.listingURL)!, source: source.extractionDescriptor)
    #expect(listings.count == 20)
    #expect(listings.first?.stableKey == "bowery-ballroom:https://mercuryeastpresents.com/tm-event/liana-flores")
  }

  private func source(_ name: String, mode: SourceMode, cadence: String = "weekly",
    lastCheckedAt: Date? = nil, listingURL: String = "https://example.com/events", hosts: String = "[\"example.com\"]") -> Source {
    Source(id: UUID(), householdID: UUID(), registryID: name, name: name, type: "venue", priority: "core",
      area: "NYC", mode: mode, method: "structured_html", listingURL: listingURL,
      registeredHosts: hosts, cadence: cadence, lastCheckedAt: lastCheckedAt)
  }
}

private actor CaptureModelCallCounter {
  private var value = 0
  func increment() { value += 1 }
  func count() -> Int { value }
}
