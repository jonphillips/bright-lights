import Foundation

public struct RobotsRules: Sendable, Equatable {
  public var disallowedPaths: [String]
  public var crawlDelay: TimeInterval?

  public init(text: String, userAgent: String = "BrightLights") {
    let lines = text.components(separatedBy: .newlines).map {
      $0.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    var agents: [String] = []
    var directives: [String] = []
    var matchingDirectives: [String] = []
    var matchingDelays: [TimeInterval] = []

    func matches(_ agents: [String]) -> Bool {
      agents.contains { agent in
        agent == "*" || userAgent.localizedCaseInsensitiveContains(agent)
      }
    }

    func finishGroup() {
      guard !agents.isEmpty else { return }
      if matches(agents) {
        for directive in directives {
          if directive.hasPrefix("\u{0}delay:") {
            if let delay = TimeInterval(directive.dropFirst(7)) { matchingDelays.append(delay) }
          } else {
            matchingDirectives.append(directive)
          }
        }
      }
      agents = []
      directives = []
    }

    for line in lines where !line.isEmpty {
      let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard parts.count == 2 else { continue }
      switch parts[0].lowercased() {
      case "user-agent":
        if !directives.isEmpty { finishGroup() }
        agents.append(parts[1])
      case "disallow" where !parts[1].isEmpty:
        directives.append(parts[1])
      case "crawl-delay":
        if let delay = TimeInterval(parts[1]) { directives.append("\u{0}delay:\(delay)") }
      default: break
      }
    }
    finishGroup()
    disallowedPaths = matchingDirectives
    crawlDelay = matchingDelays.max()
  }

  public func allows(_ url: URL) -> Bool {
    let path = url.path.isEmpty ? "/" : url.path
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery.map { "?\($0)" } ?? ""
    let target = path + query
    return !disallowedPaths.contains { Self.matches($0, against: target) }
  }

  private static func matches(_ pattern: String, against target: String) -> Bool {
    let anchored = pattern.hasSuffix("$")
    let body = anchored ? String(pattern.dropLast()) : pattern
    let pieces = body.components(separatedBy: "*").map(NSRegularExpression.escapedPattern(for:))
    let expression = "^" + pieces.joined(separator: ".*") + (anchored ? "$" : "")
    return target.range(of: expression, options: .regularExpression) != nil
  }
}
