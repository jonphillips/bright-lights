import Dependencies
import Foundation
import LLMClientKit
import Testing
@testable import BrightLightsExtraction

@Suite struct ExtractionEngineTests {
  private let sourceURL = URL(string: "https://example.com/events")!

  @Test("JSON-LD fixtures extract through the first rung")
  func jsonLD() async throws {
    let cases: [(String, String, Int, String, String, String, String, String, String)] = [
      ("bell-house.json", "bell-house", 5, "Duncan Trussell", "2026-11-19T00:30:00Z",
       "https://www.ticketmaster.com/duncan-trussell-brooklyn-new-york-11-18-2026/event/300063701DCE9DB2",
       "The George Lucas Talk Show", "2026-12-20T00:00:00Z",
       "https://www.ticketmaster.com/the-george-lucas-talk-show-brooklyn-new-york-12-19-2026/event/3000653B4011B32C"),
      ("ny-comedy-club.json", "ny-comedy-club", 21,
       "The Boy Friends ft: Jason Salmon, Keegan Tindall, Matt Lopes, Corey B, Alaina Hirschi, Myq Kaplan, Marcus Monroe",
       "2026-11-19T00:00:00Z",
       "https://newyorkcomedyclub.com/events/the-boy-friends-ft-jason-salmon-keegan-tindall-matt-lopes-corey-b-alaina-hirschi-myq-kaplan-marcus-monroe",
       "Jack Grady (Comedy Magic Show)", "2026-11-21T03:45:00Z",
       "https://newyorkcomedyclub.com/events/jack-grady-comedy")
    ]
    for (fixture, sourceID, count, firstTitle, firstStart, firstKey, lastTitle, lastStart, lastKey) in cases {
      let text = try fixtureText(fixture)
      let result = try await ExtractionEngine().extract(.json(text), sourceURL: sourceURL,
        source: .init(id: sourceID))
      #expect(result.listings.count == count)
      #expect(result.listings.first?.title == firstTitle)
      #expect(startISO(result.listings.first?.time) == firstStart)
      #expect(result.listings.first?.stableKey == "\(sourceID):\(firstKey)")
      #expect(result.listings.last?.title == lastTitle)
      #expect(startISO(result.listings.last?.time) == lastStart)
      #expect(result.listings.last?.stableKey == "\(sourceID):\(lastKey)")
      #expect(result.listings.allSatisfy { $0.rung == .jsonLD })
    }
  }

  @Test("adapters map the sampled source fixtures")
  func adapters() async throws {
    let cases: [(String, SourceDescriptor.Adapter, String, Int, String, String, String, String, String, String)] = [
      ("bowery-ballroom.html", .mercuryEast, "bowery-ballroom", 20, "Liana Flores", "2026-11-19T00:00:00Z",
       "https://mercuryeastpresents.com/tm-event/liana-flores", "Wild Pink", "2026-12-13T00:00:00Z",
       "https://mercuryeastpresents.com/tm-event/wild-pink"),
      ("brooklyn-steel.json", .aegAXS, "brooklyn-steel", 4, "The Music of Hey Arnold! Live!", "2027-01-17T01:00:00Z",
       "1706806", "Whitney", "2027-06-19T00:00:00Z", "1694427"),
      ("caveat.json", .caveatJSON, "caveat", 4, "Pitch Roast Live", "2026-11-19T00:00:00Z",
       "recL9b8lSSWVpFEBP", "The Power Joker: A Robert Moses Comedy Show", "2027-03-27T23:00:00Z",
       "rectT5FeZKkL6lsWM")
    ]
    for (fixture, adapter, sourceID, count, firstTitle, firstStart, firstKey, lastTitle, lastStart, lastKey) in cases {
      let value = try fixtureText(fixture)
      let document: PageDocument = fixture.hasSuffix(".html") ? .html(value) : .json(value)
      let result = try await ExtractionEngine().extract(document, sourceURL: sourceURL,
        source: .init(id: sourceID, adapter: adapter,
          adapterVenue: adapter == .aegAXS ? "Brooklyn Steel" : nil))
      #expect(result.listings.count == count)
      #expect(result.listings.first?.title == firstTitle)
      #expect(startISO(result.listings.first?.time) == firstStart)
      #expect(result.listings.first?.stableKey == "\(sourceID):\(firstKey)")
      #expect(result.listings.last?.title == lastTitle)
      #expect(startISO(result.listings.last?.time) == lastStart)
      #expect(result.listings.last?.stableKey == "\(sourceID):\(lastKey)")
      #expect(result.listings.allSatisfy { $0.rung == .adapter })
    }
  }

  @Test("model rung maps recorded structured output, NYC time and multi-day runs")
  func modelMapping() async throws {
    let output = #"{"listings":[{"title":"The Stand: Jane Doe","performers":["Jane Doe"],"room":"The Stand","startsAt":"2026-12-04T20:00:00Z","opensAt":"2026-12-04T19:00:00","closesAt":"2026-12-04T21:00:00","eventURL":"https://thestandnyc.com/show/jane-doe","ticketURL":"https://tickets.example/jane-doe","onSaleDate":"2026-11-20T10:00:00","status":"listed"},{"title":"Winter Repertory","performers":[],"room":"The Stand","startsAt":"","opensAt":"2026-12-01","closesAt":"2026-12-20","eventURL":"","ticketURL":"","onSaleDate":"","status":"listed"},{"title":"Wrong source","performers":[],"room":"Other room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"https://thestandwest.com/show/wrong","ticketURL":"","onSaleDate":"","status":"listed"},{"title":"Wrong subdomain","performers":[],"room":"Other room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"https://events.thestandwest.com/show/wrong","ticketURL":"","onSaleDate":"","status":"listed"}]}"#
    let result = try await withDependencies {
      $0.modelClient = StubModelClient.constant(output)
    } operation: {
      try await ExtractionEngine().extract(.html(try fixtureText("the-stand.html")), sourceURL: sourceURL,
        source: .init(id: "the-stand", excludedHosts: ["thestandwest.com"]))
    }
    #expect(result.listings.count == 2)
    #expect(result.listings[0].rung == .model)
    #expect(result.listings[0].stableKey == "the-stand:https://thestandnyc.com/show/jane-doe")
    #expect(result.warnings.contains("Dropped 2 listings on excluded hosts"))
    #expect(startISO(result.listings[0].time) == "2026-12-05T01:00:00Z")
    #expect(result.listings[0].performers == ["Jane Doe"])
    if case let .run(opens, closes) = result.listings[1].time {
      #expect(iso(opens) == "2026-12-01T05:00:00Z")
      #expect(iso(closes) == "2026-12-20T05:00:00Z")
    } else {
      Issue.record("Expected a run with opening and closing dates")
    }
  }

  @Test("the deterministic ladder stops before the model")
  func ladder() async throws {
    let model = StubModelClient.constant(#"{"listings":[]}"#)
    let jsonLD = #"[{"@type":"Event","name":"Example","startDate":"2026-12-04T20:00:00-05:00","url":"https://example.com/event"}]"#
    let result = try await withDependencies { $0.modelClient = model } operation: {
      try await ExtractionEngine().extract(.json(jsonLD), sourceURL: sourceURL,
        source: .init(id: "example"))
    }
    #expect(result.listings.count == 1)
    #expect(result.listings[0].rung == .jsonLD)

    let html = "<script type=\"application/ld+json\">\(jsonLD.dropFirst().dropLast())</script>" + (try fixtureText("bowery-ballroom.html"))
    let adapterResult = try await ExtractionEngine().extract(.html(html), sourceURL: sourceURL,
      source: .init(id: "bowery-ballroom", adapter: .mercuryEast))
    #expect(adapterResult.listings.count == 20)
    #expect(adapterResult.listings.allSatisfy { $0.rung == .adapter })
  }

  @Test("JSON-LD same-day end times and offer arrays map without losing ticket data")
  func sameDayEndAndOfferArray() async throws {
    let event = #"{"@type":"Event","name":"Late Set","startDate":"2026-12-04T20:00:00-05:00","endDate":"2026-12-04T22:00:00-05:00","url":"https://example.com/late-set","offers":[{"availability":"https://schema.org/InStock"},{"url":"https://tickets.example/late-set","validFrom":"2026-11-20T10:00:00-05:00","availability":"https://schema.org/SoldOut"}]}"#
    let result = try await ExtractionEngine().extract(.json("[\(event),\(event)]"), sourceURL: sourceURL,
      source: .init(id: "sample"))
    #expect(result.listings.count == 1)
    #expect(result.listings[0].stableKey == "sample:https://example.com/late-set")
    #expect(result.listings[0].ticketURL?.absoluteString == "https://tickets.example/late-set")
    #expect(result.listings[0].status == .soldOut)
    #expect(result.listings[0].onSaleDate != nil)
    #expect(startISO(result.listings[0].time) == "2026-12-05T01:00:00Z")
  }

  @Test("duplicate adapter and model keys are deduplicated in source namespaces")
  func adapterAndModelDeduplication() async throws {
    let caveat = #"{"records":[{"fields":{"Event":"Same show","google_start_time":"2026-12-04T20:00:00-05:00","MainRecordID":"shared-id"}},{"fields":{"Event":"Same show","google_start_time":"2026-12-04T20:00:00-05:00","MainRecordID":"shared-id"}}]}"#
    let adapterResult = try await ExtractionEngine().extract(.json(caveat), sourceURL: sourceURL,
      source: .init(id: "caveat-source", adapter: .caveatJSON))
    #expect(adapterResult.listings.count == 1)
    #expect(adapterResult.listings[0].stableKey == "caveat-source:shared-id")

    let duplicate = #"{"listings":[{"title":"Same show","performers":[],"room":"Room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"https://example.com/same","ticketURL":"","onSaleDate":"","status":"listed"},{"title":"Same show","performers":[],"room":"Room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"https://example.com/same","ticketURL":"","onSaleDate":"","status":"listed"}]}"#
    let modelResult = try await withDependencies {
      $0.modelClient = StubModelClient.constant(duplicate)
    } operation: {
      try await ExtractionEngine().extract(.html("<main>Same show</main>"), sourceURL: sourceURL,
        source: .init(id: "model-source"))
    }
    #expect(modelResult.listings.count == 1)
    #expect(modelResult.listings[0].stableKey == "model-source:https://example.com/same")
  }

  @Test("malformed JSON warns and continues to the model")
  func malformedJSONFallsThrough() async throws {
    let output = #"{"listings":[{"title":"Recovered","performers":[],"room":"Room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"","ticketURL":"","onSaleDate":"","status":"listed"}]}"#
    let result = try await withDependencies {
      $0.modelClient = StubModelClient.constant(output)
    } operation: {
      try await ExtractionEngine().extract(.json("{ malformed"), sourceURL: sourceURL,
        source: .init(id: "malformed", adapter: .caveatJSON))
    }
    #expect(result.listings.count == 1)
    #expect(result.listings[0].rung == .model)
    #expect(result.warnings.contains("JSON-LD parsing failed; continuing to the next rung."))
  }

  @Test("model performance requires a complete local start time")
  func modelRejectsDateOnlyPerformance() async throws {
    let output = #"{"listings":[{"title":"Missing time","performers":[],"room":"Room","startsAt":"2026-12-04","opensAt":"","closesAt":"","eventURL":"","ticketURL":"","onSaleDate":"","status":"listed"}]}"#
    let result = try await withDependencies {
      $0.modelClient = StubModelClient.constant(output)
    } operation: {
      try await ExtractionEngine().extract(.html("<main>Missing time</main>"), sourceURL: sourceURL,
        source: .init(id: "missing-time"))
    }
    #expect(result.listings.isEmpty)
    #expect(result.warnings.contains("Dropped 1 model listings with date-only starts"))
  }

  @Test("model rows with no title and invalid times have separate counts")
  func modelDropCounts() async throws {
    let output = #"{"listings":[{"title":"","performers":[],"room":"Room","startsAt":"2026-12-04T20:00:00","opensAt":"","closesAt":"","eventURL":"","ticketURL":"","onSaleDate":"","status":"listed"},{"title":"Invalid date","performers":[],"room":"Room","startsAt":"not a date","opensAt":"","closesAt":"","eventURL":"","ticketURL":"","onSaleDate":"","status":"listed"}] }"#
    let result = try await withDependencies {
      $0.modelClient = StubModelClient.constant(output)
    } operation: {
      try await ExtractionEngine().extract(.html("<main>Shows</main>"), sourceURL: sourceURL,
        source: .init(id: "drop-counts"))
    }
    #expect(result.warnings.contains("Dropped 1 model listings with no title"))
    #expect(result.warnings.contains("Dropped 1 model listings with invalid dates or times"))
  }

  @Test("URL identity canonicalizes host, doubled and trailing slashes, and fragments")
  func canonicalURLIdentity() async throws {
    let events = #"[{"@type":"Event","name":"The Stand Show","startDate":"2026-12-04T20:00:00-05:00","url":"https://TheStandNYC.com//shows/show/14184/performer/#tickets"},{"@type":"Event","name":"The Stand Show","startDate":"2026-12-04T20:00:00-05:00","url":"https://thestandnyc.com/shows/show/14184/performer"}]"#
    let result = try await ExtractionEngine().extract(.json(events), sourceURL: sourceURL,
      source: .init(id: "the-stand"))
    #expect(result.listings.count == 1)
    #expect(result.listings[0].stableKey == "the-stand:https://thestandnyc.com/shows/show/14184/performer")
  }

  @Test("numeric HTML entities are decoded in adapter titles")
  func numericEntityDecoding() async throws {
    let html = try fixtureText("bowery-ballroom.html")
      .replacingOccurrences(of: ">Liana Flores</a>", with: ">&amp;#8220;Liana&amp;#038; Flores&amp;#8221;</a>")
    let result = try await ExtractionEngine().extract(.html(html), sourceURL: sourceURL,
      source: .init(id: "bowery-ballroom", adapter: .mercuryEast))
    #expect(result.listings.first?.title == "“Liana& Flores”")
  }

  @Test("visible-text hashing ignores whitespace and script changes")
  func stablePageHash() {
    let first = PageDocument.html("<main>Tonight <b>at Caveat</b></main><script>old()</script>")
    let second = PageDocument.html("<main> Tonight\n<b> at Caveat </b> </main><script>new()</script>")
    #expect(ExtractionEngine.pageHash(for: first) == ExtractionEngine.pageHash(for: second))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["BRIGHT_LIGHTS_LIVE_MODEL_TEST"] == "1"))
  func liveModelAgainstStandFixture() async throws {
    let result = try await withDependencies {
      $0.modelClient = TieredModelClient.live
    } operation: {
      try await ExtractionEngine().extract(.html(try fixtureText("the-stand.html")),
        sourceURL: URL(string: "https://thestandnyc.com/shows")!,
        source: .init(id: "the-stand", excludedHosts: ["thestandwest.com"]))
    }
    print("Live model extracted \(result.listings.count) listings; warnings: \(result.warnings)")
    for listing in result.listings {
      print("- \(listing.title) | \(listing.room ?? "") | \(startISO(listing.time) ?? "run") | \(listing.stableKey)")
    }
    #expect(!result.listings.isEmpty)
  }

  private func fixtureText(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func startISO(_ time: ExtractedListing.Time?) -> String? {
    guard case let .performance(date) = time else { return nil }
    return iso(date)
  }

  private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
