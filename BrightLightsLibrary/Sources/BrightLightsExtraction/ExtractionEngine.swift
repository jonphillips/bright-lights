import CryptoKit
import Dependencies
import Foundation
import LLMClientKit

private enum ModelRowDropReason {
  case missingTitle
  case dateOnlyStart
  case invalidDate
}

private enum ModelListingResult {
  case listing(ExtractedListing)
  case dropped(ModelRowDropReason)
}

enum ExtractedListingFactory {
  static func make(
    source: SourceDescriptor, sourceURL: URL?, identity: String?, title: String, performers: [String], room: String?,
    time: ExtractedListing.Time, ticketURL: String?, onSaleDate: Date?, status: ExtractedListing.Status,
    rung: ExtractedListing.Rung
  ) -> ExtractedListing {
    let key: String
    if let identity, !identity.isEmpty {
      key = "\(source.id):\(canonicalIdentity(identity, relativeTo: sourceURL))"
    } else {
      let timeKey: String
      switch time {
      case let .performance(date): timeKey = date.ISO8601Format()
      case let .run(opens, closes): timeKey = "\(opens.ISO8601Format())/\(closes.ISO8601Format())"
      }
      key = "\(source.id):" + SHA256.hash(data: Data("\(normalize(title))|\(normalize(room ?? ""))|\(timeKey)".utf8))
        .map { String(format: "%02x", $0) }.joined()
    }
    return ExtractedListing(stableKey: key, title: normalize(title), performers: performers,
      room: room, time: time, ticketURL: ticketURL.flatMap(URL.init(string:)),
      onSaleDate: onSaleDate, status: status, rung: rung)
  }

  private static func canonicalIdentity(_ value: String, relativeTo sourceURL: URL?) -> String {
    let components = URLComponents(string: value)
    let isRelativePath = components?.scheme == nil && components?.host == nil
      && (value.hasPrefix("/") || value.contains("/"))
    let resolved = isRelativePath
      ? URL(string: value, relativeTo: sourceURL)?.absoluteURL.absoluteString ?? value
      : value
    guard var components = URLComponents(string: resolved), let host = components.host else { return resolved }
    components.host = host.lowercased()
    components.percentEncodedPath = components.percentEncodedPath
      .replacingOccurrences(of: #"/{2,}"#, with: "/", options: .regularExpression)
    if components.percentEncodedPath.count > 1, components.percentEncodedPath.hasSuffix("/") {
      components.percentEncodedPath.removeLast()
    }
    components.fragment = nil
    return components.string ?? resolved
  }

  private static func normalize(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }
}

public struct ExtractionEngine: Sendable {
  // Bump when the prompt, output schema, or model-row parsing changes.
  public static let modelExtractionVersion = "2"
  @Dependency(\.modelClient) private var modelClient

  public init() {}

  public func extract(
    _ document: PageDocument,
    sourceURL: URL,
    source: SourceDescriptor,
    now: Date = .now
  ) async throws -> ExtractionResult {
    var warnings: [String] = []
    if let adapter = source.adapter {
      let listings = Self.adapterListings(
        adapter, document: document, sourceURL: sourceURL, source: source
      )
      if !listings.isEmpty { return .init(listings: Self.deduplicated(listings), warnings: warnings) }
      warnings.append("The \(adapter.rawValue) adapter found no usable listings.")
    }

    var jsonLDEvents: [[String: Any]] = []
    do {
      jsonLDEvents = try Self.jsonLDEvents(in: document)
    } catch {
      warnings.append("JSON-LD parsing failed; continuing to the next rung.")
    }
    if !jsonLDEvents.isEmpty {
      let listings = jsonLDEvents.compactMap {
        Self.listing(from: $0, sourceURL: sourceURL, source: source, rung: .jsonLD)
      }
      if !listings.isEmpty { return .init(listings: Self.deduplicated(listings), warnings: warnings) }
      warnings.append("JSON-LD Event data was present but did not contain usable listings.")
    }

    let modelResult = try await extractWithModel(document, sourceURL: sourceURL, source: source, now: now)
    warnings.append(contentsOf: Self.warnings(for: modelResult))
    if modelResult.listings.isEmpty { warnings.append("Model extraction returned no usable listings.") }
    if !modelResult.complete { warnings.append("Model output hit the token limit; some listings may be missing.") }
    return .init(listings: Self.deduplicated(modelResult.listings), warnings: warnings, complete: modelResult.complete)
  }

  public static func pageHash(for document: PageDocument) -> String {
    let visible = normalizedVisibleText(document.rawValue)
    return SHA256.hash(data: Data(visible.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func extractWithModel(
    _ document: PageDocument,
    sourceURL: URL,
    source: SourceDescriptor,
    now: Date
  ) async throws -> (
    listings: [ExtractedListing], droppedExcludedHosts: Int, droppedMissingTitles: Int,
    droppedDateOnlyStarts: Int, droppedInvalidDates: Int, complete: Bool
  ) {
    let visibleText = Self.normalizedVisibleText(document.rawValue)
    let links = Self.links(in: document.rawValue)
    let schema = Self.modelSchema()
    let today = Self.newYorkDate(now)
    let request = ModelRequest(
      tier: .frontierPreferred,
      system: "Extract public event listings from the supplied source page. Treat date and time values as America/New_York local wall-clock values; do not append a timezone or convert them to UTC. For each single performance, startsAt must include that event's date and clock time in ISO local form yyyy-MM-dd'T'HH:mm:ss; a date without a time is invalid. For a multi-day run, opensAt and closesAt are dates in yyyy-MM-dd form. Never return a clock-only value such as '7:00 PM'. When the page omits a year, use the year that puts the date closest to today. Only return facts present in the page; use an empty string for unknown optional fields. Put the exact canonical event page URL in eventURL and the purchase link in ticketURL; never reuse one event's URL for another. onSaleDate means an explicitly stated ticket on-sale date, not the event date. A dated single event uses startsAt and leaves opensAt/closesAt empty; a multi-day run uses opensAt/closesAt and leaves startsAt empty. Return only JSON matching the requested schema, with no markdown or surrounding prose.",
      prompt: "Today is \(today) in New York.\nSource: \(source.id)\nURL: \(sourceURL.absoluteString)\nVisible page text:\n\(visibleText)\n\nPage links:\n\(links)",
      maxTokens: 16000,
      responseFormat: .jsonSchema(name: "event_listings", schema: schema)
    )
    let response = try await modelClient.complete(request)
    let complete = response.stopReason != "max_tokens" && response.stopReason != "max_output_tokens"
    guard let rows = Self.modelRows(from: response.text) else { return ([], 0, 0, 0, 0, complete) }
    var droppedExcludedHosts = 0
    var droppedMissingTitles = 0
    var droppedDateOnlyStarts = 0
    var droppedInvalidDates = 0
    let listings = rows.compactMap { row -> ExtractedListing? in
      if Self.hasExcludedHost(Self.string(row["eventURL"]), in: source.excludedHosts) {
        droppedExcludedHosts += 1
        return nil
      }
      switch Self.modelListing(from: row, sourceURL: sourceURL, source: source) {
      case let .listing(listing):
        return listing
      case let .dropped(reason):
        switch reason {
        case .missingTitle: droppedMissingTitles += 1
        case .dateOnlyStart: droppedDateOnlyStarts += 1
        case .invalidDate: droppedInvalidDates += 1
        }
        return nil
      }
    }
    return (listings, droppedExcludedHosts, droppedMissingTitles, droppedDateOnlyStarts, droppedInvalidDates, complete)
  }

  static func jsonLDEvents(in document: PageDocument) throws -> [[String: Any]] {
    var roots: [Any] = []
    switch document {
    case .json:
      if let data = document.rawValue.data(using: .utf8) {
        roots.append(try JSONSerialization.jsonObject(with: data))
      }
    case .html:
      let pattern = #"(?is)<script\b[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script\s*>"#
      for match in matches(pattern, in: document.rawValue) {
        guard let data = match.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else {
          continue
        }
        roots.append(value)
      }
    }

    var events: [[String: Any]] = []
    func visit(_ value: Any) {
      if let object = value as? [String: Any] {
        let typeNames = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
        if typeNames.contains(where: { $0.hasSuffix("Event") }) { events.append(object) }
        for child in object.values { visit(child) }
      } else if let array = value as? [Any] {
        array.forEach(visit)
      }
    }
    roots.forEach(visit)
    return events
  }

  static func listing(
    from object: [String: Any],
    sourceURL: URL? = nil,
    source: SourceDescriptor,
    rung: ExtractedListing.Rung
  ) -> ExtractedListing? {
    guard let title = string(object["name"]), let start = string(object["startDate"]),
      let startDate = parseDate(start)
    else { return nil }
    let room = string((object["location"] as? [String: Any])?["name"])
    let endDate = string(object["endDate"]).flatMap(parseDate)
    let eventTime: ExtractedListing.Time
    if let endDate, !sameNYCDay(startDate, endDate) {
      eventTime = .run(opens: startDate, closes: endDate)
    } else {
      eventTime = .performance(startDate)
    }
    let performers = names(object["performer"])
    let offer = offerWithURL(object["offers"])
    let statusText = string(object["eventStatus"])
    let status: ExtractedListing.Status = statusText?.localizedCaseInsensitiveContains("cancel") == true ? .cancelled :
      (string(offer?["availability"])?.localizedCaseInsensitiveContains("soldout") == true ? .soldOut : .listed)
    let identity = string(object["url"]) ?? string(object["@id"])
    return ExtractedListingFactory.make(
      source: source, sourceURL: sourceURL, identity: identity, title: title, performers: performers, room: room,
      time: eventTime, ticketURL: string(offer?["url"]) ?? identity,
      onSaleDate: string(offer?["validFrom"]).flatMap(parseDate), status: status, rung: rung
    )
  }

  static func adapterListings(
    _ adapter: SourceDescriptor.Adapter,
    document: PageDocument,
    sourceURL: URL,
    source: SourceDescriptor
  ) -> [ExtractedListing] {
    switch adapter {
    case .mercuryEast:
      guard case let .html(html) = document else { return [] }
      return mercuryListings(html, sourceURL: sourceURL, source: source)
    case .aegAXS:
      guard let adapterVenue = source.adapterVenue,
        let root = try? jsonObject(document.rawValue), let events = root["events"] as? [[String: Any]] else { return [] }
      return events.compactMap { event in
        guard let venue = event["venue"] as? [String: Any],
          string(venue["title"])?.localizedCaseInsensitiveCompare(adapterVenue) == .orderedSame,
          let titleObject = event["title"] as? [String: Any],
          let title = string(titleObject["headlinersText"]),
          let start = string(event["eventDateTimeISO"] ?? event["eventDateTime"]).flatMap(parseDate)
        else { return nil }
        let ticketing = event["ticketing"] as? [String: Any]
        let identity = string(event["eventId"])
        let performers = [string(titleObject["headlinersText"]), string(titleObject["supportingText"])].compactMap { $0 }
        return ExtractedListingFactory.make(source: source, sourceURL: sourceURL,
          identity: identity, title: title, performers: performers, room: string(venue["title"]),
          time: .performance(start), ticketURL: string(ticketing?["eventUrl"]) ?? string(ticketing?["url"]),
          onSaleDate: string(event["onsaleDateTime"]).flatMap(parseDate), status: .listed, rung: .adapter)
      }
    case .caveatJSON:
      guard let root = try? jsonObject(document.rawValue), let rows = root["records"] as? [[String: Any]] else { return [] }
      return rows.compactMap { row in
        guard let fields = row["fields"] as? [String: Any],
          let title = string(fields["Event"]),
          let start = string(fields["google_start_time"] ?? fields["Event start date and time"]).flatMap(parseDate)
        else { return nil }
        let identity = string(fields["MainRecordID"] ?? fields["record ID"])
        return ExtractedListingFactory.make(source: source, sourceURL: sourceURL,
          identity: identity, title: title, performers: [],
          room: "Caveat", time: .performance(start), ticketURL: string(fields["Ticket URL"]) ?? string(fields["Stellar URL"]),
          onSaleDate: nil, status: .listed, rung: .adapter)
      }
    case .eventbriteOrganizer:
      return eventbriteOrganizerListings(document, sourceURL: sourceURL, source: source)
    }
  }

  private static func mercuryListings(_ html: String, sourceURL: URL, source: SourceDescriptor) -> [ExtractedListing] {
    let sections = html.components(separatedBy: #"<div class="tw-img-container">"#).dropFirst()
    return sections.compactMap { section in
      guard let titleMatch = firstMatch(#"(?is)<div class="tw-name">.*?<a[^>]*>(.*?)</a>"#, in: section),
        let hrefMatch = firstMatch(#"(?is)<div class="tw-name">.*?<a[^>]*href="([^"]+)""#, in: section),
        let dateMatch = firstMatch(#"(?is)class="tw-event-date">([^<]+)"#, in: section),
        let timeMatch = firstMatch(#"(?is)class="tw-event-time">([^<]+)"#, in: section)
      else { return nil }
      let title = cleanHTML(titleMatch)
      let dateText = cleanHTML(dateMatch)
      let timeText = cleanHTML(timeMatch).replacingOccurrences(of: "Doors:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
      guard let date = parseMercuryDate(dateText, time: timeText) else { return nil }
      let identity = hrefMatch
      let performerLine = firstMatch(#"(?is)<div class="tw-attractions">(.*?)</div>"#, in: section).map(cleanHTML) ?? ""
      let status: ExtractedListing.Status = title.localizedCaseInsensitiveContains("sold out") ? .soldOut : .listed
      let normalizedTitle = title.replacingOccurrences(of: #"(?i)^\*?\s*sold out\s*\*?\s*"#, with: "", options: .regularExpression)
      return ExtractedListingFactory.make(source: source, sourceURL: sourceURL,
        identity: identity, title: normalizedTitle,
        performers: performerNames(in: performerLine), room: nil, time: .performance(date),
        ticketURL: identity, onSaleDate: nil, status: status, rung: .adapter)
    }
  }

  private static func modelListing(from row: [String: Any], sourceURL: URL, source: SourceDescriptor) -> ModelListingResult {
    guard let title = string(row["title"]) else { return .dropped(.missingTitle) }
    let time: ExtractedListing.Time
    if let startsAt = string(row["startsAt"]) {
      guard startsAt.contains("T") else {
        return .dropped(parseModelDate(startsAt) == nil ? .invalidDate : .dateOnlyStart)
      }
      guard let start = parseModelStart(startsAt) else { return .dropped(.invalidDate) }
      time = .performance(start)
    } else if let opens = string(row["opensAt"]).flatMap(parseModelDate),
      let closes = string(row["closesAt"]).flatMap(parseModelDate) {
      time = .run(opens: opens, closes: closes)
    } else { return .dropped(.invalidDate) }
    let status = ExtractedListing.Status(rawValue: string(row["status"]) ?? "listed") ?? .listed
    let eventURL = string(row["eventURL"])
    return .listing(ExtractedListingFactory.make(source: source, sourceURL: sourceURL,
      identity: eventURL ?? string(row["ticketURL"]), title: title,
      performers: row["performers"] as? [String] ?? [], room: string(row["room"]), time: time,
      ticketURL: string(row["ticketURL"]), onSaleDate: string(row["onSaleDate"]).flatMap(parseModelDate),
      status: status, rung: .model))
  }

  private static func normalizedVisibleText(_ text: String) -> String {
    let withoutHidden = text.replacingOccurrences(of: #"(?is)<(script|style|noscript)\b[^>]*>.*?</\1\s*>"#, with: " ", options: .regularExpression)
    let stripped = withoutHidden.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
    return normalize(decodeEntities(stripped))
  }

  private static func links(in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a\s*>"#) else { return "" }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
      guard let hrefRange = Range(match.range(at: 1), in: text), let labelRange = Range(match.range(at: 2), in: text) else { return nil }
      return "\(cleanHTML(String(text[labelRange]))) — \(String(text[hrefRange]))"
    }.joined(separator: "\n")
  }

  private static func parseMercuryDate(_ date: String, time: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "EEE MMM d, yyyy h:mm a"
    return formatter.date(from: "\(date) \(time)")
  }

  private static func parseDate(_ value: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }
    let local = DateFormatter()
    local.locale = Locale(identifier: "en_US_POSIX")
    local.timeZone = TimeZone(identifier: "America/New_York")
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
      local.dateFormat = format
      if let date = local.date(from: value) { return date }
    }
    return nil
  }

  private static func parseModelDate(_ value: String) -> Date? {
    let localValue = value.replacingOccurrences(
      of: #"(?:Z|[+-]\d{2}:?\d{2})$"#, with: "", options: .regularExpression
    )
    return parseDate(localValue)
  }

  private static func parseModelStart(_ value: String) -> Date? {
    guard value.contains("T") else { return nil }
    return parseModelDate(value)
  }

  private static func performerNames(in text: String) -> [String] {
    let separated = text.replacingOccurrences(
      of: #"(?i)\s+(?:with|w/|featuring|feat\.?|and)\s+"#,
      with: ",", options: .regularExpression
    )
    return separated.components(separatedBy: ",")
      .flatMap { $0.components(separatedBy: ",") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func names(_ value: Any?) -> [String] {
    if let name = string(value) { return [name] }
    if let object = value as? [String: Any], let name = string(object["name"]) { return [name] }
    return (value as? [[String: Any]] ?? []).compactMap { string($0["name"]) }
  }

  private static func string(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func jsonObject(_ value: String) throws -> [String: Any] {
    guard let data = value.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return object
  }

  private static func jsonObject(inModelResponse text: String) -> [String: Any]? {
    if let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      return value
    }
    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else { return nil }
    let fragment = String(text[start...end])
    guard let data = fragment.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func modelRows(from text: String) -> [[String: Any]]? {
    guard let object = jsonObject(inModelResponse: text) else { return nil }
    return object["listings"] as? [[String: Any]]
  }

  private static func cleanHTML(_ value: String) -> String {
    let stripped = value.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
    return normalize(decodeEntities(stripped))
  }

  private static func decodeEntities(_ value: String) -> String {
    let named = value.replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&#8217;", with: "’").replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
    guard let regex = try? NSRegularExpression(pattern: #"&#(?:([0-9]+)|[xX]([0-9a-fA-F]+));"#) else { return named }
    var decoded = named
    for match in regex.matches(in: named, range: NSRange(named.startIndex..., in: named)).reversed() {
      let decimalRange = Range(match.range(at: 1), in: named)
      let hexRange = Range(match.range(at: 2), in: named)
      let digits = decimalRange.map { String(named[$0]) } ?? hexRange.map { String(named[$0]) }
      let radix = decimalRange == nil ? 16 : 10
      guard let digits, let value = UInt32(digits, radix: radix), let scalar = UnicodeScalar(value),
        let range = Range(match.range, in: decoded) else { continue }
      decoded.replaceSubrange(range, with: String(scalar))
    }
    return decoded
  }

  private static func normalize(_ value: String) -> String {
    value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }

  private static func warnings(for result: (
    listings: [ExtractedListing], droppedExcludedHosts: Int, droppedMissingTitles: Int,
    droppedDateOnlyStarts: Int, droppedInvalidDates: Int, complete: Bool
  )) -> [String] {
    var warnings: [String] = []
    if result.droppedExcludedHosts > 0 { warnings.append("Dropped \(result.droppedExcludedHosts) listings on excluded hosts") }
    if result.droppedMissingTitles > 0 { warnings.append("Dropped \(result.droppedMissingTitles) model listings with no title") }
    if result.droppedDateOnlyStarts > 0 { warnings.append("Dropped \(result.droppedDateOnlyStarts) model listings with date-only starts") }
    if result.droppedInvalidDates > 0 { warnings.append("Dropped \(result.droppedInvalidDates) model listings with invalid dates or times") }
    return warnings
  }

  private static func matches(_ pattern: String, in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return regex.matches(in: value, range: range).compactMap { match in
      guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: value) else { return nil }
      return String(value[range])
    }
  }

  private static func firstMatch(_ pattern: String, in value: String) -> String? {
    matches(pattern, in: value).first
  }
}
