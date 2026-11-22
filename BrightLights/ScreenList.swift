import BrightLightsSchema
import Dependencies
import SQLiteData
import SwiftUI
import Sharing

struct ScreenList: View {
  let source: Source
  let listings: [Listing]
  let onDone: () -> Void
  var onCancel: (() -> Void)? = nil

  @State private var kept = Set<Listing.ID>()
  @State private var showingError = false
  @State private var errorMessage = ""
  @Shared(.currentPersonID) private var currentPersonIDString

  private var visibleIDs: Set<Listing.ID> { Set(listings.map(\.id)) }
  private var selectedIDs: Set<Listing.ID> { kept.intersection(visibleIDs) }
  private var selectedCount: Int { selectedIDs.count }
  private var visibleClearedCount: Int { visibleIDs.count - selectedCount }
  private var doneTitle: String {
    selectedCount == 0 ? "Clear all \(visibleIDs.count)" : "Keep \(selectedCount) · Clear \(visibleClearedCount)"
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
              let performers = ListingDisplay.performerNames(listing.performers)
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
    let visibleIDs = self.visibleIDs
    let selectedIDs = self.selectedIDs
    let clearedIDs = visibleIDs.subtracting(selectedIDs)
    let authorID = UUID(uuidString: currentPersonIDString)
    Task {
      do {
        try await database.write { db in
          _ = try Reaction.screen(
            kept: selectedIDs, cleared: clearedIDs,
            authorID: authorID, now: .now, in: db
          )
        }
        onDone()
      } catch {
        errorMessage = error.localizedDescription
        showingError = true
      }
    }
  }

  private func metadata(for listing: Listing) -> String {
    var parts = [ListingDisplay.newYorkDateTime(listing.startsAt)]
    if let room = listing.room, !room.isEmpty { parts.append(room) }
    return parts.joined(separator: " · ")
  }

}
