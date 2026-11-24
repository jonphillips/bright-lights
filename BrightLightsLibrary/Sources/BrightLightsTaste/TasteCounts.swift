import Foundation
import BrightLightsSchema

public struct TasteCounts: Sendable {
  public enum EvidenceKey: Equatable, Sendable {
    case show
    case performer(String)
    case room
  }

  public struct Evidence: Equatable, Sendable {
    public let key: EvidenceKey
    public let picked: Int
    public let decided: Int
    public let name: String

    public var line: String { "Kept \(picked) of \(decided) · \(name)" }
  }

  public struct Result: Equatable, Sendable {
    public let score: Double
    public let evidence: Evidence?
  }

  private struct Counts: Sendable {
    var picked = 0
    var decided = 0

    mutating func add(_ kind: ReactionKind) {
      guard kind.isPicked || kind.isHidden else { return }
      decided += 1
      if kind.isPicked { picked += 1 }
    }

    mutating func subtract(_ other: Counts) {
      picked -= other.picked
      decided -= other.decided
    }

    func rate(prior: Double) -> Double {
      (Double(picked) + 2 * prior) / (Double(decided) + 2)
    }
  }

  private struct ListingKey: Hashable, Sendable {
    let source: String
    let stableKey: String
  }

  private struct Key: Hashable, Sendable {
    let source: String?
    let value: String
  }

  private struct Contribution: Sendable {
    var counts = Counts()
    var show: Key?
    var room: Key?
    var performers: Set<String> = []
  }

  private var global = Counts()
  private var sources: [String: Counts] = [:]
  private var shows: [Key: Counts] = [:]
  private var rooms: [Key: Counts] = [:]
  private var performers: [String: Counts] = [:]
  private var contributions: [ListingKey: Contribution] = [:]

  public init(records: [TasteRecord]) {
    for record in records {
      guard record.kind.isPicked || record.kind.isHidden else { continue }
      let sourceID = record.sourceRegistryID
      let normalizedTitle = Self.normalized(record.title)
      let normalizedRoom = record.room.map(Self.normalized).flatMap { $0.isEmpty ? nil : $0 }
      let normalizedPerformers = Set(Self.performerNames(record.performers).map(Self.normalized).filter { !$0.isEmpty })
      let listingKey = ListingKey(source: sourceID, stableKey: record.stableKey)
      let showKey = Key(source: sourceID, value: normalizedTitle)
      let roomKey = normalizedRoom.map { Key(source: sourceID, value: $0) }

      global.add(record.kind)
      sources[sourceID, default: Counts()].add(record.kind)
      shows[showKey, default: Counts()].add(record.kind)
      if let roomKey { rooms[roomKey, default: Counts()].add(record.kind) }
      for performer in normalizedPerformers { performers[performer, default: Counts()].add(record.kind) }

      var contribution = contributions[listingKey] ?? Contribution()
      contribution.counts.add(record.kind)
      contribution.show = showKey
      contribution.room = roomKey
      contribution.performers.formUnion(normalizedPerformers)
      contributions[listingKey] = contribution
    }
  }

  public func result(for listing: Listing, sourceRegistryID: String) -> Result {
    let own = contributions[ListingKey(source: sourceRegistryID, stableKey: listing.stableKey)] ?? Contribution()
    var globalWithoutListing = global
    globalWithoutListing.subtract(own.counts)
    var sourceWithoutListing = sources[sourceRegistryID] ?? Counts()
    sourceWithoutListing.subtract(own.counts)
    let globalRate = (Double(globalWithoutListing.picked) + 1) / (Double(globalWithoutListing.decided) + 2)
    let sourceRate = sourceWithoutListing.rate(prior: globalRate)

    let showKey = Key(source: sourceRegistryID, value: Self.normalized(listing.title))
    var showCounts = shows[showKey] ?? Counts()
    if own.show == showKey { showCounts.subtract(own.counts) }
    if showCounts.decided >= 3 {
      return Result(score: showCounts.rate(prior: sourceRate), evidence: Evidence(
        key: .show, picked: showCounts.picked, decided: showCounts.decided, name: listing.title
      ))
    }

    let names = Self.performerNames(listing.performers)
    let matchingPerformers = names.compactMap { name -> (String, Counts)? in
      let normalized = Self.normalized(name)
      guard !normalized.isEmpty else { return nil }
      var counts = performers[normalized] ?? Counts()
      if own.performers.contains(normalized) { counts.subtract(own.counts) }
      return counts.decided >= 3 ? (name, counts) : nil
    }
    if let selected = matchingPerformers.sorted(by: {
      if $0.1.decided != $1.1.decided { return $0.1.decided > $1.1.decided }
      return Self.normalized($0.0) < Self.normalized($1.0)
    }).first {
      return Result(score: selected.1.rate(prior: sourceRate), evidence: Evidence(
        key: .performer(selected.0), picked: selected.1.picked, decided: selected.1.decided, name: selected.0
      ))
    }

    if let room = listing.room, !room.isEmpty {
      let key = Key(source: sourceRegistryID, value: Self.normalized(room))
      var counts = rooms[key] ?? Counts()
      if own.room == key { counts.subtract(own.counts) }
      if counts.decided >= 3 {
        return Result(score: counts.rate(prior: sourceRate), evidence: Evidence(
          key: .room, picked: counts.picked, decided: counts.decided, name: room
        ))
      }
    }
    return Result(score: sourceRate, evidence: nil)
  }

  public func sorted(
    _ listings: [Listing], sourceRegistryID: String, likelyFirst: Bool = true
  ) -> [Listing] {
    listings.sorted { lhs, rhs in
      if likelyFirst {
        let lhsScore = result(for: lhs, sourceRegistryID: sourceRegistryID).score
        let rhsScore = result(for: rhs, sourceRegistryID: sourceRegistryID).score
        if lhsScore != rhsScore { return lhsScore > rhsScore }
      }
      if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  public static func performerNames(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8),
      let names = try? JSONDecoder().decode([String].self, from: data) else { return [json] }
    return names
  }

  public static func normalized(_ value: String) -> String {
    let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    var result = ""
    var needsSpace = false
    for scalar in folded.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        if needsSpace, !result.isEmpty { result.append(" ") }
        result.unicodeScalars.append(scalar)
        needsSpace = false
      } else {
        needsSpace = true
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
