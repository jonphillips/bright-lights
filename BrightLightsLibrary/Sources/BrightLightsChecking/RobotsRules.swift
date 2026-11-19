import Foundation

public struct RobotsRules: Sendable, Equatable {
  public var disallowedPaths: [String]
  public var crawlDelay: TimeInterval?

  public init(text: String, userAgent: String = "BrightLights") {
    let lines = text.components(separatedBy: .newlines).map {
      $0.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    var groups: [[String]] = []
    var current: [String] = []
    var active = false
    for line in lines where !line.isEmpty {
      let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard parts.count == 2 else { continue }
      switch parts[0].lowercased() {
      case "user-agent":
        if active, !current.isEmpty { groups.append(current); current = [] }
        active = parts[1] == "*" || userAgent.localizedCaseInsensitiveContains(parts[1])
      case "disallow" where active && !parts[1].isEmpty:
        current.append(parts[1])
      case "crawl-delay" where active:
        if let delay = TimeInterval(parts[1]) { current.append("\u{0}delay:\(delay)") }
      default: break
      }
    }
    if !current.isEmpty { groups.append(current) }
    let directives = groups.flatMap { $0 }
    disallowedPaths = directives.filter { !$0.hasPrefix("\u{0}delay:") }
    crawlDelay = directives.compactMap { $0.hasPrefix("\u{0}delay:") ? TimeInterval($0.dropFirst(7)) : nil }.max()
  }

  public func allows(_ url: URL) -> Bool {
    let path = url.path.isEmpty ? "/" : url.path
    return !disallowedPaths.contains { path.hasPrefix($0) }
  }
}
