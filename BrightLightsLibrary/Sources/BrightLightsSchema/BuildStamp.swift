import Foundation

public struct BuildStamp: Equatable, Sendable {
  public var build: String
  public var dirty: Bool
  public var builtAt: String

  public init(build: String, dirty: Bool, builtAt: String) {
    self.build = build
    self.dirty = dirty
    self.builtAt = builtAt
  }

  public static let unknown = Self(build: "unknown", dirty: false, builtAt: "unknown")

  public var displayValue: String {
    guard build != "unknown" else { return "unknown" }
    let date = ISO8601DateFormatter().date(from: builtAt)
    let formattedDate = date?.formatted(date: .numeric, time: .shortened) ?? builtAt
    return "\(build) · \(dirty ? "dirty" : "clean") · \(formattedDate)"
  }

  public static func from(infoDictionary: [String: Any]) -> Self {
    guard let build = infoDictionary["BLBuild"] as? String,
      let dirtyValue = infoDictionary["BLDirty"] as? String,
      let builtAt = infoDictionary["BLBuiltAt"] as? String,
      !build.isEmpty, !builtAt.isEmpty,
      dirtyValue == "true" || dirtyValue == "false"
    else { return .unknown }

    return Self(build: build, dirty: dirtyValue == "true", builtAt: builtAt)
  }

  public static func fromMainBundle() -> Self {
    from(infoDictionary: Bundle.main.infoDictionary ?? [:])
  }
}
