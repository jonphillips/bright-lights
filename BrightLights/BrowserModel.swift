import BrightLightsChecking
import BrightLightsSchema
import Dependencies
import Foundation
import Observation
import SQLiteData
import WebExtractorKit
import WebKit

@MainActor
@Observable
final class BrowserModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  let page = WebPage.browser(contentMode: .desktop)
  private let captureEngine = BrowserCapture()
  var currentRoundsSource: Source?
  var pendingPage: (URL, String)?
  var pendingSources: [Source] = []
  var report: BrowserCaptureReport?
  var captureError: String?
  var errorMessage: String?
  var isReading = false

  func open(_ source: Source) {
    currentRoundsSource = source
    navigationStarted()
    guard let url = URL(string: source.listingURL) else { return }
    page.load(URLRequest(url: url))
  }

  func open(_ url: URL) {
    currentRoundsSource = nil
    navigationStarted()
    page.load(URLRequest(url: url))
  }

  func capture(page webPage: WebPage, sources: [Source], assignedSource: Source? = nil) async {
    guard let url = webPage.url, let html = await webPage.currentDOM(), !html.isEmpty else { return }
    let source = assignedSource ?? SourcePageMatcher.source(
      for: url, among: sources, currentSource: currentRoundsSource
    )
    guard let source else {
      pendingPage = (url, html)
      pendingSources = sources.filter { $0.retiredAt == nil }.sorted {
        if $0.id == currentRoundsSource?.id { return true }
        if $1.id == currentRoundsSource?.id { return false }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      return
    }
    await runCapture(source: source, url: url, html: html)
  }

  func captureAutomatically(at url: URL, html: String, sources: [Source]) async {
    guard let source = SourcePageMatcher.source(for: url, among: sources, currentSource: currentRoundsSource),
      SourcePageMatcher.allowsPassiveCapture(source) else { return }
    await runCapture(source: source, url: url, html: html)
  }

  func markChecked(_ source: Source) {
    Task {
      do {
        try await database.write { db in
          try Source.find(source.id).update {
            $0.lastCheckedAt = #bind(Date.now)
            $0.lastCheckOutcome = #bind(SourceCheckOutcome.succeeded)
            $0.consecutiveFailures = #bind(0)
            $0.lastCheckNote = #bind("Marked checked")
          }.execute(db)
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }

  func choose(_ source: Source) {
    guard let (url, html) = pendingPage else { return }
    pendingPage = nil
    Task { await runCapture(source: source, url: url, html: html) }
  }

  func navigationStarted() {
    report = nil
    captureError = nil
  }

  private func runCapture(source: Source, url: URL, html: String) async {
    isReading = true
    defer { isReading = false }
    do {
      let nextReport = try await captureEngine.capture(source: source, pageURL: url, html: html, in: database)
      guard page.url == url else { return }
      report = nextReport
      captureError = nil
    } catch {
      guard page.url == url else { return }
      captureError = error.localizedDescription
    }
  }
}
