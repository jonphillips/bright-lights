import Foundation
import BrightLightsTaste

enum ListingDisplay {
  private static let newYorkTimeZone = TimeZone(identifier: "America/New_York")!
  private static let newYorkDateTimeStyle = Date.FormatStyle(
    date: .complete, time: .shortened, timeZone: newYorkTimeZone
  )

  static func newYorkDateTime(_ date: Date) -> String {
    let value = date.formatted(newYorkDateTimeStyle)
    return TimeZone.current.identifier == "America/New_York" ? value : value + " ET"
  }

  static func performerNames(_ json: String) -> String {
    TasteCounts.performerNames(json).joined(separator: ", ")
  }
}
