import BrightLightsExtraction
import BrightLightsSchema
import CryptoKit
import Dependencies
import Foundation
import LLMClientKit
import OSLog
import SQLiteData

public struct BrowserCaptureReport: Sendable, Equatable {
  public var sourceID: UUID
  public var listings: [ExtractedListing]
  public var rowsWritten: Int
  public var newListings: Int
  public var warnings: [String]
  public var rung: ExtractionRung?
  public var modelCalls: Int

  public init(sourceID: UUID, listings: [ExtractedListing], rowsWritten: Int, newListings: Int,
    warnings: [String], rung: ExtractionRung?, modelCalls: Int) {
    self.sourceID = sourceID; self.listings = listings; self.rowsWritten = rowsWritten
    self.newListings = newListings; self.warnings = warnings; self.rung = rung; self.modelCalls = modelCalls
  }
}

public enum BrowserCaptureError: Error, LocalizedError, Sendable {
  case noModelKey

  public var errorDescription: String? {
    switch self {
    case .noModelKey: "No model key — add one in Settings"
    }
  }
}

/// Session-scoped capture pipeline shared by passive and explicit browser captures.
public actor BrowserCapture {
  @Dependency(\.apiKeyStore) private var apiKeyStore
  private var cache: [String: BrowserCaptureReport] = [:]

  public init() {}

  public func capture(
    source: Source, pageURL: URL, html: String, in database: any DatabaseWriter, now: Date = .now
  ) async throws -> BrowserCaptureReport {
    let document: PageDocument = source.feedURL == nil ? .html(html) : .json(html)
    let hash = ExtractionEngine.pageHash(for: document)
    let cacheKey = "\(source.id.uuidString)|\(pageURL.absoluteString)|\(hash)"
    if var cached = cache[cacheKey] {
      cached.rowsWritten = 0
      cached.newListings = 0
      return cached
    }
    let engine = ExtractionEngine()
    let descriptor = source.extractionDescriptor
    let needsModel = !engine.hasDeterministicRung(document, sourceURL: pageURL, source: descriptor)
    guard !needsModel || apiKeyStore.key(.anthropic) != nil || apiKeyStore.key(.openai) != nil else {
      throw BrowserCaptureError.noModelKey
    }
    let result = try await engine.extract(document, sourceURL: pageURL, source: descriptor)
    try Task.checkCancellation()
    let unique = Dictionary(result.listings.map { ($0.stableKey, $0) }, uniquingKeysWith: { first, _ in first })
      .values.sorted { $0.stableKey < $1.stableKey }
    let wasKnown = try await database.read { db in
      Set(try Listing.where { $0.sourceID.eq(source.id) }.fetchAll(db).map(\.stableKey))
    }
    let newCount = unique.filter { !wasKnown.contains($0.stableKey) }.count
    try Task.checkCancellation()
    let listingPage = SourcePageMatcher.isListingPage(pageURL, for: source)
    let writes = try await database.write { db in
      let count = try Listing.reconcile(unique, sourceID: source.id, capturedBy: .browser,
        complete: false, now: now, makeID: UUID.init, in: db)
      if listingPage && !unique.isEmpty {
        let note = (["Captured in the browser"] + result.warnings).joined(separator: "; ")
        try Source.find(source.id).update {
          $0.lastCheckedAt = #bind(now)
          $0.lastCheckOutcome = #bind(SourceCheckOutcome.succeeded)
          $0.lastListingCount = #bind(unique.count)
          $0.consecutiveFailures = #bind(0)
          $0.lastCheckNote = #bind(String(note.prefix(Source.checkNoteCharacterLimit)))
        }.execute(db)
      } else if source.needsManualLook && !unique.isEmpty {
        // A browser capture on a subpage covers the immediate failure without pretending
        // that Jon checked the source's whole listing page.
        try Source.find(source.id).update {
          $0.consecutiveFailures = #bind(0)
          $0.lastCheckNote = #bind("Covered by a browser capture")
        }.execute(db)
      }
      return count
    }
    let usedModel = needsModel
    let rung = unique.compactMap { ExtractionRung(rawValue: $0.rung.rawValue) }
      .max { $0.rawValue < $1.rawValue }
    let report = BrowserCaptureReport(sourceID: source.id, listings: unique,
      rowsWritten: writes, newListings: newCount, warnings: result.warnings,
      rung: rung, modelCalls: usedModel ? 1 : 0)
    cache[cacheKey] = report
    Logger(subsystem: "com.jonphillips.BrightLights", category: "BrowserCapture")
      .info("source=\(source.id.uuidString, privacy: .public) page=\(pageURL.absoluteString, privacy: .private) listings=\(unique.count, privacy: .public) new=\(newCount, privacy: .public) rung=\(rung?.rawValue ?? "none", privacy: .public) modelCalls=\(report.modelCalls, privacy: .public)")
    return report
  }
}
