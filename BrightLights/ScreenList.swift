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
  let unscreenedListingIDs: Set<Listing.ID>?
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
  private var suggestionCache: [String: TastePrompt.CachedSuggestion] = [:]
  @Shared(.currentPersonID) private var currentPersonIDString
  @Shared(.appStorage("brightLightsScreenSort")) private var sortModeRaw = ScreenSortMode.likelyFirst.rawValue

  init(
    source: Source, listings: [Listing], tasteRecords: [TasteRecord], tasteNotes: [TasteNote],
    people: [Person], unscreenedListingIDs: Set<Listing.ID>?,
    onDone: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.source = source
    self.listings = listings
    self.tasteRecords = tasteRecords
    self.tasteNotes = tasteNotes
    self.people = people
    self.unscreenedListingIDs = unscreenedListingIDs
    self.onDone = onDone
    self.onCancel = onCancel
    _tasteCounts = State(initialValue: TasteCounts(records: tasteRecords.filter { $0.householdID == source.householdID }))
  }

  private var visibleIDs: Set<Listing.ID> { Set(listings.map(\.id)) }
  private var selectedIDs: Set<Listing.ID> { kept.intersection(visibleIDs) }
  private var selectedCount: Int { selectedIDs.count }
  private var visibleClearedCount: Int { visibleIDs.count - selectedCount }
  private var sortedListings: [Listing] {
    let verdicts = Dictionary(uniqueKeysWithValues: suggestionCache.compactMap { key, cached in
      UUID(uuidString: key).map { ($0, cached.verdict) }
    })
    return tasteCounts.sorted(
      listings, sourceRegistryID: source.registryID, likelyFirst: sortMode == .likelyFirst,
      verdicts: verdicts
    )
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
    let suggestions = visibleIDs.reduce(into: [Listing.ID: TasteSuggestion]()) { result, id in
      guard !isSuggesting.contains(id), let cached = suggestionCache[id.uuidString] else { return }
      result[id] = cached.verdict
    }
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
    let staleIDs = Set(staleRows.map(\.id))
    isSuggesting.formUnion(staleIDs)
    defer { isSuggesting.subtract(staleIDs) }
    for batch in TastePrompt.batches(
      listings: staleRows, source: source,
      records: tasteRecords.filter { $0.householdID == source.householdID },
      notes: tasteNotes.filter { $0.householdID == source.householdID },
      people: people.filter { $0.householdID == source.householdID }, counts: tasteCounts
    ) {
      guard !Task.isCancelled else { return }
      do {
        let response = try await modelClient.complete(batch.request)
        guard !Task.isCancelled else { return }
        let parsed = TastePrompt.parse(response.text, rowIDs: batch.rowIDs)
        $suggestionCache.withLock { cache in
          cache = TastePrompt.prunedCache(cache, keeping: unscreenedListingIDs)
          for id in batch.rowIDs {
            guard let suggestion = parsed[id] else { continue }
            cache[id.uuidString] = TastePrompt.CachedSuggestion(
              verdict: suggestion.verdict, reason: suggestion.reason, provider: provider,
              suggestedAt: now
            )
          }
        }
        isSuggesting.subtract(Set(batch.rowIDs))
      } catch {
        if !Task.isCancelled { suggestionError = "Suggestions failed: \(error.localizedDescription)" }
        return
      }
    }
  }
}

private enum ScreenSortMode: String, Hashable {
  case likelyFirst
  case byDate
}
