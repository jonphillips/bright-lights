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
  @FetchAll(Listing.canonical.order(by: \.startsAt)) private var listings
  @FetchAll private var reactions: [Reaction]
  @FetchAll private var tasteRecords: [TasteRecord]
  @State private var inspectorPresented = false
  @State private var showingReport = false
  @State private var showingFlagPrompt = false
  @State private var flagNote = ""
  @State private var flaggingSource: Source?
  @State private var passiveCaptureTask: Task<Void, Never>?
  @State private var screenRoute: CaptureScreenRoute?

  private var projection: RoundsProjection { RoundsProjection(sources: sources, stays: stays, now: .now) }
  private var screenSheet: Binding<CaptureScreenRoute?> {
    Binding(
      get: { horizontalSizeClass == .compact ? screenRoute : nil },
      set: { if horizontalSizeClass == .compact { screenRoute = $0 } }
    )
  }

  var body: some View {
    @Bindable var model = model
    let newProjection = NewProjection(
      listings: listings, sources: sources, reactions: reactions,
      tasteRecordIDs: Set(tasteRecords.map(\.id)), now: .now
    )
    let currentNewCount = model.currentRoundsSource.map { newProjection.count(for: $0.id) } ?? 0
    WebBrowserView(
      page: model.page,
      accessory: { page in
        HStack(spacing: 12) {
          let fixSources = sourcesForActions(page.url)
          let next = projection.next(after: model.currentRoundsSource?.id)
          Button {
            if currentNewCount > 0, let current = model.currentRoundsSource {
              openScreen(current, then: next, from: newProjection)
            } else if let next {
              router.capture(next)
            }
          } label: {
            Text(currentNewCount > 0 ? "Review \(currentNewCount)" : next == nil ? "Round done" : "Next")
          }
          .disabled(next == nil && currentNewCount == 0)

          Button("Mark as checked") {
            if let current = model.currentRoundsSource { model.markChecked(current) }
          }
          .disabled(model.currentRoundsSource == nil)
          Button { Task { await model.capture(page: page, sources: sources) } } label: {
            Label(model.isReading ? "Reading…" : "Capture", systemImage: "plus.circle.fill")
          }
          .disabled(model.isReading || page.url == nil)
          if !fixSources.isEmpty {
            Menu {
              ForEach(fixSources) { source in
                if let url = startPageURL(page.url, for: source) {
                  Button("Use as start page for \(source.name)") {
                    sourceFixes.setStartPage(url.absoluteString, for: source)
                  }
                }
                if source.flaggedAt == nil {
                  Button("Flag \(source.name)…") {
                    flaggingSource = source
                    flagNote = ""
                    showingFlagPrompt = true
                  }
                } else {
                  Button("Unflag \(source.name)") { sourceFixes.unflag(source) }
                }
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
          } else if let source = model.currentRoundsSource, currentNewCount > 0 {
            Button { openScreen(source, then: nil, from: newProjection) } label: {
              Text("\(currentNewCount) new · Review")
            }
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
      NavigationStack {
        if let route = screenRoute {
          ScreenList(source: route.source, listings: route.listings, tasteRecords: tasteRecords, onDone: { finishScreen(route) }, onCancel: { screenRoute = nil })
            .id(route.id)
        } else {
          RoundsList(onSelect: selectSource)
        }
      }
        .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
    }
    .onChange(of: inspectorPresented) { _, isPresented in
      if !isPresented { screenRoute = nil }
    }
    .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
      screenRoute = nil
      inspectorPresented = sizeClass != .compact
    }
    .onChange(of: model.page.url) { _, _ in
      model.navigationStarted()
      sourceFixes.clearConfirmation()
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
    .sheet(item: screenSheet) { route in
      NavigationStack {
        ScreenList(source: route.source, listings: route.listings, tasteRecords: tasteRecords, onDone: { finishScreen(route) }, onCancel: { screenRoute = nil })
          .id(route.id)
      }
    }
    .alert("Couldn't mark source as checked", isPresented: Binding(
      get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: { Text(model.errorMessage ?? "") }
    .alert("Flag \(flaggingSource?.name ?? "source")", isPresented: $showingFlagPrompt) {
      TextField("Note (optional)", text: $flagNote)
      Button("Flag") {
        if let flaggingSource { sourceFixes.flag(flaggingSource, note: flagNote) }
        flaggingSource = nil
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

  private func openScreen(_ source: Source, then next: Source?, from projection: NewProjection) {
    let rows = projection.groups.first { $0.source.id == source.id }?.listings ?? []
    screenRoute = CaptureScreenRoute(source: source, listings: rows, nextSource: next)
    if horizontalSizeClass != .compact { inspectorPresented = true }
  }

  private func finishScreen(_ route: CaptureScreenRoute) {
    screenRoute = nil
    if let next = route.nextSource { router.capture(next) }
  }

  private func sourcesForActions(_ url: URL?) -> [Source] {
    guard let url else { return [] }
    if let current = model.currentRoundsSource,
      SourcePageMatcher.canUseAsStartPage(url, for: current) { return [current] }
    return SourcePageMatcher.candidates(for: url, among: sources)
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

private struct CaptureScreenRoute: Identifiable {
  let source: Source
  let listings: [Listing]
  let nextSource: Source?
  var id: Source.ID { source.id }
}
