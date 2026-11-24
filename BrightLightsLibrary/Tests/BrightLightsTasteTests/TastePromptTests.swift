import BrightLightsSchema
import BrightLightsTaste
import Foundation
import Testing

@Suite struct TastePromptTests {
  @Test func renderedPromptIncludesOnlyInventedFixtureDetails() {
    var source = sourceFixture()
    source.name = "The Moon Room"
    let listing = Listing(
      id: UUID(), sourceID: source.id, stableKey: "fixture", title: "Fictional Moonlight Parade",
      performers: "[\"The Harbor Lights\"]", room: "The Moon Room",
      startsAt: Date(timeIntervalSince1970: 1_800_000_000), rung: .model, capturedBy: .mac
    )
    let request = TastePrompt.batches(
      listings: [listing], source: source, records: [], notes: [], people: [], counts: TasteCounts(records: [])
    )[0].request
    #expect(request.system?.contains("Never decide for the people") == true)
    #expect(request.system?.contains("notesOmitted") == false)
    #expect(request.messages[0].text.contains("Fictional Moonlight Parade"))
    #expect(request.messages[0].text.contains("The Harbor Lights"))
    #expect(request.messages[0].text.contains("The Moon Room"))
  }

  @Test func dateUsesNewYorkTimeAndIncludesWeekday() {
    #expect(TastePrompt.formattedDate(Date(timeIntervalSince1970: 1_800_000_000)) == "Fri, Jan 15, 2027 at 3:00 AM")
  }

  @Test func pruningKeepsEverythingWhenUnscreenedIDsAreUnknown() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let cache = [first, second, third].reduce(into: [String: TastePrompt.CachedSuggestion]()) { result, id in
      result[id.uuidString] = TastePrompt.CachedSuggestion(
        verdict: .keep, reason: nil, provider: .anthropic, suggestedAt: Date(timeIntervalSince1970: 1)
      )
    }

    #expect(TastePrompt.prunedCache(cache, keeping: nil).count == 3)
    #expect(Set(TastePrompt.prunedCache(cache, keeping: [first, third]).keys) == [first.uuidString, third.uuidString])
  }

  @Test func batchesFortyRowsAndCapsNotesAndExamples() throws {
    let source = sourceFixture()
    let listings = (0..<95).map { index in listing("row-\(index)", title: "Row \(index)") }
    let notes = (0..<81).map { index in
      TasteNote(id: UUID(), householdID: source.householdID, subject: nil,
        body: "Note \(index)", createdAt: Date(timeIntervalSince1970: Double(index)),
        updatedAt: Date(timeIntervalSince1970: Double(index)))
    }
    let records = (0..<45).map { index in
      record("example-\(index)", title: "Example \(index)", kind: .kept, note: "Why")
    } + [record("clear-only", title: "Clear", kind: .cleared, note: "Do not send")]
    let batches = TastePrompt.batches(
      listings: listings, source: source, records: records, notes: notes,
      people: [], counts: TasteCounts(records: records)
    )

    #expect(batches.map(\.rowIDs.count) == [40, 40, 15])
    #expect(batches[0].request.tier == .frontierPreferred)
    #expect(batches[0].request.responseFormat != .text)
    let firstPrompt = batches[0].request.messages[0].text
    #expect(firstPrompt.contains("\"notesOmitted\":\"1 more not shown\""))
    #expect(firstPrompt.contains("\"examples\":["))
    #expect(!firstPrompt.contains("Do not send"))
    #expect(firstPrompt.contains("Example"))
    #expect(firstPrompt.components(separatedBy: "\"decision\"").count - 1 == 40)
  }

  @Test func missingAndMalformedRowsBecomeUnsureAndReasonsAreTrimmed() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let response = """
    {"suggestions":[
      {"index":1,"verdict":"keep","reason":"  \(String(repeating: "x", count: 130))  "},
      {"index":99,"verdict":"clear","reason":"unknown"},
      {"index":3,"verdict":"made-up","reason":"bad"}
    ]}
    """
    let parsed = TastePrompt.parse(response, rowIDs: [first, second, third])
    #expect(parsed[first]?.verdict == .keep)
    #expect(parsed[first]?.reason?.count == 120)
    #expect(parsed[second] == .init(verdict: .unsure, reason: nil))
    #expect(parsed[third] == .init(verdict: .unsure, reason: nil))
  }

  @Test func agreementCountsOnlyRecentStoredSuggestions() {
    let cutoff = Date(timeIntervalSince1970: 100)
    let recentKeep = record("recent-keep", title: "A", kind: .kept, suggestion: .keep, decided: 101)
    let recentClear = record("recent-clear", title: "B", kind: .pass, suggestion: .clear, decided: 102)
    let recentUnsure = record("recent-unsure", title: "C", kind: .cleared, suggestion: .unsure, decided: 103)
    let oldKeep = record("old-keep", title: "D", kind: .kept, suggestion: .keep, decided: 99)
    let agreement = TastePrompt.agreement(records: [recentKeep, recentClear, recentUnsure, oldKeep], since: cutoff)
    #expect(agreement.suggestedKeep == 1)
    #expect(agreement.kept == 1)
    #expect(agreement.suggestedClear == 1)
    #expect(agreement.clearedOrPassed == 1)
    #expect(agreement.unsure == 1)
  }

  @Test func examplesSharingAKeyComeBeforeMoreRecentUnmatchedExamples() throws {
    let source = sourceFixture()
    let listing = Listing(
      id: UUID(), sourceID: source.id, stableKey: "candidate", title: "New Act",
      performers: "[\"Shared Performer\"]", startsAt: Date(timeIntervalSince1970: 300),
      rung: .model, capturedBy: .mac
    )
    let matched = record(
      "older-match", title: "Old Bill", kind: .kept, performers: "[\"Shared Performer\"]",
      updated: 10
    )
    let recent = record("newer", title: "Unrelated", kind: .kept, updated: 100)
    let prompt = TastePrompt.batches(
      listings: [listing], source: source, records: [recent, matched], notes: [], people: [],
      counts: TasteCounts(records: [recent, matched])
    )[0].request.messages[0].text
    let payload = try #require(try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any])
    let examples = try #require(payload["examples"] as? [[String: Any]])

    #expect(examples.compactMap { $0["title"] as? String } == ["Old Bill", "Unrelated"])
  }

  private func sourceFixture() -> Source {
    Source(id: UUID(), householdID: UUID(), registryID: "venue", name: "Venue", type: "venue",
      priority: "core", area: "Brooklyn", mode: .manual, method: "fixture", listingURL: "https://example.com",
      registeredHosts: "[\"example.com\"]", cadence: "weekly")
  }

  private func listing(_ key: String, title: String, performers: String = "[]", room: String? = nil) -> Listing {
    Listing(id: UUID(), sourceID: UUID(), stableKey: key, title: title,
      performers: performers, room: room, startsAt: Date(timeIntervalSince1970: 200), rung: .model, capturedBy: .mac)
  }

  private func record(
    _ key: String, title: String, kind: ReactionKind, suggestion: TasteSuggestion? = nil,
    performers: String = "[]", note: String? = nil, decided: TimeInterval = 20, updated: TimeInterval = 20
  ) -> TasteRecord {
    TasteRecord(id: UUID(), householdID: UUID(), sourceRegistryID: "venue", sourceName: "Venue",
      stableKey: key, title: title, performers: performers, startsAt: Date(timeIntervalSince1970: 10),
      kind: kind, suggestion: suggestion, note: note,
      firstDecidedAt: Date(timeIntervalSince1970: decided), updatedAt: Date(timeIntervalSince1970: updated))
  }
}
