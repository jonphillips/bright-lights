import BrightLightsSchema
import Dependencies
import SQLiteData
import SwiftUI

struct SourcesView: View {
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @State private var showingSettings = false

  var body: some View {
    List {
      let flagged = sources.filter { $0.flaggedAt != nil }
      if !flagged.isEmpty {
        Section("Flagged") {
          ForEach(flagged) { source in
            NavigationLink { SourceDetailView(source: source) } label: {
              VStack(alignment: .leading, spacing: 3) {
                SourceRow(source: source)
                if let note = source.flagNote {
                  Text(note).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      Section("Automated") {
        ForEach(sources.filter { $0.mode == .automated && $0.flaggedAt == nil }) { source in
          NavigationLink { SourceDetailView(source: source) } label: { SourceRow(source: source) }
        }
      }
      Section("Manual") {
        ForEach(sources.filter { $0.mode == .manual && $0.flaggedAt == nil }) { source in
          NavigationLink { SourceDetailView(source: source) } label: { SourceRow(source: source) }
        }
      }
    }
    .navigationTitle("Sources")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
      }
    }
    .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
  }
}

private struct SourceRow: View {
  let source: Source

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(source.name).font(.headline)
      if source.flaggedAt != nil { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange) }
      Text("\(source.area) · \(source.methodLabel)")
        .font(.subheadline).foregroundStyle(.secondary)
      Text("Checks \(source.cadence) · \(source.lastCheckOutcome.rawValue)")
        .font(.caption).foregroundStyle(.secondary)
      if let checked = source.lastCheckedAt {
        Text("Checked \(checked, style: .relative) ago")
          .font(.caption).foregroundStyle(.secondary)
      }
      if source.needsManualLook {
        Label("Needs a manual look", systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct SourceDetailView: View {
  @Environment(AppRouter.self) private var router
  @Environment(SourceFixesModel.self) private var sourceFixes
  let source: Source
  @FetchAll private var currentSources: [Source]
  @FetchAll private var listings: [Listing]
  @FetchAll private var reactions: [Reaction]
  @State private var showingFlagPrompt = false
  @State private var flagNote = ""

  init(source: Source) {
    self.source = source
    self._currentSources = FetchAll(Source.where { $0.id.eq(source.id) })
    self._listings = FetchAll(
      Listing.canonical.where { $0.sourceID.eq(source.id) }.order(by: \.startsAt)
    )
  }

  var body: some View {
    let source = currentSources.first ?? self.source
    Form {
      Section("Source") {
        LabeledContent("ID", value: source.id.uuidString)
        LabeledContent("Household ID", value: source.householdID.uuidString)
        LabeledContent("Name", value: source.name)
        LabeledContent("Type", value: source.type)
        LabeledContent("Priority", value: source.priority)
        LabeledContent("Area", value: source.area)
        LabeledContent("Mode", value: source.mode.rawValue.capitalized)
        LabeledContent("Method", value: source.methodLabel)
        LabeledContent("Cadence", value: source.cadence)
        LabeledContent("Registry ID", value: source.registryID)
        LabeledContent("Added", value: source.createdAt.formatted())
      }
      Section("Checking") {
        LabeledContent("Last check", value: source.lastCheckedAt?.formatted() ?? "never")
        LabeledContent("Outcome", value: source.lastCheckOutcome.rawValue)
        LabeledContent("Listings", value: source.lastListingCount.map(String.init) ?? "—")
        LabeledContent("Consecutive failures", value: String(source.consecutiveFailures))
        if let note = source.lastCheckNote { Text(note).foregroundStyle(.secondary) }
      }
      Section("Current listings") {
        ForEach(listings) { listing in
          VStack(alignment: .leading) {
            Text(listing.title)
            Text("\(listing.startsAt.formatted()) · \(listing.status.rawValue)")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Section {
        NavigationLink {
          ClearedListingsView(source: source)
        } label: {
          LabeledContent("Cleared", value: clearedListings.count.formatted())
        }
      }
      Section("Capture") {
        Button {
          router.capture(source)
        } label: {
          Label("Open in browser", systemImage: "safari")
        }
        LabeledContent("Adapter", value: source.adapter ?? "—")
        LabeledContent("Adapter venue", value: source.adapterVenue ?? "—")
        LabeledContent("Registered hosts", value: source.registeredHosts)
        LabeledContent("Excluded hosts", value: source.excludedHosts)
        if let url = URL(string: source.listingURL) {
          Link(destination: url) { LabeledContent("Registry page", value: source.listingURL) }
        }
      }
      Section("Fixes") {
        if let startPageURL = source.startPageURL {
          LabeledContent("Start page", value: startPageURL)
          Text("Set in the app").font(.caption).foregroundStyle(.secondary)
          Button("Reset", role: .destructive) { sourceFixes.resetStartPage(for: source) }
        }
        if source.flaggedAt != nil {
          Label("Flagged", systemImage: "flag.fill").foregroundStyle(.orange)
          if let note = source.flagNote { Text(note).foregroundStyle(.secondary) }
          Button("Unflag") { sourceFixes.unflag(source) }
        } else {
          Button("Flag…") { flagNote = ""; showingFlagPrompt = true }
        }
      }
    }
    .navigationTitle(source.name)
    .alert("Flag \(source.name)", isPresented: $showingFlagPrompt) {
      TextField("Note (optional)", text: $flagNote)
      Button("Flag") { sourceFixes.flag(source, note: flagNote) }
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

  private var clearedListings: [Listing] {
    ClearedListingRows.make(listings: listings, reactions: reactions, now: .now)
  }
}

private struct ClearedListingsView: View {
  let source: Source
  @FetchAll private var listings: [Listing]
  @FetchAll private var reactions: [Reaction]
  @State private var errorMessage: String?

  init(source: Source) {
    self.source = source
    _listings = FetchAll(Listing.canonical.where { $0.sourceID.eq(source.id) }.order(by: \.startsAt))
  }

  private var clearedListings: [Listing] {
    ClearedListingRows.make(listings: listings, reactions: reactions, now: .now)
  }

  var body: some View {
    Group {
      if clearedListings.isEmpty {
        ContentUnavailableView("No cleared listings", systemImage: "checkmark.circle")
      } else {
        List(clearedListings) { listing in
          VStack(alignment: .leading, spacing: 3) {
            Text(listing.title).font(.headline)
            Text(listing.startsAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption).foregroundStyle(.secondary)
          }
          .swipeActions(edge: .trailing) {
            Button { keep(listing) } label: { Label("Keep", systemImage: "checkmark") }.tint(.green)
          }
        }
      }
    }
    .navigationTitle("Cleared · \(source.name)")
    .alert("Couldn't keep listing", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: { Text(errorMessage ?? "") }
  }

  private func keep(_ listing: Listing) {
    @Dependency(\.defaultDatabase) var database
    let current = ClearedListingRows.latestReaction(for: listing.id, in: reactions)
    let reaction = Reaction(
      id: current?.id ?? UUID(), listingID: listing.id, kind: .kept,
      note: current?.note, authorID: current?.authorID, updatedAt: .now
    )
    Task {
      do { try await database.write { db in try Reaction.upsertForListing(reaction, in: db) } }
      catch { errorMessage = error.localizedDescription }
    }
  }
}

private extension Source {
  var methodLabel: String { adapter.map { "\(method) (\($0))" } ?? method }
}

private enum ClearedListingRows {
  static func make(listings: [Listing], reactions: [Reaction], now: Date) -> [Listing] {
    let latest = Dictionary(grouping: reactions, by: \.listingID)
      .compactMapValues { WhatsOnProjection.latestReaction(in: $0) }
    let clearedIDs = Set(latest.values.filter { $0.kind == .cleared }.map(\.listingID))
    return listings.filter { clearedIDs.contains($0.id) && ($0.closesAt ?? $0.startsAt) >= now }
  }

  static func latestReaction(for listingID: Listing.ID, in reactions: [Reaction]) -> Reaction? {
    WhatsOnProjection.latestReaction(in: reactions.filter { $0.listingID == listingID })
  }
}
