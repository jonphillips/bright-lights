import BrightLightsSchema
import Foundation

public struct RoundsProjection: Sendable, Equatable {
  public enum Group: Sendable, Equatable {
    case due([Source])
    case notReadingAutomatically([Source])
    case upToDate([Source])
  }

  public var due: [Source]
  public var notReadingAutomatically: [Source]
  public var upToDate: [Source]
  public var badgeCount: Int { due.count + notReadingAutomatically.count }

  public init(sources: [Source], stays: [Stay], now: Date) {
    let active = sources.filter { $0.retiredAt == nil }
    due = active.filter { source in
      guard source.mode == .manual else { return false }
      guard let checkedAt = source.lastCheckedAt else { return true }
      return now.timeIntervalSince(checkedAt) > SourceCadence.interval(for: source, at: now, stays: stays)
    }.sorted {
      switch ($0.lastCheckedAt, $1.lastCheckedAt) {
      case (nil, nil): $0.name.localizedStandardCompare($1.name) == .orderedAscending
      case (nil, _): true
      case (_, nil): false
      case let (lhs?, rhs?): lhs == rhs
        ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
      }
    }
    notReadingAutomatically = active.filter { $0.mode == .automated && $0.needsManualLook }
      .sorted {
        $0.consecutiveFailures == $1.consecutiveFailures
          ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
          : $0.consecutiveFailures > $1.consecutiveFailures
      }
    let dueIDs = Set(due.map(\.id))
    upToDate = active.filter { $0.mode == .manual && !dueIDs.contains($0.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
