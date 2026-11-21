import Foundation
import BrightLightsSchema
import Testing

@Suite
struct NewProjectionTests {
  @Test func groupsOnlyUnscreenedFutureListingsFromActiveSources() {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let active = source("Alpha", retiredAt: nil)
    let other = source("Beta", retiredAt: nil)
    let retired = source("Retired", retiredAt: now)
    let late = listing("Later", source: active, start: now.addingTimeInterval(200))
    let early = listing("Earlier", source: active, start: now.addingTimeInterval(100))
    let soldOut = listing("Sold out", source: other, start: now, status: .soldOut)
    let reacted = listing("Reacted", source: other, start: now)
    let past = listing("Past", source: other, start: now.addingTimeInterval(-1))
    let cancelled = listing("Cancelled", source: other, start: now, status: .cancelled)
    let retiredListing = listing("Retired", source: retired, start: now)
    let reactions = [Reaction(id: UUID(), listingID: reacted.id, kind: .kept)]

    let result = NewProjection(
      listings: [late, early, soldOut, reacted, past, cancelled, retiredListing],
      sources: [other, retired, active], reactions: reactions, tasteRecordIDs: [], now: now
    )

    #expect(result.groups.map(\.source.name) == ["Alpha", "Beta"])
    #expect(result.groups.first?.listings.map(\.title) == ["Earlier", "Later"])
    #expect(result.groups.last?.listings.map(\.title) == ["Sold out"])
    #expect(result.count(for: active.id) == 2)
    #expect(result.count(for: other.id) == 1)
    #expect(result.total == 3)
  }

  private func source(_ name: String, retiredAt: Date?) -> Source {
    Source(
      id: UUID(), householdID: UUID(), registryID: name, name: name, type: "venue",
      priority: "core", area: "NYC", mode: .manual, method: "manual",
      listingURL: "https://example.com/events", registeredHosts: "[]", cadence: "weekly",
      retiredAt: retiredAt
    )
  }

  private func listing(_ title: String, source: Source, start: Date, status: ListingStatus = .listed) -> Listing {
    Listing(id: UUID(), sourceID: source.id, stableKey: title, title: title, startsAt: start,
      status: status, rung: .model, capturedBy: .mac)
  }
}
