import Foundation

public struct NewSourceGroup: Identifiable, Sendable {
  public let source: Source
  public let listings: [Listing]
  public var count: Int { listings.count }
  public var id: Source.ID { source.id }
}

public struct NewProjection: Sendable {
  public let groups: [NewSourceGroup]
  public var total: Int { groups.reduce(0) { $0 + $1.count } }

  public init(
    listings: [Listing], sources: [Source], reactions: [Reaction], tasteRecordIDs: Set<UUID>, now: Date
  ) {
    let activeSources = sources.filter { $0.retiredAt == nil }
    let activeIDs = Set(activeSources.map(\.id))
    let sourcesByID = Dictionary(activeSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let reactedIDs = Set(reactions.map(\.listingID))
    let unscreened = listings.filter { listing in
      guard let source = sourcesByID[listing.sourceID] else { return false }
      let tasteRecordID = TasteRecord.id(
        householdID: source.householdID, sourceRegistryID: source.registryID, stableKey: listing.stableKey
      )
      return activeIDs.contains(listing.sourceID)
        && !reactedIDs.contains(listing.id)
        && !tasteRecordIDs.contains(tasteRecordID)
        && (listing.status == .listed || listing.status == .soldOut)
        && (listing.closesAt ?? listing.startsAt) >= now
    }
    let bySource = Dictionary(grouping: unscreened, by: \.sourceID)
    groups = activeSources.compactMap { source in
      guard let listings = bySource[source.id], !listings.isEmpty else { return nil }
      return NewSourceGroup(source: source, listings: listings.sorted {
        if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
        return $0.id.uuidString < $1.id.uuidString
      })
    }.sorted {
      if $0.source.name != $1.source.name { return $0.source.name.localizedStandardCompare($1.source.name) == .orderedAscending }
      return $0.source.id.uuidString < $1.source.id.uuidString
    }
  }

  public func count(for sourceID: Source.ID) -> Int {
    groups.first { $0.source.id == sourceID }?.count ?? 0
  }
}
