import Foundation

extension ExtractionEngine {
  public func hasDeterministicRung(_ document: PageDocument, sourceURL: URL, source: SourceDescriptor) -> Bool {
    !deterministicListings(document, sourceURL: sourceURL, source: source).isEmpty
  }

  public func deterministicListings(
    _ document: PageDocument, sourceURL: URL, source: SourceDescriptor
  ) -> [ExtractedListing] {
    if let adapter = source.adapter {
      let listings = Self.adapterListings(adapter, document: document, sourceURL: sourceURL, source: source)
      if !listings.isEmpty { return Self.deduplicated(listings) }
    }
    guard let events = try? Self.jsonLDEvents(in: document) else { return [] }
    return Self.deduplicated(events.compactMap { Self.listing(from: $0, source: source, rung: .jsonLD) })
  }

  static func deduplicated(_ listings: [ExtractedListing]) -> [ExtractedListing] {
    var seenKeys = Set<String>()
    return listings.filter { seenKeys.insert($0.stableKey).inserted }
  }

  static func hasExcludedHost(_ value: String?, in excludedHosts: [String]) -> Bool {
    guard let value, let host = URL(string: value)?.host?.lowercased() else { return false }
    return excludedHosts.contains { excludedHost in
      let excluded = excludedHost.lowercased()
      return host == excluded || host.hasSuffix(".\(excluded)")
    }
  }

  static func sameNYCDay(_ lhs: Date, _ rhs: Date) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar.isDate(lhs, inSameDayAs: rhs)
  }

  static func offerWithURL(_ value: Any?) -> [String: Any]? {
    func hasURL(_ offer: [String: Any]) -> Bool {
      guard let url = offer["url"] as? String else { return false }
      return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if let offer = value as? [String: Any], hasURL(offer) { return offer }
    return (value as? [[String: Any]])?.first(where: hasURL)
  }
}
