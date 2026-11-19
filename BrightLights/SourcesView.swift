import BrightLightsSchema
import SQLiteData
import SwiftUI

struct SourcesView: View {
  @FetchAll(Source.canonical.order(by: \.name)) private var allSources
  @FetchAll private var allListings: [Listing]
  @State private var selectedSourceID: Source.ID?
  @State private var showingSettings = false

  private var sources: [Source] { allSources.filter { $0.retiredAt == nil } }

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
        SourceDetailView(source: selectedSource, listings: allListings.filter { $0.sourceID == selectedSource.id })
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
  let listings: [Listing]

  private var distinctListings: [Listing] {
    Dictionary(grouping: listings, by: \.stableKey).values.compactMap { rows in
      rows.min { lhs, rhs in
        lhs.firstSeenAt == rhs.firstSeenAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.firstSeenAt < rhs.firstSeenAt
      }
    }
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
        ForEach(distinctListings.sorted { $0.startsAt < $1.startsAt }) { listing in
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
