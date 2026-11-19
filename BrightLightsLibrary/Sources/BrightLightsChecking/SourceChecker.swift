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

public struct SourceCheckReport: Sendable, Equatable {
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
      reports.append(await check(source, in: database, now: now, pacer: pacer))
    }
    try? await database.write { try prune(in: $0, now: now) }
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
      guard !pages.isEmpty else { throw SourceCheckError.noListings() }
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
        previousCount >= Source.manualLookFailureThreshold {
        throw SourceCheckError.noListings(previousCount: previousCount)
      }
      var warnings = batch.warnings
      if !pageResult.complete { warnings.append("partial check; a later page failed") }
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
      let isJSON = page.contentType?.localizedCaseInsensitiveContains("json") == true || source.method == "platform_feed"
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
      let result = try await engine.extract(document, sourceURL: url, source: descriptor)
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

  private func recordSuccess(
    _ listings: [ExtractedListing], source: Source, complete: Bool, database: any DatabaseWriter,
    now: Date, usedModel: Bool, hash: String, note: String?
  ) async throws -> Int {
    try await database.write { db in
      let count = try apply(listings, source: source, complete: complete, db: db, now: now)
      try Source.find(source.id).update {
        $0.lastCheckedAt = #bind(now); $0.lastCheckOutcome = #bind(SourceCheckOutcome.succeeded)
        $0.lastListingCount = #bind(listings.count); $0.consecutiveFailures = #bind(0)
        $0.lastContentHash = #bind(usedModel ? hash : nil as String?); $0.lastCheckNote = #bind(note)
      }.execute(db)
      return count
    }
  }

  private func fetchPages(_ source: Source, now: Date, pacer: PassPacer) async throws -> (pages: [FetchedPage], complete: Bool) {
    let pagination = Self.pagination(source.pagination)
    let urls = try Self.urls(source: source, pagination: pagination, now: now)
    var pages: [FetchedPage] = []
    var complete = true
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
        complete = false
        break
      }
      if page.statusCode == 404 && index > 0, case .pages = pagination { break }
      guard page.statusCode != 403 && page.statusCode != 429 else { throw SourceCheckError.challenge("HTTP \(page.statusCode)") }
      guard (200..<300).contains(page.statusCode) else {
        if index == 0 { throw SourceCheckError.fetchFailed("HTTP \(page.statusCode)") }
        complete = false; break
      }
      let lower = page.document.lowercased()
      if ["captcha", "verify you are human", "bot challenge", "access denied"].contains(where: lower.contains) {
        throw SourceCheckError.challenge("bot-challenge page")
      }
      if page.effectiveURL.path.localizedCaseInsensitiveContains("login") {
        throw SourceCheckError.challenge("redirected to a login page")
      }
      pages.append(page)
      if case .pages = pagination,
        Self.isEmptyPage(page, source: source, descriptor: descriptor(for: source)) {
        pages.removeLast(); break
      }
    }
    } catch {
      throw PaginatedFetchError(note: error.localizedDescription, pagesRead: pages.count)
    }
    return (pages, complete)
  }

  private static func urls(source: Source, pagination: PaginationRule?, now: Date) throws -> [URL] {
    guard let base = URL(string: source.listingURL) else { throw SourceCheckError.fetchFailed("invalid listing URL") }
    var urls = [base]
    switch pagination {
    case let .pages(template, first, max):
      urls += (first..<first + max).compactMap { URL(string: template.replacingOccurrences(of: "{n}", with: String($0))) }
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
    let json = page.contentType?.localizedCaseInsensitiveContains("json") == true
    return ExtractionEngine().deterministicListings(
      json ? .json(page.document) : .html(page.document), sourceURL: page.effectiveURL, source: descriptor
    ).isEmpty
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

  private func apply(_ listings: [ExtractedListing], source: Source, complete: Bool, db: Database, now: Date) throws -> Int {
    let existing = try Listing.where { $0.sourceID.eq(source.id) }.fetchAll(db)
    let grouped = Dictionary(grouping: existing, by: \.stableKey)
    var keep = Set<String>()
    var writes = 0
    for item in listings {
      keep.insert(item.stableKey)
      let duplicates = grouped[item.stableKey, default: []].sorted {
        $0.firstSeenAt == $1.firstSeenAt ? $0.id.uuidString < $1.id.uuidString : $0.firstSeenAt < $1.firstSeenAt
      }
      let current = duplicates.first
      if let current {
        for loser in duplicates.dropFirst() {
          try Reaction.where { $0.listingID.eq(loser.id) }.update { $0.listingID = #bind(current.id) }.execute(db)
          try Listing.find(loser.id).delete().execute(db)
        }
      }
      let performers = String(decoding: try JSONEncoder().encode(item.performers), as: UTF8.self)
      let starts: Date; let closes: Date?
      switch item.time { case let .performance(date): starts = date; closes = nil; case let .run(opens, ends): starts = opens; closes = ends }
      let status = ListingStatus(rawValue: item.status.rawValue) ?? .listed
      let changed = current.map { $0.title != item.title || $0.performers != performers || $0.room != item.room || $0.ticketURL != item.ticketURL?.absoluteString || $0.onSaleAt != item.onSaleDate || $0.startsAt != starts || $0.closesAt != closes || ($0.status != status && $0.status != .missing) || $0.status == .missing } ?? true
      guard changed else { continue }
      let row = Listing(id: current?.id ?? UUID(), sourceID: source.id, stableKey: item.stableKey, title: item.title,
        performers: performers, room: item.room, ticketURL: item.ticketURL?.absoluteString, onSaleAt: item.onSaleDate,
        startsAt: starts, closesAt: closes, status: status, rung: ExtractionRung(rawValue: item.rung.rawValue) ?? .model,
        capturedBy: .mac, firstSeenAt: current?.firstSeenAt ?? now, updatedAt: now)
      if current == nil { try Listing.insert { Listing.Draft(row) }.execute(db) }
      else { try Listing.upsert { Listing.Draft(row) }.execute(db) }
      writes += 1
    }
    if complete {
      for row in existing where !keep.contains(row.stableKey)
        && (row.closesAt ?? row.startsAt) > now && row.status != .missing {
        try Listing.find(row.id).update { $0.status = #bind(ListingStatus.missing); $0.updatedAt = #bind(now) }.execute(db)
        writes += 1
      }
    }
    return writes
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

  private func prune(in db: Database, now: Date) throws {
    for listing in try Listing.fetchAll(db) {
      let end = listing.closesAt ?? listing.startsAt
      guard end < now.addingTimeInterval(-SourceCheckingPolicy.pruningAge),
        try Reaction.where({ $0.listingID.eq(listing.id) }).fetchAll(db).isEmpty else { continue }
      try Listing.find(listing.id).delete().execute(db)
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
