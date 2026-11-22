import Foundation
import SQLiteData

private struct SourceRegistryFile: Decodable {
  var version: String
  var sources: [RegistrySource]

  enum CodingKeys: String, CodingKey {
    case sources
    case version = "registry_version"
  }
}

private struct RegistrySource: Decodable {
  var id: String
  var name: String
  var sourceType: String
  var area: String?
  var priority: String
  var listingURL: String
  var registeredHosts: [String]?
  var excludedHosts: [String]?
  var mode: String
  var method: String
  var adapter: String?
  var adapterVenue: String?
  var cadence: String
  var operationalStatus: String?
  var pagination: RegistryPagination?
  var feedURL: String?

  enum CodingKeys: String, CodingKey {
    case id, name, area, priority, mode, method, adapter, cadence
    case sourceType = "source_type"
    case listingURL = "listing_url"
    case registeredHosts = "registered_hosts"
    case excludedHosts = "excluded_hosts"
    case adapterVenue = "adapter_venue"
    case operationalStatus = "operational_status"
    case feedURL = "feed_url"
    case pagination
  }

  var isSeedable: Bool { mode != "skip" && priority != "retired" && operationalStatus != "retired" }
  var sourceMode: SourceMode? { SourceMode(rawValue: mode) }
}

private struct RegistryPagination: Codable {
  var kind: String
  var template: String
  var first: Int?
  var max: Int?
  var monthsAhead: Int?

  enum CodingKeys: String, CodingKey {
    case kind, template, first, max
    case monthsAhead = "months_ahead"
  }

  var encoded: String? {
    var object: [String: Any] = ["kind": kind, "template": template]
    if let first { object["first"] = first }
    if let max { object["max"] = max }
    if let monthsAhead { object["months_ahead"] = monthsAhead }
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}

public enum SourceRegistryError: Error {
  case resourceMissing
  case invalidMode(String)
  case invalidRegistryVersion(String)
}

public struct RegistryVersion: RawRepresentable, Comparable, Sendable, Equatable {
  public var components: [Int]

  public init?(rawValue: String) {
    let pieces = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
    var values: [Int] = []
    for piece in pieces {
      guard let value = Int(piece) else { return nil }
      values.append(value)
    }
    self.components = values
  }

  public var rawValue: String { components.map(String.init).joined(separator: ".") }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right { return left < right }
    }
    return false
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }
}

public extension Source {
  /// Reconcile registry-owned configuration without changing check history.
  /// Offline duplicate seeds converge on their oldest `(createdAt, id)` row.
  static func syncFromRegistry(in db: Database) throws {
    guard let url = Bundle.module.url(forResource: "registry", withExtension: "json") else {
      throw SourceRegistryError.resourceMissing
    }
    try syncFromRegistry(data: Data(contentsOf: url), in: db)
  }

  static func syncFromRegistry(data: Data, in db: Database) throws {
    let registry = try JSONDecoder().decode(SourceRegistryFile.self, from: data)
    let household = try Household.ensureDefault(in: db)
    guard let bundledVersion = RegistryVersion(rawValue: registry.version) else {
      throw SourceRegistryError.invalidRegistryVersion(registry.version)
    }
    let existing = try Source.fetchAll(db).sorted {
      $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
    }
    let grouped = Dictionary(grouping: existing, by: \.registryID)
    if let rawStoredVersion = household.registryVersion {
      guard let storedVersion = RegistryVersion(rawValue: rawStoredVersion) else {
        throw SourceRegistryError.invalidRegistryVersion(rawStoredVersion)
      }
      if bundledVersion < storedVersion {
        // An older build writes no registry fields, but converging duplicates isn't a registry write (ADR-0009 point 5).
        for matches in grouped.values {
          if let survivor = matches.first { try converge(matches, onto: survivor, in: db) }
        }
        return
      }
    }
    let incoming = registry.sources.filter(\.isSeedable)
    let incomingIDs = Set(incoming.map(\.id))

    for source in existing where !incomingIDs.contains(source.registryID) && source.retiredAt == nil {
      try Source.find(source.id).update { $0.retiredAt = #bind(Date.now) }.execute(db)
    }

    for item in incoming {
      guard let sourceMode = item.sourceMode else {
        throw SourceRegistryError.invalidMode(item.mode)
      }
      let matches = grouped[item.id, default: []]
      if let survivor = matches.first {
        try converge(matches, onto: survivor, in: db)
        try update(survivor, from: item, mode: sourceMode, householdID: household.id, in: db)
      } else {
        try insert(item, mode: sourceMode, householdID: household.id, in: db)
      }
    }
    if household.registryVersion != bundledVersion.rawValue {
      try Household.find(household.id).update { $0.registryVersion = #bind(bundledVersion.rawValue) }.execute(db)
    }
  }

  private static func converge(_ sources: [Source], onto survivor: Source, in db: Database) throws {
    for duplicate in sources.dropFirst() {
      try Listing.where { $0.sourceID.eq(duplicate.id) }
        .update { $0.sourceID = #bind(survivor.id) }.execute(db)
      try Source.find(duplicate.id).delete().execute(db)
    }
  }

  private static func update(
    _ source: Source, from item: RegistrySource, mode: SourceMode, householdID: UUID, in db: Database
  ) throws {
    let registeredHosts = try encodeJSON(item.registeredHosts ?? [])
    let excludedHosts = try encodeJSON(item.excludedHosts ?? [])
    let startPageURL = source.startPageURL == item.listingURL ? nil : source.startPageURL
    guard source.householdID != householdID || source.name != item.name
      || source.type != item.sourceType || source.priority != item.priority
      || source.area != (item.area ?? "") || source.mode != mode || source.method != item.method
      || source.adapter != item.adapter || source.adapterVenue != item.adapterVenue
      || source.listingURL != item.listingURL || source.feedURL != item.feedURL || source.registeredHosts != registeredHosts
      || source.excludedHosts != excludedHosts || source.cadence != item.cadence
      || source.pagination != item.pagination?.encoded || source.retiredAt != nil
      || source.startPageURL != startPageURL
    else { return }
    try Source.find(source.id).update {
      $0.householdID = #bind(householdID)
      $0.name = #bind(item.name)
      $0.type = #bind(item.sourceType)
      $0.priority = #bind(item.priority)
      $0.area = #bind(item.area ?? "")
      $0.mode = #bind(mode)
      $0.method = #bind(item.method)
      $0.adapter = #bind(item.adapter)
      $0.adapterVenue = #bind(item.adapterVenue)
      $0.listingURL = #bind(item.listingURL)
      $0.startPageURL = #bind(startPageURL)
      $0.feedURL = #bind(item.feedURL)
      $0.registeredHosts = #bind(registeredHosts)
      $0.excludedHosts = #bind(excludedHosts)
      $0.cadence = #bind(item.cadence)
      $0.pagination = #bind(item.pagination?.encoded)
      if source.retiredAt != nil { $0.retiredAt = #bind(nil as Date?) }
    }.execute(db)
  }

  private static func insert(
    _ item: RegistrySource, mode: SourceMode, householdID: UUID, in db: Database
  ) throws {
    let source = Source(
      id: UUID(), householdID: householdID, registryID: item.id, name: item.name,
      type: item.sourceType, priority: item.priority, area: item.area ?? "",
      mode: mode, method: item.method, adapter: item.adapter,
      adapterVenue: item.adapterVenue, listingURL: item.listingURL, feedURL: item.feedURL,
      registeredHosts: try encodeJSON(item.registeredHosts ?? []),
      excludedHosts: try encodeJSON(item.excludedHosts ?? []), cadence: item.cadence,
      pagination: item.pagination?.encoded
    )
    try Source.insert { Source.Draft(source) }.execute(db)
  }
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
  let data = try JSONEncoder().encode(value)
  return String(decoding: data, as: UTF8.self)
}
