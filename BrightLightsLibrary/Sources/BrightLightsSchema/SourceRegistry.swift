import Foundation
import SQLiteData

private struct SourceRegistryFile: Decodable {
  var sources: [RegistrySource]
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

  enum CodingKeys: String, CodingKey {
    case id, name, area, priority, mode, method, adapter, cadence
    case sourceType = "source_type"
    case listingURL = "listing_url"
    case registeredHosts = "registered_hosts"
    case excludedHosts = "excluded_hosts"
    case adapterVenue = "adapter_venue"
    case operationalStatus = "operational_status"
  }

  var isSeedable: Bool { mode != "skip" && priority != "retired" && operationalStatus != "retired" }
  var sourceMode: SourceMode { SourceMode(rawValue: mode) ?? .manual }
}

public enum SourceRegistryError: Error {
  case resourceMissing
  case invalidMode(String)
}

public extension Source {
  /// Reconcile registry-owned configuration without changing check history.
  /// Offline duplicate seeds converge on their oldest `(createdAt, id)` row.
  static func syncFromRegistry(in db: Database) throws {
    guard let url = Bundle.module.url(forResource: "registry", withExtension: "json") else {
      throw SourceRegistryError.resourceMissing
    }
    let registry = try JSONDecoder().decode(SourceRegistryFile.self, from: Data(contentsOf: url))
    let household = try Household.ensureDefault(in: db)
    let existing = try Source.fetchAll(db).sorted {
      $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
    }
    let grouped = Dictionary(grouping: existing, by: \.registryID)
    let incoming = registry.sources.filter(\.isSeedable)

    for item in incoming {
      guard item.mode == "automated" || item.mode == "manual" else {
        throw SourceRegistryError.invalidMode(item.mode)
      }
      let duplicates = grouped[item.id, default: []]
      let survivor = duplicates.first
      if let survivor {
        let registeredHosts = try encodeJSON(item.registeredHosts ?? [])
        let excludedHosts = try encodeJSON(item.excludedHosts ?? [])
        for duplicate in duplicates.dropFirst() {
          try Listing.where { $0.sourceID.eq(duplicate.id) }
            .update { $0.sourceID = #bind(survivor.id) }.execute(db)
          try Source.find(duplicate.id).delete().execute(db)
        }
        try Source.find(survivor.id).update {
          $0.householdID = #bind(household.id)
          $0.name = #bind(item.name)
          $0.type = #bind(item.sourceType)
          $0.priority = #bind(item.priority)
          $0.area = #bind(item.area ?? "")
          $0.mode = #bind(item.sourceMode)
          $0.method = #bind(item.method)
          $0.adapter = #bind(item.adapter)
          $0.adapterVenue = #bind(item.adapterVenue)
          $0.listingURL = #bind(item.listingURL)
          $0.registeredHosts = #bind(registeredHosts)
          $0.excludedHosts = #bind(excludedHosts)
          $0.cadence = #bind(item.cadence)
        }.execute(db)
      } else {
        let source = Source(
          id: UUID(), householdID: household.id, registryID: item.id, name: item.name,
          type: item.sourceType, priority: item.priority, area: item.area ?? "",
          mode: item.sourceMode, method: item.method, adapter: item.adapter,
          adapterVenue: item.adapterVenue, listingURL: item.listingURL,
          registeredHosts: try encodeJSON(item.registeredHosts ?? []),
          excludedHosts: try encodeJSON(item.excludedHosts ?? []), cadence: item.cadence
        )
        try Source.insert { Source.Draft(source) }.execute(db)
      }
    }
  }
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
  let data = try JSONEncoder().encode(value)
  return String(decoding: data, as: UTF8.self)
}
