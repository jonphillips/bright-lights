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
    return now.timeIntervalSince(lastCheckedAt) > interval(for: source, at: now, stays: stays)
  }

  public static func interval(for source: Source, at now: Date, stays: [Stay]) -> TimeInterval {
    let duringStay = stays.contains { stay in
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "America/New_York")!
      let arrivalDay = calendar.startOfDay(for: stay.arrivesOn)
      let departureDay = calendar.startOfDay(for: stay.departsOn
        ?? calendar.date(byAdding: .day, value: openDepartureDays, to: arrivalDay) ?? arrivalDay)
      let start = calendar.date(byAdding: .day, value: stayLeadDays, to: arrivalDay) ?? arrivalDay
      let end = calendar.date(byAdding: .day, value: 1, to: departureDay) ?? departureDay
      return now >= start && now < end
    }
    return duringStay || source.cadence == "nightly" ? nightlyInterval : weeklyInterval
  }

  public static func orderedDue(_ sources: [Source], at now: Date, stays: [Stay]) -> [Source] {
    sources.filter { isDue($0, at: now, stays: stays) }.sorted {
      ($0.lastCheckedAt ?? .distantPast) < ($1.lastCheckedAt ?? .distantPast)
    }
  }
}
