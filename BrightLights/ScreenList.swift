import BrightLightsSchema
import BrightLightsTaste
import Dependencies
import LLMClientKit
import SQLiteData
import SwiftUI
import Sharing

struct ScreenList: View {
  let source: Source
  let listings: [Listing]
  let tasteRecords: [TasteRecord]
  let tasteNotes: [TasteNote]
  let people: [Person]
  let unscreenedListingIDs: Set<Listing.ID>
  let onDone: () -> Void
  var onCancel: (() -> Void)? = nil

  @State private var kept = Set<Listing.ID>()
  @State private var tasteCounts: TasteCounts
  @State private var isSuggesting = Set<Listing.ID>()
  @State private var suggestionError: String?
  @State private var showingError = false
  @State private var errorMessage = ""
  @Dependency(\.apiKeyStore) private var apiKeyStore
  @Dependency(\.modelClient) private var modelClient
  @Shared(.fileStorage(.documentsDirectory.appending(path: "BrightLightsTasteSuggestions.json")))
  private var suggestionCache: [String: CachedTasteSuggestion] = [:]
  @Shared(.currentPersonID) private var currentPersonIDString
  @Shared(.appStorage("brightLightsScreenSort")) private var sortModeRaw = ScreenSortMode.likelyFirst.rawValue

  init(
    source: Source, listings: [Listing], tasteRecords: [TasteRecord], tasteNotes: [TasteNote] = [],
    people: [Person] = [], unscreenedListingIDs: Set<Listing.ID>? = nil,
    onDone: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.source = source
    self.listings = listings
    self.tasteRecords = tasteRecords
    self.tasteNotes = tasteNotes
    self.people = people
    self.unscreenedListingIDs = unscreenedListingIDs ?? Set(listings.map(\.id))
    self.onDone = onDone
    self.onCancel = onCancel
    _tasteCounts = State(initialValue: TasteCounts(records: tasteRecords.filter { $0.householdID == source.householdID }))
  }

  private var visibleIDs: Set<Listing.ID> { Set(listings.map(\.id)) }
  private var selectedIDs: Set<Listing.ID> { kept.intersection(visibleIDs) }
  private var selectedCount: Int { selectedIDs.count }
  private var visibleClearedCount: Int { visibleIDs.count - selectedCount }
  private var sortedListings: [Listing] {
    return listings.sorted { lhs, rhs in
      let left = suggestionCache[lhs.id.uuidString]?.verdict
      let right = suggestionCache[rhs.id.uuidString]?.verdict
      let rank: (TasteSuggestion?) -> Int = { suggestion in
        switch suggestion { case .keep: 0; case .clear: 2; case .unsure, nil: 1 }
      }
      if rank(left) != rank(right) { return rank(left) < rank(right) }
      if sortMode == .likelyFirst {
        let leftScore = tasteCounts.result(for: lhs, sourceRegistryID: source.registryID).score
        let rightScore = tasteCounts.result(for: rhs, sourceRegistryID: source.registryID).score
        if leftScore != rightScore { return leftScore > rightScore }
      }
      if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
  private var sortMode: ScreenSortMode {
    get { ScreenSortMode(rawValue: sortModeRaw) ?? .likelyFirst }
    nonmutating set { $sortModeRaw.withLock { $0 = newValue.rawValue } }
  }
  private var doneTitle: String {
    selectedCount == 0 ? "Clear all \(visibleIDs.count)" : "Keep \(selectedCount) · Clear \(visibleClearedCount)"
  }

  var body: some View {
    List {
      if let suggestionError {
        Text(suggestionError).font(.caption).foregroundStyle(.secondary)
      }
      ForEach(sortedListings) { listing in
        Button { toggle(listing.id) } label: {
          HStack(spacing: 12) {
            Image(systemName: kept.contains(listing.id) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(kept.contains(listing.id) ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
              Text(listing.title).font(.headline)
              Text(metadata(for: listing)).font(.subheadline).foregroundStyle(.secondary)
              let performers = ListingDisplay.performerNames(listing.performers)
              if !performers.isEmpty { Text(performers).font(.subheadline).foregroundStyle(.secondary) }
              if let evidence = tasteCounts.result(for: listing, sourceRegistryID: source.registryID).evidence {
                Text(evidence.line).font(.caption).foregroundStyle(.secondary)
              }
              if isSuggesting.contains(listing.id) {
                Text("Suggesting…").font(.caption).foregroundStyle(.secondary)
              } else if let suggestion = suggestionCache[listing.id.uuidString] {
                if suggestion.verdict != .unsure {
                  Text(suggestion.verdict == .keep ? "Likely keep" : "Likely clear")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let reason = suggestion.reason, !reason.isEmpty {
                  Text(reason).font(.caption).foregroundStyle(.secondary)
                }
              }
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
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Sort", selection: Binding(
            get: { sortMode }, set: { sortMode = $0 }
          )) {
            Text("Likely first").tag(ScreenSortMode.likelyFirst)
            Text("By date").tag(ScreenSortMode.byDate)
          }
        } label: {
          Label {
            HStack { Text("Sort"); Image(systemName: "chevron.down") }
          } icon: {
            Image(systemName: "arrow.up.arrow.down")
          }
        }
      }
    }
    .onChange(of: tasteRecords) { _, records in
      tasteCounts = TasteCounts(records: records.filter { $0.householdID == source.householdID })
    }
    .task { await requestSuggestionsIfNeeded() }
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
    let suggestions = Dictionary(uniqueKeysWithValues: visibleIDs.compactMap { id in
      suggestionCache[id.uuidString].map { (id, $0.verdict) }
    })
    let authorID = UUID(uuidString: currentPersonIDString)
    Task {
      do {
        try await database.write { db in
          _ = try Reaction.screen(
            kept: selectedIDs, cleared: clearedIDs,
            suggestions: suggestions,
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

  @MainActor
  private func requestSuggestionsIfNeeded() async {
    let now = Date.now
    let unscreened = Set(unscreenedListingIDs.map(\.uuidString))
    $suggestionCache.withLock { cache in
      cache = cache.filter { unscreened.contains($0.key) }
    }
    guard let provider = FrontierResolver().resolve(isConfigured: { apiKeyStore.key($0) != nil }) else {
      suggestionError = "Add a model key in Settings for suggestions"
      return
    }
    suggestionError = nil
    let fresh = Set(suggestionCache.compactMap { key, value in
      now.timeIntervalSince(value.suggestedAt) < 14 * 24 * 60 * 60 ? key : nil
    })
    let staleRows = listings.filter { !fresh.contains($0.id.uuidString) }
    guard !staleRows.isEmpty else { return }
    for batch in TastePrompt.batches(
      listings: staleRows, source: source,
      records: tasteRecords.filter { $0.householdID == source.householdID },
      notes: tasteNotes.filter { $0.householdID == source.householdID },
      people: people, counts: tasteCounts
    ) {
      isSuggesting.formUnion(batch.rowIDs)
      defer { isSuggesting.subtract(batch.rowIDs) }
      do {
        let response = try await modelClient.complete(batch.request)
        let parsed = TastePrompt.parse(response.text, rowIDs: batch.rowIDs)
        $suggestionCache.withLock { cache in
          for id in batch.rowIDs {
            guard let suggestion = parsed[id] else { continue }
            cache[id.uuidString] = CachedTasteSuggestion(
              verdict: suggestion.verdict, reason: suggestion.reason, provider: provider,
              suggestedAt: now
            )
          }
        }
      } catch {
        suggestionError = "Suggestions failed: \(error.localizedDescription)"
        return
      }
    }
  }

  private struct CachedTasteSuggestion: Codable, Sendable, Equatable {
    let verdict: TasteSuggestion
    let reason: String?
    let provider: FrontierProvider
    let suggestedAt: Date
  }

}

private enum ScreenSortMode: String, Hashable {
  case likelyFirst
  case byDate
}
