@testable import BrightLightsChecking
import BrightLightsSchema
import Foundation
import Testing

struct CheckReportTests {
  @Test func recordEncodesAllFieldsWithStableKeysAndNulls() throws {
    let source = Source(id: UUID(), householdID: UUID(), registryID: "venue", name: "Venue",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
      listingURL: "https://example.com", startPageURL: "https://example.com/start",
      flaggedAt: Date(timeIntervalSince1970: 1_900_000_000), flagNote: "Review this source",
      registeredHosts: "[]", cadence: "nightly")
    let report = SourceCheckReport(sourceID: source.id, outcome: .succeeded, listingCount: 2,
      pagesRead: 1, rungs: [.adapter], modelCalls: 0, note: nil, rowsWritten: 1,
      newListings: 1, changedListings: 0, markedMissing: 0, complete: true,
      unchanged: false, durationSeconds: 1.5)
    let record = CheckReportRecord(checkedAt: Date(timeIntervalSince1970: 1_900_000_000),
      trigger: .scheduled, build: "abc · clean · date", deviceName: "Mac mini", source: source, report: report)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(record)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasPrefix("{\"build\":"))
    #expect(text.contains("\"note\":null"))
    #expect(text.contains("\"flagged\":true"))
    #expect(text.contains("\"flagNote\":\"Review this source\""))
    #expect(text.contains("\"startPageURL\":\"https://example.com/start\""))
    #expect(try JSONDecoder().decode(CheckReportRecord.self, from: data) == record)
  }

  @Test func unchangedAndFailedReportsEncodeTheirOutcomesAndCounts() throws {
    let source = Source(id: UUID(), householdID: UUID(), registryID: "venue", name: "Venue",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
      listingURL: "https://example.com", registeredHosts: "[]", cadence: "nightly")
    let unchangedReport = SourceCheckReport(sourceID: source.id, outcome: .succeeded, listingCount: 2,
      pagesRead: 1, rungs: [.model], modelCalls: 0, note: "unchanged; model not called", rowsWritten: 0,
      newListings: 0, changedListings: 0, markedMissing: 0, complete: true,
      unchanged: true, durationSeconds: 0.25)
    let failedReport = SourceCheckReport(sourceID: source.id, outcome: .failed, listingCount: 0,
      pagesRead: 0, rungs: [], modelCalls: 0, note: "timeout", rowsWritten: 0,
      newListings: 0, changedListings: 0, markedMissing: 0, complete: false,
      unchanged: false, durationSeconds: 1.25)
    let checkedAt = Date(timeIntervalSince1970: 1_900_000_000)
    let unchanged = CheckReportRecord(checkedAt: checkedAt, trigger: .scheduled, build: "test",
      deviceName: "Test", source: source, report: unchangedReport)
    let failed = CheckReportRecord(checkedAt: checkedAt, trigger: .manual, build: "test",
      deviceName: "Test", source: source, report: failedReport)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let unchangedJSON = String(decoding: try encoder.encode(unchanged), as: UTF8.self)
    let failedJSON = String(decoding: try encoder.encode(failed), as: UTF8.self)
    #expect(unchangedJSON.contains("\"outcome\":\"unchanged\""))
    #expect(failedJSON.contains("\"outcome\":\"failed\""))
    #expect(failedJSON.contains("\"note\":\"timeout\""))
    #expect(failedJSON.contains("\"found\":0"))
    #expect(failedJSON.contains("\"new\":0"))
    #expect(failedJSON.contains("\"changed\":0"))
    #expect(failedJSON.contains("\"markedMissing\":0"))
    #expect(failedJSON.contains("\"complete\":false"))
  }

  @Test func writerAppendsMonthlyFilesAndPrunesOnlyThisDevicesOldFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let deviceID = UUID()
    let otherDeviceID = UUID()
    let source = Source(id: UUID(), householdID: UUID(), registryID: "venue", name: "Venue",
      type: "venue", priority: "core", area: "NYC", mode: .automated, method: "structured_html",
      listingURL: "https://example.com", registeredHosts: "[]", cadence: "nightly")
    let report = SourceCheckReport(sourceID: source.id, outcome: .succeeded, listingCount: 0,
      pagesRead: 1, rungs: [], modelCalls: 0, note: nil, rowsWritten: 0,
      newListings: 0, changedListings: 0, markedMissing: 0, complete: true,
      unchanged: false, durationSeconds: 0.1)
    func record(_ date: Date) -> CheckReportRecord {
      CheckReportRecord(checkedAt: date, trigger: .manual, build: "test", deviceName: "Test",
        source: source, report: report)
    }
    let current = date("2026-11-01")
    try CheckReportWriter.append([record(current)], date: current, deviceID: deviceID, container: root)
    try CheckReportWriter.append([record(current.addingTimeInterval(1))], date: current, deviceID: deviceID, container: root)
    let nextMonth = date("2026-10-01")
    try CheckReportWriter.append([record(nextMonth)], date: nextMonth, deviceID: deviceID, container: root)
    try CheckReportWriter.append([record(current)], date: current, deviceID: otherDeviceID, container: root)
    let directory = root.appendingPathComponent("CheckReports", isDirectory: true)
    let fileName = "2026-11.\(deviceID.uuidString.lowercased()).jsonl"
    let lines = try String(contentsOf: directory.appendingPathComponent(fileName), encoding: .utf8)
      .split(whereSeparator: \.isNewline)
    #expect(lines.count == 2)

    let oldOwn = directory.appendingPathComponent("2026-08.\(deviceID.uuidString.lowercased()).jsonl")
    let oldOther = directory.appendingPathComponent("2026-08.\(otherDeviceID.uuidString.lowercased()).jsonl")
    let retainedTwoMonths = directory.appendingPathComponent("2026-09.\(deviceID.uuidString.lowercased()).jsonl")
    try Data().write(to: oldOwn)
    try Data().write(to: oldOther)
    try Data().write(to: retainedTwoMonths)
    try CheckReportWriter.append([record(current)], date: current, deviceID: deviceID, container: root)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("2026-10.\(deviceID.uuidString.lowercased()).jsonl").path))
    #expect(FileManager.default.fileExists(atPath: retainedTwoMonths.path))
    #expect(!FileManager.default.fileExists(atPath: oldOwn.path))
    #expect(FileManager.default.fileExists(atPath: oldOther.path))

    let file = directory.appendingPathComponent(fileName)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    #expect(throws: (any Error).self) {
      try CheckReportWriter.append([record(current.addingTimeInterval(2))], date: current,
        deviceID: deviceID, container: root)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let retainedLines = try String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline)
    #expect(retainedLines.count == 3)
  }

  private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)!
  }
}
