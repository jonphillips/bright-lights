import Foundation

enum BrightLightsSyncPolicy {
  static var environmentName: String {
    #if DEBUG
      "Development"
    #else
      "Production"
    #endif
  }

  static func isEnabled(debugOptIn: Bool) -> Bool {
    #if DEBUG
      debugOptIn
    #else
      true
    #endif
  }
}
