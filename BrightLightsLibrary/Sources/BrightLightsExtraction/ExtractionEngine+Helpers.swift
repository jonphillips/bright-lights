import Foundation
import LLMClientKit

extension ExtractionEngine {
  static func modelSchema() -> JSONValue {
    [
      "type": "object",
      "properties": [
        "listings": [
          "type": "array",
          "items": [
            "type": "object",
            "properties": [
              "title": ["type": "string"],
              "performers": ["type": "array", "items": ["type": "string"]],
              "room": ["type": "string"],
              "startsAt": ["type": "string"],
              "opensAt": ["type": "string"],
              "closesAt": ["type": "string"],
              "eventURL": ["type": "string"],
              "ticketURL": ["type": "string"],
              "onSaleDate": ["type": "string"],
              "status": ["type": "string", "enum": ["listed", "soldOut", "cancelled"]]
            ],
            "required": ["title", "performers", "room", "startsAt", "opensAt", "closesAt", "eventURL", "ticketURL", "onSaleDate", "status"],
            "additionalProperties": .bool(false)
          ]
        ]
      ],
      "required": ["listings"],
      "additionalProperties": .bool(false)
    ]
  }

  static func newYorkDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

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

  static func eventbriteOrganizerListings(
    _ document: PageDocument, sourceURL: URL, source: SourceDescriptor
  ) -> [ExtractedListing] {
    guard let arrayText = embeddedArray(named: "upcomingEvents", in: document.rawValue),
      let data = arrayText.data(using: .utf8),
      let events = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return [] }
    return events.compactMap { event in
      guard let title = organizerString(event["name"]),
        let date = organizerString(event["start_date"]),
        let time = organizerString(event["start_time"]),
        let timezoneName = organizerString(event["timezone"]),
        let timezone = TimeZone(identifier: timezoneName),
        let start = organizerStart(date: date, time: time, timezone: timezone),
        let url = organizerString(event["url"])
      else { return nil }
      let normalizedTitle = title.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }.joined(separator: " ")
      return ExtractedListingFactory.make(source: source, sourceURL: sourceURL,
        identity: url, title: normalizedTitle, performers: [], room: nil,
        time: .performance(start), ticketURL: url, onSaleDate: nil,
        status: event["is_cancelled"] as? Bool == true ? .cancelled : .listed, rung: .adapter)
    }
  }

  private static func organizerString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func organizerStart(date: String, time: String, timezone: TimeZone) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timezone
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd h:mm a", "yyyy-MM-dd hh:mm a", "yyyy-MM-dd HH:mm", "yyyy-MM-dd H:mm"] {
      formatter.dateFormat = format
      if let parsed = formatter.date(from: "\(date) \(time)") { return parsed }
    }
    return nil
  }

  private static func embeddedArray(named name: String, in text: String) -> String? {
    guard let keyRange = text.range(of: "\"\(name)\""),
      let colon = text[keyRange.upperBound...].firstIndex(of: ":"),
      let opening = text[text.index(after: colon)...].firstIndex(of: "[") else { return nil }
    let characters = Array(text[opening...])
    var depth = 0
    var inString = false
    var escaped = false
    for (offset, character) in characters.enumerated() {
      if inString {
        if escaped { escaped = false }
        else if character == "\\" { escaped = true }
        else if character == "\"" { inString = false }
        continue
      }
      if character == "\"" { inString = true }
      else if character == "[" { depth += 1 }
      else if character == "]" {
        depth -= 1
        if depth == 0 { return String(characters[...offset]) }
      }
    }
    return nil
  }
}
