import BrightLightsExtraction
import BrightLightsSchema
import CryptoKit
import Dependencies
import Foundation
import LLMClientKit
import OSLog
import SQLiteData

private enum SourceCheckingPolicy {
  static let requestInterval: TimeInterval = 1 // M1 S3 minimum between source requests.
  static let pruningAge: TimeInterval = 30 * 24 * 60 * 60 // ADR-0002 retention window.
  static let zeroDropPreviousCountThreshold = 3 // Separate from the consecutive-failure threshold.
}

private enum PaginationRule {
  case pages(template: String, first: Int, max: Int)
  case months(template: String, monthsAhead: Int)
}

private struct PaginatedFetchError: LocalizedError {
  var note: String
  var pagesRead: Int
  var errorDescription: String? { note }
}

private struct ExtractionBatch {
  var listings: [ExtractedListing]
  var warnings: [String]
  var modelCalls: Int
  var rungs: [ExtractionRung]
}

private struct PageFetchResult {
  var pages: [FetchedPage]
  var complete: Bool
  var partialFailure: Bool
}

private actor PassPacer {
  private var lastRequestEndedAt: Date?
  private var robotsByHost: [String: RobotsRules] = [:]

  func wait(for delay: TimeInterval, using wait: @Sendable (Duration) async throws -> Void) async throws {
    guard let lastRequestEndedAt else { return }
    let remaining = delay - Date.now.timeIntervalSince(lastRequestEndedAt)
    if remaining > 0 { try await wait(.milliseconds(Int64(remaining * 1_000))) }
  }

  func recordRequestEnd() { lastRequestEndedAt = .now }
  func rules(for host: String) -> RobotsRules? { robotsByHost[host] }
  func cache(_ rules: RobotsRules, for host: String) { robotsByHost[host] = rules }
}

public struct SourceCheckReport: Identifiable, Sendable, Equatable {
  public var id: UUID { sourceID }
  public var sourceID: UUID
  public var outcome: SourceCheckOutcome
  public var listingCount: Int
  public var pagesRead: Int
  public var rungs: [ExtractionRung]
  public var modelCalls: Int
  public var note: String?
  public var rowsWritten: Int
}

public struct SourceChecker: Sendable {
  @Dependency(\.sourceCheckClient) private var client
  @Dependency(\.apiKeyStore) private var apiKeyStore

  public init() {}

  public func runPass(in database: any DatabaseWriter, checkAll: Bool = false, now: Date = .now) async -> [SourceCheckReport] {
    let sources = (try? await database.read { try Source.canonical.fetchAll($0) }) ?? []
    let stays = (try? await database.read { try Stay.fetchAll($0) }) ?? []
    let due = checkAll ? sources.filter { $0.mode == .automated && $0.retiredAt == nil }
      .sorted { $0.lastCheckedAt ?? .distantPast < $1.lastCheckedAt ?? .distantPast }
      : SourceCadence.orderedDue(sources, at: now, stays: stays)
    var reports: [SourceCheckReport] = []
    let pacer = PassPacer()
    for source in due {
      let report = await check(source, in: database, now: now, pacer: pacer)
      reports.append(report)
      logReport(report, source: source)
    }
    try? await database.write { db in
      try Listing.pruneExpired(before: now.addingTimeInterval(-SourceCheckingPolicy.pruningAge), in: db)
    }
    return reports
  }

  private func check(_ source: Source, in database: any DatabaseWriter, now: Date, pacer: PassPacer) async -> SourceCheckReport {
    var pagesRead = 0
    var calls = 0
    var rungs: [ExtractionRung] = []
    do {
      let pageResult = try await fetchPages(source, now: now, pacer: pacer)
      let pages = pageResult.pages
      pagesRead = pages.count
      let documents = documents(from: pages, source: source)
      let hash = Self.combinedHash(documents.map { ExtractionEngine.pageHash(for: $0.1) })
      let descriptor = descriptor(for: source)
      let requiresModel = requiresModel(for: documents, source: descriptor)
      let modelAllowed = apiKeyStore.key(.anthropic) != nil || apiKeyStore.key(.openai) != nil
      if requiresModel && !modelAllowed { throw SourceCheckError.noModelKey }
      if requiresModel && source.lastContentHash == hash {
        try await recordUnchanged(source, database: database, now: now)
        return SourceCheckReport(sourceID: source.id, outcome: .succeeded,
          listingCount: source.lastListingCount ?? 0, pagesRead: pages.count,
          rungs: [.model], modelCalls: 0,
          note: "unchanged; model not called", rowsWritten: 0)
      }
      let batch = try await extractDocuments(documents, source: source, descriptor: descriptor)
      calls = batch.modelCalls
      rungs = batch.rungs
      let unique = Dictionary(batch.listings.map { ($0.stableKey, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.stableKey < $1.stableKey }
      if unique.isEmpty, let previousCount = source.lastListingCount,
        previousCount >= SourceCheckingPolicy.zeroDropPreviousCountThreshold {
        throw SourceCheckError.noListings(previousCount: previousCount)
      }
      var warnings = batch.warnings
      if pageResult.partialFailure { warnings.append("partial check; a later page failed") }
      let note = warnings.isEmpty ? nil : String(warnings.joined(separator: "; ").prefix(Source.checkNoteCharacterLimit))
      let usedModel = calls > 0
      let rowsWritten = try await recordSuccess(
        unique, source: source, complete: pageResult.complete, database: database,
        now: now, usedModel: usedModel, hash: hash, note: note
      )
      return SourceCheckReport(sourceID: source.id, outcome: .succeeded, listingCount: unique.count,
        pagesRead: pages.count, rungs: rungs.sorted { $0.rawValue < $1.rawValue },
        modelCalls: calls, note: note, rowsWritten: rowsWritten)
    } catch {
      let fetchFailure = error as? PaginatedFetchError
      let note = String((fetchFailure?.note ?? error.localizedDescription).prefix(Source.checkNoteCharacterLimit))
      pagesRead = max(pagesRead, fetchFailure?.pagesRead ?? 0)
      try? await database.write { db in
        try Source.find(source.id).update {
          $0.lastCheckedAt = #bind(now); $0.lastCheckOutcome = #bind(SourceCheckOutcome.failed)
          $0.consecutiveFailures = #bind(source.consecutiveFailures + 1); $0.lastCheckNote = #bind(note)
        }.execute(db)
      }
      return SourceCheckReport(sourceID: source.id, outcome: .failed, listingCount: source.lastListingCount ?? 0,
        pagesRead: pagesRead, rungs: rungs, modelCalls: calls, note: note, rowsWritten: 0)
    }
  }

  private func documents(from pages: [FetchedPage], source: Source) -> [(URL, PageDocument)] {
    pages.map { page in
      let isJSON = source.feedURL != nil
      return (page.effectiveURL, isJSON ? .json(page.document) : .html(page.document))
    }
  }

  private func requiresModel(for documents: [(URL, PageDocument)], source: SourceDescriptor) -> Bool {
    let engine = ExtractionEngine()
    return documents.contains { !engine.hasDeterministicRung($0.1, sourceURL: $0.0, source: source) }
  }

  private func extractDocuments(
    _ documents: [(URL, PageDocument)], source: Source, descriptor: SourceDescriptor
  ) async throws -> ExtractionBatch {
    let engine = ExtractionEngine()
    var batch = ExtractionBatch(listings: [], warnings: [], modelCalls: 0, rungs: [])
    for (index, (url, document)) in documents.enumerated() {
      let modelPage = !engine.hasDeterministicRung(document, sourceURL: url, source: descriptor)
      if modelPage { batch.modelCalls += 1 }
      let result: ExtractionResult
      do {
        result = try await engine.extract(document, sourceURL: url, source: descriptor)
      } catch {
        if modelPage { logModelCall(source: source, page: index + 1, pageCount: documents.count, listingCount: 0) }
        throw error
      }
      if modelPage { logModelCall(source: source, page: index + 1, pageCount: documents.count, listingCount: result.listings.count) }
      batch.listings.append(contentsOf: result.listings)
      batch.warnings.append(contentsOf: result.warnings)
      for listing in result.listings {
        if let rung = ExtractionRung(rawValue: listing.rung.rawValue), !batch.rungs.contains(rung) { batch.rungs.append(rung) }
      }
      if modelPage && !batch.rungs.contains(.model) { batch.rungs.append(.model) }
    }
    return batch
  }

  private func logModelCall(source: Source, page: Int, pageCount: Int, listingCount: Int) {
    Logger(subsystem: "com.jonphillips.BrightLights", category: "ModelExtraction")
      .info("source=\(source.id.uuidString, privacy: .public) page=\(page) pages=\(pageCount) listings=\(listingCount)")
  }

  private func logReport(_ report: SourceCheckReport, source: Source) {
    let rungs = report.rungs.map(\.rawValue).joined(separator: ",")
    Logger(subsystem: "com.jonphillips.BrightLights", category: "SourceChecks")
      .info("source=\(source.id.uuidString, privacy: .public) outcome=\(report.outcome.rawValue, privacy: .public) listings=\(report.listingCount, privacy: .public) rungs=\(rungs, privacy: .public) pages=\(report.pagesRead, privacy: .public) modelCalls=\(report.modelCalls, privacy: .public) rowsWritten=\(report.rowsWritten, privacy: .public) note=\(report.note ?? "", privacy: .private)")
  }

  private func recordSuccess(
    _ listings: [ExtractedListing], source: Source, complete: Bool, database: any DatabaseWriter,
    now: Date, usedModel: Bool, hash: String, note: String?
  ) async throws -> Int {
    try await database.write { db in
      let count = try Listing.reconcile(
        listings, sourceID: source.id, complete: complete, now: now, makeID: UUID.init, in: db
      )
      try Source.find(source.id).update {
        $0.lastCheckedAt = #bind(now); $0.lastCheckOutcome = #bind(SourceCheckOutcome.succeeded)
        $0.lastListingCount = #bind(listings.count); $0.consecutiveFailures = #bind(0)
        $0.lastContentHash = #bind(usedModel ? hash : nil as String?); $0.lastCheckNote = #bind(note)
      }.execute(db)
      return count
    }
  }

  private func fetchPages(_ source: Source, now: Date, pacer: PassPacer) async throws -> PageFetchResult {
    let pagination = Self.pagination(source.pagination)
    let urls = try Self.urls(source: source, pagination: pagination, now: now)
    var pages: [FetchedPage] = []
    var complete = true
    var partialFailure = false
    do {
    for (index, url) in urls.enumerated() {
      guard let host = url.host?.lowercased() else { throw SourceCheckError.fetchFailed("URL has no host") }
      if await pacer.rules(for: host) == nil {
        guard let robotsURL = URL(string: "\(url.scheme ?? "https")://\(host)/robots.txt") else {
          throw SourceCheckError.fetchFailed("invalid robots.txt URL")
        }
        let robotsPage = try? await pacedFetch(
          robotsURL, render: false, delay: SourceCheckingPolicy.requestInterval, pacer: pacer
        )
        if robotsPage?.statusCode == 403 || robotsPage?.statusCode == 429 {
          throw SourceCheckError.challenge("robots.txt returned HTTP \(robotsPage?.statusCode ?? 0)")
        }
        await pacer.cache(RobotsRules(text: robotsPage?.statusCode == 200 ? robotsPage?.document ?? "" : ""), for: host)
      }
      let rules = await pacer.rules(for: host) ?? RobotsRules(text: "")
      guard rules.allows(url) else { throw SourceCheckError.disallowed(url) }
      let delay = max(SourceCheckingPolicy.requestInterval, rules.crawlDelay ?? 0)
      let rendered = source.method == "rendered_scrape"
      let page: FetchedPage
      do { page = try await pacedFetch(url, render: rendered, delay: delay, pacer: pacer) }
      catch {
        if index == 0 { throw error }
        complete = false; partialFailure = true
        break
      }
      guard page.statusCode != 403 && page.statusCode != 429 else { throw SourceCheckError.challenge("HTTP \(page.statusCode)") }
      if page.statusCode == 404, index > 0, case .pages = pagination { break }
      guard (200..<300).contains(page.statusCode) else {
        if index == 0 { throw SourceCheckError.fetchFailed("HTTP \(page.statusCode)") }
        complete = false; partialFailure = true; break
      }
      if Self.isChallengePage(page.document) {
        throw SourceCheckError.challenge("bot-challenge page")
      }
      if page.effectiveURL.path.localizedCaseInsensitiveContains("login") {
        throw SourceCheckError.challenge("redirected to a login page")
      }
      pages.append(page)
      if index > 0, case .pages = pagination,
        Self.isEmptyPage(page, source: source, descriptor: descriptor(for: source)) {
        pages.removeLast(); break
      }
      if case .pages = pagination, index == urls.count - 1 { complete = false }
    }
    } catch {
      throw PaginatedFetchError(note: error.localizedDescription, pagesRead: pages.count)
    }
    return PageFetchResult(pages: pages, complete: complete, partialFailure: partialFailure)
  }

  private static func urls(source: Source, pagination: PaginationRule?, now: Date) throws -> [URL] {
    guard let base = URL(string: source.feedURL ?? source.listingURL) else { throw SourceCheckError.fetchFailed("invalid listing URL") }
    var urls = [base]
    switch pagination {
    case let .pages(template, first, max):
      if first <= max {
        urls += (first...max).compactMap { URL(string: template.replacingOccurrences(of: "{n}", with: String($0))) }
      }
    case let .months(template, monthsAhead):
      let calendar = Calendar(identifier: .gregorian)
      let formatter = DateFormatter(); formatter.calendar = calendar
      formatter.timeZone = TimeZone(identifier: "America/New_York")
      formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
      urls += (0...monthsAhead).compactMap { offset in
        calendar.date(byAdding: .month, value: offset, to: now).flatMap {
          URL(string: template.replacingOccurrences(of: "{yyyy-MM}", with: formatter.string(from: $0)))
        }
      }
    case nil: break
    }
    return urls
  }

  private static func isEmptyPage(_ page: FetchedPage, source: Source, descriptor: SourceDescriptor) -> Bool {
    return ExtractionEngine().deterministicListings(
      source.feedURL != nil ? .json(page.document) : .html(page.document), sourceURL: page.effectiveURL, source: descriptor
    ).isEmpty
  }

  static func isChallengePage(_ document: String) -> Bool {
    let lower = document.lowercased()
    guard !lower.contains("cf-chl"), !lower.contains("/cdn-cgi/challenge-platform/h/"),
      !lower.contains("px-captcha") else { return true }
    guard let match = lower.range(of: #"(?is)<title\b[^>]*>(.*?)</title\s*>"#, options: .regularExpression) else { return false }
    let title = lower[match].replacingOccurrences(of: #"(?is)</?title\b[^>]*>"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return ["access denied", "verify you are human", "just a moment...", "just a moment…"].contains(title)
  }

  private func pacedFetch(_ url: URL, render: Bool, delay: TimeInterval, pacer: PassPacer) async throws -> FetchedPage {
    try await pacer.wait(for: delay, using: client.wait)
    do {
      let page = try await client.fetch(url, render)
      await pacer.recordRequestEnd()
      return page
    } catch {
      await pacer.recordRequestEnd()
      throw error
    }
  }

  private func recordUnchanged(_ source: Source, database: any DatabaseWriter, now: Date) async throws {
    try await database.write { db in
      try Source.find(source.id).update {
        $0.lastCheckedAt = #bind(now); $0.lastCheckOutcome = #bind(SourceCheckOutcome.succeeded)
        $0.lastListingCount = #bind(source.lastListingCount); $0.consecutiveFailures = #bind(0)
        $0.lastCheckNote = #bind("unchanged; model not called")
      }.execute(db)
    }
  }

  private func descriptor(for source: Source) -> SourceDescriptor {
    let adapter = source.adapter.flatMap(SourceDescriptor.Adapter.init(rawValue:))
    let hosts = (try? JSONDecoder().decode([String].self, from: Data(source.registeredHosts.utf8))) ?? []
    let excluded = (try? JSONDecoder().decode([String].self, from: Data(source.excludedHosts.utf8))) ?? []
    return SourceDescriptor(id: source.registryID, adapter: adapter, registeredHosts: hosts,
      excludedHosts: excluded, adapterVenue: source.adapterVenue)
  }

  private static func pagination(_ raw: String?) -> PaginationRule? {
    guard let raw, let data = raw.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let kind = value["kind"] as? String, let template = value["template"] as? String else { return nil }
    if kind == "pages", let first = value["first"] as? Int, let max = value["max"] as? Int {
      return .pages(template: template, first: first, max: max)
    }
    if kind == "months", let months = value["months_ahead"] as? Int { return .months(template: template, monthsAhead: months) }
    return nil
  }

  private static func combinedHash(_ hashes: [String]) -> String {
    SHA256.hash(data: Data(hashes.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
