import BrightLightsSchema
import Foundation

public enum SourceCadence {
  // These thresholds are the explicit M1 S3 cadence rules, including the 20-hour slack.
  public static let nightlyInterval: TimeInterval = 20 * 60 * 60
  public static let weeklyInterval: TimeInterval = 6 * 24 * 60 * 60 + 20 * 60 * 60
  private static let stayLeadDays = -2 // M1 S3 starts nightly cadence two days before arrival.
  private static let openDepartureDays = 7 // M1 S3's proxy for an open-ended one-week stay.

  public static func isDue(_ source: Source, at now: Date, stays: [Stay]) -> Bool {
    guard source.mode == .automated, source.retiredAt == nil else { return false }
    guard let lastCheckedAt = source.lastCheckedAt else { return true }
    let duringStay = stays.contains { stay in
      let arrival = Calendar(identifier: .gregorian).date(byAdding: .day, value: stayLeadDays, to: stay.arrivesOn) ?? stay.arrivesOn
      let departure = stay.departsOn ?? Calendar(identifier: .gregorian).date(byAdding: .day, value: openDepartureDays, to: stay.arrivesOn) ?? stay.arrivesOn
      return now >= arrival && now <= departure
    }
    let interval = duringStay || source.cadence == "nightly" ? nightlyInterval : weeklyInterval
    return now.timeIntervalSince(lastCheckedAt) > interval
  }

  public static func orderedDue(_ sources: [Source], at now: Date, stays: [Stay]) -> [Source] {
    sources.filter { isDue($0, at: now, stays: stays) }.sorted {
      ($0.lastCheckedAt ?? .distantPast) < ($1.lastCheckedAt ?? .distantPast)
    }
  }
}
