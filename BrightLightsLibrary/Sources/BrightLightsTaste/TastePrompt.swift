import Foundation
import BrightLightsSchema
import LLMClientKit

public struct TastePrompt: Sendable {
  public struct Batch: Sendable {
    public let request: ModelRequest
    public let rowIDs: [UUID]
  }

  public struct Suggestion: Equatable, Sendable {
    public let verdict: TasteSuggestion
    public let reason: String?

    public init(verdict: TasteSuggestion, reason: String?) {
      self.verdict = verdict
      self.reason = reason
    }
  }

  public struct Agreement: Equatable, Sendable {
    public let suggestedKeep: Int
    public let kept: Int
    public let suggestedClear: Int
    public let clearedOrPassed: Int
    public let unsure: Int
  }

  public static func agreement(records: [TasteRecord], since date: Date) -> Agreement {
    let recent = records.filter { $0.firstDecidedAt >= date }
    let keeps = recent.filter { $0.suggestion == .keep }
    let clears = recent.filter { $0.suggestion == .clear }
    return Agreement(
      suggestedKeep: keeps.count,
      kept: keeps.filter { $0.kind.isPicked }.count,
      suggestedClear: clears.count,
      clearedOrPassed: clears.filter { $0.kind == .cleared || $0.kind == .pass }.count,
      unsure: recent.filter { $0.suggestion == .unsure }.count
    )
  }

  private struct PromptRow: Encodable {
    let index: Int
    let title: String
    let performers: [String]
    let room: String?
    let date: String
    let source: String
    let evidence: [String]
  }

  private struct PromptExample: Encodable {
    let decision: String
    let title: String
    let performers: [String]
    let room: String?
    let note: String?
    let source: String
  }

  private struct PromptNote: Encodable {
    let author: String
    let subject: String?
    let text: String
  }

  private struct Payload: Encodable {
    let notes: [PromptNote]
    let notesOmitted: String?
    let examples: [PromptExample]
    let rows: [PromptRow]
  }

  public static func batches(
    listings: [Listing], source: Source, records: [TasteRecord], notes: [TasteNote],
    people: [Person], counts: TasteCounts
  ) -> [Batch] {
    let sortedNotes = notes.sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    let includedNotes = sortedNotes.prefix(80).map { note in
      PromptNote(
        author: people.first(where: { $0.id == note.authorID })?.displayName.nonEmpty ?? "Someone",
        subject: note.subject, text: note.body
      )
    }
    return listings.chunked(into: 40).map { group in
      let rows = group.enumerated().map { offset, listing in
        PromptRow(
          index: offset + 1, title: listing.title,
          performers: TasteCounts.performerNames(listing.performers), room: listing.room,
          date: listing.startsAt.formatted(date: .abbreviated, time: .shortened),
          source: source.name,
          evidence: counts.result(for: listing, sourceRegistryID: source.registryID).evidence.map { [$0.line] } ?? []
        )
      }
      let exampleRecords = examples(for: group, source: source, records: records)
      let examples = exampleRecords.map { record in
        PromptExample(
          decision: record.kind.title, title: record.title,
          performers: TasteCounts.performerNames(record.performers), room: record.room,
          note: record.note, source: record.sourceName
        )
      }
      let payload = Payload(
        notes: Array(includedNotes),
        notesOmitted: sortedNotes.count > 80 ? "\(sortedNotes.count - 80) more not shown" : nil,
        examples: examples, rows: rows
      )
      let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
      let prompt = String(decoding: data, as: UTF8.self)
      let request = ModelRequest(
        tier: .frontierPreferred,
        system: """
        You suggest whether each event fits the household's taste. Never decide for the people. Use the notes and examples as evidence. If notesOmitted is present, mention how many notes were left out. Return one verdict per row: keep, clear, or unsure. Give a reason of about 12 words or fewer that names an example or note. When there is no basis, use unsure. The row index must match the input.
        """,
        prompt: prompt, maxTokens: 1800,
        responseFormat: .jsonSchema(name: "taste_suggestions", schema: Self.schema)
      )
      return Batch(request: request, rowIDs: group.map(\.id))
    }
  }

  public static func parse(_ text: String, rowIDs: [UUID]) -> [UUID: Suggestion] {
    var result = Dictionary(uniqueKeysWithValues: rowIDs.map {
      ($0, Suggestion(verdict: .unsure, reason: nil))
    })
    guard let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = object["suggestions"] as? [[String: Any]] else { return result }
    for row in rows {
      guard let index = row["index"] as? Int, rowIDs.indices.contains(index - 1),
        let rawVerdict = row["verdict"] as? String,
        let verdict = TasteSuggestion(rawValue: rawVerdict) else { continue }
      let reason = (row["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      result[rowIDs[index - 1]] = Suggestion(verdict: verdict, reason: reason.map { String($0.prefix(120)) })
    }
    return result
  }

  private static let schema: JSONValue = [
    "type": "object",
    "properties": [
      "suggestions": [
        "type": "array",
        "items": [
          "type": "object",
          "properties": [
            "index": ["type": "integer"],
            "verdict": ["type": "string", "enum": ["keep", "clear", "unsure"]],
            "reason": ["type": "string"]
          ],
          "required": ["index", "verdict", "reason"],
          "additionalProperties": .bool(false)
        ]
      ]
    ],
    "required": ["suggestions"],
    "additionalProperties": .bool(false)
  ]

  private static func examples(for listings: [Listing], source: Source, records: [TasteRecord]) -> [TasteRecord] {
    func keys(for record: TasteRecord) -> Set<String> {
      var result: Set<String> = ["show:\(record.sourceRegistryID):\(TasteCounts.normalized(record.title))"]
      if let room = record.room, !room.isEmpty {
        result.insert("room:\(record.sourceRegistryID):\(TasteCounts.normalized(room))")
      }
      for performer in TasteCounts.performerNames(record.performers) {
        let normalized = TasteCounts.normalized(performer)
        if !normalized.isEmpty { result.insert("performer:\(normalized)") }
      }
      return result
    }
    let frequencies = records.reduce(into: [String: Int]()) { counts, record in
      for key in keys(for: record) { counts[key, default: 0] += 1 }
    }
    let rowKeys = listings.reduce(into: Set<String>()) { result, listing in
      var row = ["show:\(source.registryID):\(TasteCounts.normalized(listing.title))"]
      if let room = listing.room, !room.isEmpty {
        row.append("room:\(source.registryID):\(TasteCounts.normalized(room))")
      }
      row += TasteCounts.performerNames(listing.performers).map { "performer:\(TasteCounts.normalized($0))" }
      result.formUnion(row)
    }
    func matchCount(_ record: TasteRecord) -> Int {
      keys(for: record).intersection(rowKeys).map { frequencies[$0, default: 0] }.max() ?? 0
    }
    let eligible = records.filter { $0.kind.isPicked || ($0.kind == .pass && $0.note?.isEmpty == false) }
    let shared = eligible.filter { matchCount($0) > 0 }.sorted {
      if matchCount($0) != matchCount($1) { return matchCount($0) > matchCount($1) }
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    let remaining = eligible.filter { matchCount($0) == 0 }.sorted {
      if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    return Array((shared + remaining).prefix(40))
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}

private extension Collection {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [] }
    return stride(from: 0, to: count, by: size).map { start in
      Array(self.dropFirst(start).prefix(size))
    }
  }
}
