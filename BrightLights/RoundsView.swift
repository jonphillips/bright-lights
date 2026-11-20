import BrightLightsChecking
import BrightLightsSchema
import SQLiteData
import SwiftUI

struct RoundsView: View {
  @Environment(BrowserModel.self) private var browser
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays

  private var projection: RoundsProjection { RoundsProjection(sources: sources, stays: stays, now: .now) }

  var body: some View {
    List {
      sourceSection("Due", sources: projection.due)
      sourceSection("Not reading automatically", sources: projection.notReadingAutomatically)
      sourceSection("Up to date", sources: projection.upToDate)
    }
    .navigationTitle("Rounds")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Text("\(projection.badgeCount) due").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private func sourceSection(_ title: String, sources: [Source]) -> some View {
    if !sources.isEmpty {
      Section(title) {
        ForEach(sources) { source in
          NavigationLink {
            BrowserScreen(source: source)
          } label: {
            SourceRoundRow(source: source)
          }
          .swipeActions(edge: .trailing) {
            Button { browser.markChecked(source) } label: {
              Label("Mark as checked", systemImage: "checkmark")
            }.tint(.blue)
          }
        }
      }
    }
  }
}

private struct SourceRoundRow: View {
  let source: Source

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(source.name).font(.headline)
      Text("\(source.lastCheckedAt.map { $0.formatted(.relative(presentation: .named)) + " ago" } ?? "never") · \(source.lastListingCount.map(String.init) ?? "—") listings")
        .font(.caption).foregroundStyle(.secondary)
      if source.needsManualLook, let note = source.lastCheckNote {
        Text(note).font(.caption).foregroundStyle(.orange)
      }
    }.padding(.vertical, 3)
  }
}
