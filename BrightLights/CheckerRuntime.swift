#if os(macOS)
import AppKit
import BrightLightsChecking
import BrightLightsSchema
import Dependencies
import SQLiteData
import Sharing

@MainActor
final class BrightLightsMacDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
enum CheckerRuntime {
  private static let scheduleInterval: TimeInterval = 60 * 60 // M1 S3 specifies an hourly scheduler tick.
  private static let scheduleTolerance = scheduleInterval / 4 // A quarter-tick grace is 15 minutes.
  private static var scheduler: NSBackgroundActivityScheduler?
  private static var isChecking = false

  static func startIfEnabled() {
    guard UserDefaults.standard.bool(forKey: "brightLights.checkerEnabled") else { return }
    guard scheduler == nil else { return }
    let activity = NSBackgroundActivityScheduler(identifier: "com.jonphillips.BrightLights.check-sources")
    activity.interval = scheduleInterval
    activity.tolerance = scheduleTolerance
    activity.repeats = true
    activity.schedule { completion in
      Task { @MainActor in
        _ = await check(all: false)
        completion(.finished)
      }
    }
    scheduler = activity
  }

  static func stop() {
    scheduler?.invalidate()
    scheduler = nil
  }

  static func checkNow(all: Bool) async -> [SourceCheckReport] {
    await check(all: all)
  }

  private static func check(all: Bool) async -> [SourceCheckReport] {
    guard !isChecking else { return [] }
    isChecking = true
    defer { isChecking = false }
    let syncEnabled = UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled")
    let checkerEnabled = UserDefaults.standard.bool(forKey: "brightLights.checkerEnabled")
    guard syncEnabled, checkerEnabled else { return [] }
    @Shared(.appStorage("brightLights.checkerDeviceID")) var deviceID = ""
    guard let id = UUID(uuidString: deviceID) else { return [] }
    @Dependency(\.defaultDatabase) var db
    let mayCheck = (try? await db.read {
      try CheckerLease.mayCheck(deviceID: id, checkerEnabled: checkerEnabled, syncEnabled: syncEnabled, in: $0)
    }) == true
    guard mayCheck else { return [] }
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Checking Bright Lights sources")
    defer { ProcessInfo.processInfo.endActivity(activity) }
    let checker = SourceChecker()
    return await checker.runPass(in: db, checkAll: all)
  }
}
#endif
