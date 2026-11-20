import BrightLightsChecking
import BrightLightsExtraction
import BrightLightsSchema
import SQLiteData
import SwiftUI
import WebExtractorKit
import WebKit

struct BrowserScreen: View {
  @Environment(BrowserModel.self) private var model
  @FetchAll(Source.active.order(by: \.name)) private var sources
  let source: Source?
  let startingURL: URL?
  @State private var showingReport = false
  @State private var passiveCaptureTask: Task<Void, Never>?

  init(source: Source? = nil, url: URL? = nil) { self.source = source; self.startingURL = url }

  var body: some View {
    @Bindable var model = model
    WebBrowserView(
      page: model.page,
      initialURL: model.initialURL ?? source.flatMap { URL(string: $0.listingURL) } ?? startingURL,
      accessory: { page in
        HStack(spacing: 12) {
          Button("Mark as checked") {
            if let current = model.currentRoundsSource ?? source { model.markChecked(current) }
          }
          .disabled(model.currentRoundsSource == nil && source == nil)
          Button { Task { await model.capture(page: page, sources: sources) } } label: {
            Label(model.isReading ? "Reading…" : "Capture", systemImage: "plus.circle.fill")
          }
          .disabled(model.isReading || page.url == nil)
          if let error = model.captureError {
            Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          } else if let report = model.report, report.listings.isEmpty {
            Text("No listings found").font(.caption).foregroundStyle(.secondary)
            Button("Mark as checked") {
              if let current = model.currentRoundsSource ?? source { model.markChecked(current) }
            }
            .disabled(model.currentRoundsSource == nil && source == nil)
          } else if let report = model.report {
            Button { showingReport = true } label: {
              Text("\(report.listings.count) listings from \(report.sourceName) · \(report.newListings) new")
            }
          }
        }
      },
      home: { _ in ContentUnavailableView("Open a source", systemImage: "safari") }
    )
    .navigationTitle(source?.name ?? "Browser")
    .onAppear {
      if let source { model.open(source) }
      else if let startingURL, model.page.url != startingURL { model.open(startingURL) }
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
  }

  private func listingDate(_ listing: ExtractedListing) -> String {
    switch listing.time {
    case let .performance(date): date.formatted(date: .abbreviated, time: .shortened)
    case let .run(opens, closes): "\(opens.formatted(date: .abbreviated, time: .omitted)) – \(closes.formatted(date: .abbreviated, time: .omitted))"
    }
  }
}
