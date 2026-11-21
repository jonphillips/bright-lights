import Dependencies
import Foundation
import BrightLightsSchema

public enum CheckReportTrigger: String, Codable, Sendable {
  case scheduled
  case manual
}

public struct CheckReportRecord: Codable, Equatable, Sendable {
  public var version: Int
  public var checkedAt: String
  public var trigger: CheckReportTrigger
  public var build: String
  public var deviceName: String
  public var registryID: String
  public var name: String
  public var outcome: String
  public var note: String?
  public var found: Int
  public var new: Int
  public var changed: Int
  public var markedMissing: Int
  public var complete: Bool
  public var rungs: [String]
  public var pagesRead: Int
  public var modelCalls: Int
  public var durationSeconds: Double
  public var flagged: Bool
  public var flagNote: String?
  public var startPageURL: String?

  private enum CodingKeys: String, CodingKey {
    case version, checkedAt, trigger, build, deviceName, registryID, name, outcome, note, found, new, changed
    case markedMissing, complete, rungs, pagesRead, modelCalls, durationSeconds, flagged, flagNote, startPageURL
  }

  public init(checkedAt: Date, trigger: CheckReportTrigger, build: String, deviceName: String,
    source: Source, report: SourceCheckReport) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    self.version = 1
    self.checkedAt = formatter.string(from: checkedAt)
    self.trigger = trigger
    self.build = build
    self.deviceName = deviceName
    self.registryID = source.registryID
    self.name = source.name
    self.outcome = report.unchanged ? "unchanged" : report.outcome.rawValue
    self.note = report.note
    self.found = report.listingCount
    self.new = report.newListings
    self.changed = report.changedListings
    self.markedMissing = report.markedMissing
    self.complete = report.complete
    self.rungs = report.rungs.map(\.rawValue).sorted()
    self.pagesRead = report.pagesRead
    self.modelCalls = report.modelCalls
    self.durationSeconds = report.durationSeconds
    self.flagged = source.flaggedAt != nil
    self.flagNote = source.flagNote
    self.startPageURL = source.startPageURL
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(checkedAt, forKey: .checkedAt)
    try container.encode(trigger, forKey: .trigger)
    try container.encode(build, forKey: .build)
    try container.encode(deviceName, forKey: .deviceName)
    try container.encode(registryID, forKey: .registryID)
    try container.encode(name, forKey: .name)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(note, forKey: .note)
    try container.encode(found, forKey: .found)
    try container.encode(new, forKey: .new)
    try container.encode(changed, forKey: .changed)
    try container.encode(markedMissing, forKey: .markedMissing)
    try container.encode(complete, forKey: .complete)
    try container.encode(rungs, forKey: .rungs)
    try container.encode(pagesRead, forKey: .pagesRead)
    try container.encode(modelCalls, forKey: .modelCalls)
    try container.encode(durationSeconds, forKey: .durationSeconds)
    try container.encode(flagged, forKey: .flagged)
    try container.encode(flagNote, forKey: .flagNote)
    try container.encode(startPageURL, forKey: .startPageURL)
  }
}

public struct CheckReportClient: Sendable {
  public var append: @Sendable ([CheckReportRecord], Date, UUID) async throws -> Void

  public init(append: @escaping @Sendable ([CheckReportRecord], Date, UUID) async throws -> Void) {
    self.append = append
  }

  public static let live = CheckReportClient { records, date, deviceID in
    try await Task.detached(priority: .utility) {
      guard let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jonphillips.BrightLights") else {
        throw CheckReportError.containerUnavailable
      }
      try CheckReportWriter.append(records, date: date, deviceID: deviceID, container: container)
    }.value
  }

  public static let testValue = CheckReportClient { records, date, deviceID in
    let container = FileManager.default.temporaryDirectory.appendingPathComponent("BrightLightsCheckReports", isDirectory: true)
    try CheckReportWriter.append(records, date: date, deviceID: deviceID, container: container)
  }
}

enum CheckReportWriter {
  static func append(_ records: [CheckReportRecord], date: Date, deviceID: UUID, container: URL) throws {
    let directory = container.appendingPathComponent("CheckReports", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let month = monthName(date)
    let file = directory.appendingPathComponent("\(month).\(deviceID.uuidString.lowercased()).jsonl")
    var lines = Data()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    for record in records {
      lines.append(try encoder.encode(record))
      lines.append(0x0A)
    }

    var coordinationError: NSError?
    var writeError: Error?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { coordinatedURL in
      do {
        let existing = (try? Data(contentsOf: coordinatedURL)) ?? Data()
        var combined = existing
        combined.append(lines)
        try combined.write(to: coordinatedURL, options: .atomic)
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
    try prune(directory: directory, currentMonth: month, deviceID: deviceID)
  }

  private static func monthName(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: date)
  }

  private static func prune(directory: URL, currentMonth: String, deviceID: UUID) throws {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM"
    guard let currentDate = formatter.date(from: currentMonth),
      let cutoff = Calendar(identifier: .gregorian).date(byAdding: .month, value: -2, to: currentDate) else { return }
    let prefix = ".\(deviceID.uuidString.lowercased()).jsonl"
    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where url.lastPathComponent.hasSuffix(prefix) {
      let month = String(url.lastPathComponent.dropLast(prefix.count))
      if let date = formatter.date(from: month), date < cutoff { try FileManager.default.removeItem(at: url) }
    }
  }
}

public enum CheckReportError: Error, LocalizedError {
  case containerUnavailable

  public var errorDescription: String? { "Bright Lights iCloud container is unavailable" }
}

extension CheckReportClient: DependencyKey {
  public static let liveValue = CheckReportClient.live
}

extension DependencyValues {
  public var checkReportClient: CheckReportClient {
    get { self[CheckReportClient.self] }
    set { self[CheckReportClient.self] = newValue }
  }
}
