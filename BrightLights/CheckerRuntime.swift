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
        _ = await checkIfHolder()
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

  private static func checkIfHolder() async -> [SourceCheckReport] {
    @Shared(.appStorage("brightLights.checkerDeviceID")) var deviceID = ""
    guard let id = UUID(uuidString: deviceID) else { return [] }
    @Dependency(\.defaultDatabase) var db
    guard let household = try? await db.read({ try Household.fetchAll($0).first }), household.checkerDeviceID == id else { return [] }
    return await check(all: false)
  }

  private static func check(all: Bool) async -> [SourceCheckReport] {
    guard UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled") else { return [] }
    guard !isChecking else { return [] }
    @Shared(.appStorage("brightLights.checkerDeviceID")) var deviceID = ""
    guard let id = UUID(uuidString: deviceID) else { return [] }
    @Dependency(\.defaultDatabase) var db
    guard let household = try? await db.read({ try Household.fetchAll($0).first }), household.checkerDeviceID == id else { return [] }
    isChecking = true
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Checking Bright Lights sources")
    let checker = SourceChecker()
    let reports = await checker.runPass(in: db, checkAll: all)
    ProcessInfo.processInfo.endActivity(activity)
    isChecking = false
    return reports
  }
}
#endif
