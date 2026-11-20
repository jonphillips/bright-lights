import BrightLightsSchema
import Dependencies
import SQLiteData
import SwiftUI

struct ScreenList: View {
  let source: Source
  let listings: [Listing]
  let onDone: () -> Void
  var onCancel: (() -> Void)? = nil

  @State private var kept = Set<Listing.ID>()
  @State private var showingError = false
  @State private var errorMessage = ""

  private var clearedCount: Int { listings.count - kept.count }
  private var doneTitle: String {
    kept.isEmpty ? "Clear all \(listings.count)" : "Keep \(kept.count) · Clear \(clearedCount)"
  }

  var body: some View {
    List {
      ForEach(listings) { listing in
        Button { toggle(listing.id) } label: {
          HStack(spacing: 12) {
            Image(systemName: kept.contains(listing.id) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(kept.contains(listing.id) ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
              Text(listing.title).font(.headline)
              Text(metadata(for: listing)).font(.subheadline).foregroundStyle(.secondary)
              let performers = performerNames(listing.performers)
              if !performers.isEmpty { Text(performers).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(kept.contains(listing.id) ? "Kept" : "Not kept")
      }
    }
    .navigationTitle(source.name)
    .toolbar {
      if let onCancel {
        ToolbarItem(placement: .cancellationAction) {
          Button("Back", action: onCancel)
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(doneTitle) { saveScreen() }
      }
    }
    .alert("Couldn't save screen", isPresented: $showingError) {
      Button("OK", role: .cancel) {}
    } message: { Text(errorMessage) }
  }

  private func toggle(_ id: Listing.ID) {
    if kept.contains(id) { kept.remove(id) } else { kept.insert(id) }
  }

  private func saveScreen() {
    @Dependency(\.defaultDatabase) var database
    let visibleIDs = Set(listings.map(\.id))
    let selectedIDs = kept.intersection(visibleIDs)
    let clearedIDs = visibleIDs.subtracting(selectedIDs)
    Task {
      do {
        try await database.write { db in
          _ = try Reaction.screen(kept: selectedIDs, cleared: clearedIDs, authorID: nil, now: .now, in: db)
        }
        onDone()
      } catch {
        errorMessage = error.localizedDescription
        showingError = true
      }
    }
  }

  private func metadata(for listing: Listing) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateStyle = .full
    formatter.timeStyle = .short
    var parts = [formatter.string(from: listing.startsAt)]
    if let room = listing.room, !room.isEmpty { parts.append(room) }
    return parts.joined(separator: " · ")
  }

  private func performerNames(_ json: String) -> String {
    guard let data = json.data(using: .utf8),
      let performers = try? JSONDecoder().decode([String].self, from: data) else { return json }
    return performers.joined(separator: ", ")
  }
}
