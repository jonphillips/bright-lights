import BrightLightsChecking
import BrightLightsSchema
import SQLiteData
import SwiftUI

struct RoundsList: View {
  @Environment(BrowserModel.self) private var browser
  @FetchAll(Source.active.order(by: \.name)) private var sources
  @FetchAll(Stay.order(by: \.arrivesOn)) private var stays
  let onSelect: (Source) -> Void

  private var projection: RoundsProjection { RoundsProjection(sources: sources, stays: stays, now: .now) }

  var body: some View {
    List {
      sourceSection("Due", sources: projection.due)
      sourceSection("Not reading automatically", sources: projection.notReadingAutomatically)
      sourceSection("Up to date", sources: projection.upToDate)
    }
  }

  @ViewBuilder private func sourceSection(_ title: String, sources: [Source]) -> some View {
    if !sources.isEmpty {
      Section(title) {
        ForEach(sources) { source in
          Button { onSelect(source) } label: {
            SourceRoundRow(source: source, isCurrent: browser.currentRoundsSource?.id == source.id)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
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
  let isCurrent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(source.name).font(.headline)
        Spacer()
        if isCurrent {
          Label("Current", systemImage: "arrow.forward.circle.fill")
            .font(.caption)
            .foregroundStyle(.tint)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Current source")
        }
      }
      Text("\(source.lastCheckedAt.map { $0.formatted(.relative(presentation: .named)) + " ago" } ?? "never") · \(source.lastListingCount.map(String.init) ?? "—") listings")
        .font(.caption).foregroundStyle(.secondary)
      if source.needsManualLook, let note = source.lastCheckNote {
        Text(note).font(.caption).foregroundStyle(.orange)
      }
    }.padding(.vertical, 3)
  }
}
