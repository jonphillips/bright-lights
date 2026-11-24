import BrightLightsSchema
import BrightLightsTaste
import Foundation
import Testing

@Suite
struct TasteCountsTests {
  @Test func normalizationFoldsCaseDiacriticsAndPunctuationRuns() {
    #expect(TasteCounts.normalized("  CAFÉ—After  Party!! ") == "cafe after party")
    #expect(TasteCounts.normalized("Beyoncé & The   Roots") == "beyonce the roots")
  }

  @Test func usesTheSmoothedGlobalSourceAndShowRates() {
    let records = [
      record("A", source: "alpha", title: "The Show", kind: .kept),
      record("B", source: "alpha", title: "The Show", kind: .kept),
      record("C", source: "alpha", title: "The Show", kind: .cleared),
      record("D", source: "alpha", title: "Other", kind: .cleared),
      record("E", source: "beta", title: "Elsewhere", kind: .kept)
    ]
    let target = listing("future", title: "The Show", start: 100)
    let result = TasteCounts(records: records).result(for: target, sourceRegistryID: "alpha")

    #expect(abs(result.score - 64.0 / 105.0) < 0.000001)
    #expect(result.evidence?.key == .show)
    #expect(result.evidence?.picked == 2)
    #expect(result.evidence?.decided == 3)
    #expect(result.evidence?.name == "The Show")
    #expect(result.evidence?.line == "Kept 2 of 3 · The Show")
  }

  @Test func excludesTheListingItselfFromItsEvidence() {
    let records = [
      record("same", source: "alpha", title: "Solo", stableKey: "same", kind: .kept),
      record("other-1", source: "alpha", title: "Solo", kind: .kept),
      record("other-2", source: "alpha", title: "Solo", kind: .cleared)
    ]
    let target = listing("same", title: "Solo", start: 100)
    let result = TasteCounts(records: records).result(for: target, sourceRegistryID: "alpha")
    #expect(result.evidence == nil)
  }

  @Test func keyPriorityIsShowThenMostDecidedPerformerThenRoom() {
    let records = [
      record("show-1", source: "alpha", title: "A Show", kind: .kept),
      record("show-2", source: "alpha", title: "A Show", kind: .cleared),
      record("person-1", source: "beta", title: "Other", performers: "[\"Zed\"]", kind: .kept),
      record("person-2", source: "gamma", title: "Other", performers: "[\"Zed\"]", kind: .cleared),
      record("person-3", source: "delta", title: "Other", performers: "[\"Zed\"]", kind: .kept),
      record("room-1", source: "alpha", title: "Other", room: "Blue Room", kind: .kept),
      record("room-2", source: "alpha", title: "Other", room: "Blue Room", kind: .cleared),
      record("room-3", source: "alpha", title: "Other", room: "Blue Room", kind: .kept),
      record("room-4", source: "alpha", title: "Other", room: "Blue Room", kind: .cleared)
    ]
    let counts = TasteCounts(records: records)
    let target = listing("target", title: "A Show", performers: "[\"Zed\"]", room: "Blue Room", start: 100)
    #expect(counts.result(for: target, sourceRegistryID: "alpha").evidence?.key == .performer("Zed"))

    let enoughShow = (records + [record("show-3", source: "alpha", title: "A Show", kind: .kept)])
    #expect(TasteCounts(records: enoughShow).result(for: target, sourceRegistryID: "alpha").evidence?.key == .show)
  }

  @Test func performerTieUsesTheNameThatSortsFirstAndMatchesDisplayParsing() {
    let records = [
      record("b1", source: "beta", title: "One", performers: "[\"Björk\"]", kind: .kept),
      record("b2", source: "beta", title: "Two", performers: "[\"Björk\"]", kind: .cleared),
      record("b3", source: "beta", title: "Three", performers: "[\"Björk\"]", kind: .kept),
      record("a1", source: "gamma", title: "One", performers: "[\"A\u{00E9}ro\"]", kind: .kept),
      record("a2", source: "gamma", title: "Two", performers: "[\"A\u{00E9}ro\"]", kind: .cleared),
      record("a3", source: "gamma", title: "Three", performers: "[\"A\u{00E9}ro\"]", kind: .kept)
    ]
    let listing = listing("target", title: "Other", performers: "[\"Björk\",\"Aéro\"]", start: 100)
    let evidence = TasteCounts(records: records).result(for: listing, sourceRegistryID: "alpha").evidence
    #expect(evidence?.key == .performer("Aéro"))
    #expect(evidence?.line == "Kept 2 of 3 · Aéro")
    #expect(TasteCounts.performerNames("[\"One\",\"Two\"]") == ["One", "Two"])
    #expect(TasteCounts.performerNames("legacy name") == ["legacy name"])
  }

  @Test func roomEvidenceIsUsedWhenShowAndPerformerKeysAreTooSparse() {
    let records = [
      record("r1", source: "alpha", title: "Other 1", room: "Blue Room", kind: .kept),
      record("r2", source: "alpha", title: "Other 2", room: "Blue Room", kind: .cleared),
      record("r3", source: "alpha", title: "Other 3", room: "Blue Room", kind: .kept)
    ]
    let target = listing("target", title: "Unseen", room: "Blue Room", start: 100)
    let evidence = TasteCounts(records: records).result(for: target, sourceRegistryID: "alpha").evidence

    #expect(evidence?.key == .room)
    #expect(evidence?.line == "Kept 2 of 3 · Blue Room")
  }

  @Test func evidenceIncludesEveryMatchedKeyInPromptOrder() {
    let records = [
      record("show-1", source: "alpha", title: "The Play", performers: "[\"Performer\"]", room: "Main Room", kind: .kept),
      record("show-2", source: "alpha", title: "The Play", performers: "[\"Performer\"]", room: "Main Room", kind: .cleared),
      record("show-3", source: "alpha", title: "The Play", performers: "[\"Performer\"]", room: "Main Room", kind: .kept),
      record("few-1", source: "alpha", title: "Sparse", performers: "[\"Sparse Performer\"]", kind: .kept),
      record("few-2", source: "alpha", title: "Sparse", performers: "[\"Sparse Performer\"]", kind: .cleared)
    ]
    let target = listing("target", title: "The Play", performers: "[\"Performer\",\"Sparse Performer\"]", room: "Main Room", start: 100)
    let evidence = TasteCounts(records: records).evidence(for: target, sourceRegistryID: "alpha")

    #expect(evidence.map(\.key) == [.show, .performer("Performer"), .room])
    #expect(evidence.map(\.line) == [
      "Kept 2 of 3 · The Play", "Kept 2 of 3 · Performer", "Kept 2 of 3 · Main Room"
    ])
  }

  @Test func evidenceExcludesTheListingBeingSuggested() {
    let records = [
      record("same", source: "alpha", title: "Solo", performers: "[\"Performer\"]", room: "Main Room", kind: .kept),
      record("other-1", source: "alpha", title: "Solo", performers: "[\"Performer\"]", room: "Main Room", kind: .kept),
      record("other-2", source: "alpha", title: "Solo", performers: "[\"Performer\"]", room: "Main Room", kind: .cleared)
    ]
    let target = listing("same", title: "Solo", performers: "[\"Performer\"]", room: "Main Room", start: 100)
    #expect(TasteCounts(records: records).evidence(for: target, sourceRegistryID: "alpha").isEmpty)
  }

  @Test func sortingBreaksScoreTiesByDateThenIDAndDateModeUsesDate() {
    let records = [
      record("pick-1", source: "alpha", title: "Liked", kind: .kept),
      record("pick-2", source: "alpha", title: "Liked", kind: .kept),
      record("pick-3", source: "alpha", title: "Liked", kind: .kept)
    ]
    let later = listing("later", title: "Unseen", start: 200)
    let sameDateB = listing("00000000-0000-0000-0000-000000000002", title: "Unseen", start: 100)
    let sameDateA = listing("00000000-0000-0000-0000-000000000001", title: "Unseen", start: 100)
    let liked = listing("liked", title: "Liked", start: 300)
    let counts = TasteCounts(records: records)

    #expect(counts.sorted([later, sameDateB, sameDateA, liked], sourceRegistryID: "alpha").map(\.id) == [liked.id, sameDateA.id, sameDateB.id, later.id])
    #expect(counts.sorted([later, sameDateB, sameDateA, liked], sourceRegistryID: "alpha", likelyFirst: false).map(\.id) == [sameDateA.id, sameDateB.id, later.id, liked.id])
    #expect(TasteCounts(records: []).sorted([later, sameDateB, sameDateA], sourceRegistryID: "alpha").map(\.id) == [sameDateA.id, sameDateB.id, later.id])
  }

  @Test func verdictsOnlyChangeLikelyFirstOrder() {
    let records = [
      record("liked-1", source: "alpha", title: "Liked", kind: .kept),
      record("liked-2", source: "alpha", title: "Liked", kind: .kept),
      record("liked-3", source: "alpha", title: "Liked", kind: .kept),
      record("cleared-1", source: "alpha", title: "Poor", kind: .cleared),
      record("cleared-2", source: "alpha", title: "Poor", kind: .cleared),
      record("cleared-3", source: "alpha", title: "Poor", kind: .cleared)
    ]
    let highScore = listing("high-score", title: "Liked", start: 200)
    let suggestedKeep = listing("suggested-keep", title: "Unseen", start: 300)
    let lowScore = listing("low-score", title: "Poor", start: 100)
    let suggestedClear = listing("suggested-clear", title: "Liked", start: 400)
    let counts = TasteCounts(records: records)
    let verdicts: [Listing.ID: TasteSuggestion] = [suggestedKeep.id: .keep, suggestedClear.id: .clear]

    #expect(counts.sorted(
      [highScore, lowScore, suggestedKeep, suggestedClear], sourceRegistryID: "alpha", verdicts: verdicts
    ).map(\.id) == [suggestedKeep.id, highScore.id, lowScore.id, suggestedClear.id])
    #expect(counts.sorted(
      [highScore, lowScore, suggestedKeep, suggestedClear], sourceRegistryID: "alpha", likelyFirst: false,
      verdicts: verdicts
    ).map(\.id) == [lowScore.id, highScore.id, suggestedKeep.id, suggestedClear.id])
    #expect(counts.sorted(
      [highScore, lowScore, suggestedKeep, suggestedClear], sourceRegistryID: "alpha"
    ) == counts.sorted([highScore, lowScore, suggestedKeep, suggestedClear], sourceRegistryID: "alpha", verdicts: [:]))
  }

  private func record(
    _ id: String,
    source: String,
    title: String,
    stableKey: String? = nil,
    performers: String = "[]",
    room: String? = nil,
    kind: ReactionKind
  ) -> TasteRecord {
    TasteRecord(
      id: UUID(), householdID: UUID(), sourceRegistryID: source, sourceName: source,
      stableKey: stableKey ?? id, title: title, performers: performers, room: room,
      startsAt: Date(timeIntervalSince1970: 50), kind: kind,
      firstDecidedAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 20)
    )
  }

  private func listing(
    _ id: String, title: String, performers: String = "[]", room: String? = nil, start: TimeInterval
  ) -> Listing {
    Listing(
      id: UUID(uuidString: id) ?? UUID(), sourceID: UUID(), stableKey: id, title: title,
      performers: performers, room: room, startsAt: Date(timeIntervalSince1970: start),
      rung: .model, capturedBy: .mac
    )
  }
}
