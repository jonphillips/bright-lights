import BrightLightsChecking
import BrightLightsExtraction
import BrightLightsSchema
import SQLiteData
import SwiftUI
import WebExtractorKit
import WebKit

struct CaptureScreen: View {
  @Environment(BrowserModel.self) private var model
  @Environment(SourceFixesModel.self) private var sourceFixes
  @Environment(AppRouter.self) private var router
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays
  @State private var inspectorPresented = false
  @State private var showingReport = false
  @State private var showingFlagPrompt = false
  @State private var flagNote = ""
  @State private var passiveCaptureTask: Task<Void, Never>?

  private var projection: RoundsProjection { RoundsProjection(sources: sources, stays: stays, now: .now) }

  var body: some View {
    @Bindable var model = model
    WebBrowserView(
      page: model.page,
      accessory: { page in
        HStack(spacing: 12) {
          let fixSource = source(for: page.url)
          let next = projection.next(after: model.currentRoundsSource?.id)
          Button {
            if let next { router.capture(next) }
          } label: {
            Text(next == nil ? "Round done" : "Next")
          }
          .disabled(next == nil)

          Button("Mark as checked") {
            if let current = model.currentRoundsSource { model.markChecked(current) }
          }
          .disabled(model.currentRoundsSource == nil)
          Button { Task { await model.capture(page: page, sources: sources) } } label: {
            Label(model.isReading ? "Reading…" : "Capture", systemImage: "plus.circle.fill")
          }
          .disabled(model.isReading || page.url == nil)
          if let fixSource {
            Menu {
              if let url = startPageURL(page.url, for: fixSource) {
                Button("Use as start page") {
                  sourceFixes.setStartPage(url.absoluteString, for: fixSource)
                }
              }
              if fixSource.flaggedAt == nil {
                Button("Flag…") { flagNote = ""; showingFlagPrompt = true }
              } else {
                Button("Unflag") { sourceFixes.unflag(fixSource) }
              }
            } label: {
              Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Source actions")
            }
          }
          if let message = sourceFixes.confirmationMessage {
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          if let error = model.captureError {
            Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          } else if let report = model.report, report.listings.isEmpty {
            Text("No listings found").font(.caption).foregroundStyle(.secondary)
            Button("Mark as checked") {
              if let current = model.currentRoundsSource { model.markChecked(current) }
            }
            .disabled(model.currentRoundsSource == nil)
          } else if let report = model.report {
            Button { showingReport = true } label: {
              Text("\(report.listings.count) listings from \(report.sourceName) · \(report.newListings) new")
            }
          }
        }
      },
      home: { _ in
        RoundsList(onSelect: selectSource)
      }
    )
    .navigationTitle("Capture")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { inspectorPresented.toggle() } label: {
          Label("Sources due", systemImage: "sidebar.trailing")
        }
        .accessibilityLabel(inspectorPresented ? "Hide sources due" : "Show sources due")
      }
    }
    .inspector(isPresented: $inspectorPresented) {
      RoundsList(onSelect: selectSource)
        .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
    }
    .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
      inspectorPresented = sizeClass != .compact
    }
    .onChange(of: model.page.url) { _, _ in
      model.navigationStarted()
      passiveCaptureTask?.cancel()
    }
    .onChange(of: model.page.isLoading) { wasLoading, isLoading in
      if isLoading { model.navigationStarted(); passiveCaptureTask?.cancel(); return }
      guard wasLoading, let url = model.page.url else { return }
      passiveCaptureTask?.cancel()
      passiveCaptureTask = Task {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, model.page.url == url, !model.page.isLoading,
          let html = await model.page.currentDOM(), !html.isEmpty else { return }
        await model.captureAutomatically(at: url, html: html, sources: sources)
      }
    }
    .confirmationDialog("Choose a source for this page", isPresented: Binding(
      get: { model.pendingPage != nil },
      set: { isPresented in
        if !isPresented {
          model.pendingPage = nil
          model.pendingSources = []
        }
      }
    )) {
      ForEach(model.pendingSources) { candidate in
        Button(candidate.name) { model.choose(candidate) }
      }
    }
    .sheet(isPresented: $showingReport) {
      NavigationStack {
        List(model.report?.listings ?? []) { listing in
          VStack(alignment: .leading) {
            Text(listing.title)
            Text(listingDate(listing)).font(.caption).foregroundStyle(.secondary)
          }
        }
        .navigationTitle("Captured listings")
      }
    }
    .alert("Couldn't mark source as checked", isPresented: Binding(
      get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: { Text(model.errorMessage ?? "") }
    .alert("Flag \(source(for: model.page.url)?.name ?? "source")", isPresented: $showingFlagPrompt) {
      TextField("Note (optional)", text: $flagNote)
      Button("Flag") {
        if let source = source(for: model.page.url) { sourceFixes.flag(source, note: flagNote) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { Text("Add a short note about what isn't working.") }
    .onChange(of: flagNote) { _, value in
      if value.count > 200 { flagNote = String(value.prefix(200)) }
    }
    .alert("Couldn't update source", isPresented: Binding(
      get: { sourceFixes.errorMessage != nil }, set: { if !$0 { sourceFixes.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { sourceFixes.errorMessage = nil }
    } message: { Text(sourceFixes.errorMessage ?? "") }
  }

  private func selectSource(_ source: Source) {
    router.capture(source)
    if horizontalSizeClass == .compact { inspectorPresented = false }
  }

  private func source(for url: URL?) -> Source? {
    guard let url else { return nil }
    if let current = model.currentRoundsSource,
      SourcePageMatcher.canUseAsStartPage(url, for: current) { return current }
    return SourcePageMatcher.source(for: url, among: sources)
  }

  private func startPageURL(_ pageURL: URL?, for source: Source) -> URL? {
    guard let pageURL, SourcePageMatcher.canUseAsStartPage(pageURL, for: source),
      var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
    components.fragment = nil
    guard let cleaned = components.url,
      let existing = URL(string: source.pageURL), existing.absoluteString != cleaned.absoluteString else { return nil }
    return cleaned
  }

  private func listingDate(_ listing: ExtractedListing) -> String {
    switch listing.time {
    case let .performance(date): date.formatted(date: .abbreviated, time: .shortened)
    case let .run(opens, closes): "\(opens.formatted(date: .abbreviated, time: .omitted)) – \(closes.formatted(date: .abbreviated, time: .omitted))"
    }
  }
}
