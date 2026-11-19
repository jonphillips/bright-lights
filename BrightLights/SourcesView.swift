import BrightLightsSchema
import SQLiteData
import SwiftUI

struct SourcesView: View {
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @State private var selectedSourceID: Source.ID?
  @State private var showingSettings = false

  private var selectedSource: Source? { sources.first { $0.id == selectedSourceID } }

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedSourceID) {
        Section("Automated") {
          ForEach(sources.filter { $0.mode == .automated }) { source in
            NavigationLink(value: source.id) { SourceRow(source: source) }
          }
        }
        Section("Manual") {
          ForEach(sources.filter { $0.mode == .manual }) { source in
            NavigationLink(value: source.id) { SourceRow(source: source) }
          }
        }
      }
      .navigationTitle("Sources")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
        }
      }
    } detail: {
      if let selectedSource {
        SourceDetailView(source: selectedSource)
      } else {
        ContentUnavailableView("Choose a source", systemImage: "calendar.badge.clock")
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
  let source: Source
  @FetchAll private var listings: [Listing]

  init(source: Source) {
    self.source = source
    self._listings = FetchAll(
      Listing.canonical.where { $0.sourceID.eq(source.id) }.order(by: \.startsAt)
    )
  }

  var body: some View {
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
      Section("Capture") {
        LabeledContent("Adapter", value: source.adapter ?? "—")
        LabeledContent("Adapter venue", value: source.adapterVenue ?? "—")
        LabeledContent("Registered hosts", value: source.registeredHosts)
        LabeledContent("Excluded hosts", value: source.excludedHosts)
        if let url = URL(string: source.listingURL) {
          Link(source.listingURL, destination: url)
        }
      }
    }
    .navigationTitle(source.name)
  }
}

private extension Source {
  var methodLabel: String { adapter.map { "\(method) (\($0))" } ?? method }
}
