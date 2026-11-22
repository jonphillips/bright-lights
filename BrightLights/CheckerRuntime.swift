#if os(macOS)
import AppKit
import BrightLightsChecking
import BrightLightsSchema
import Dependencies
import OSLog
import SQLiteData
import Sharing
import ServiceManagement

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
    @Shared(.checkerEnabled) var checkerEnabled
    guard checkerEnabled else { return }
    guard scheduler == nil else { return }
    let activity = NSBackgroundActivityScheduler(identifier: "com.jonphillips.BrightLights.check-sources")
    activity.interval = scheduleInterval
    activity.tolerance = scheduleTolerance
    activity.repeats = true
    activity.schedule { completion in
      Task { @MainActor in
        _ = await check(all: false, trigger: .scheduled)
        completion(.finished)
      }
    }
    scheduler = activity
  }

  static func restoreLoginItemIfNeeded() async {
    @Shared(.checkerEnabled) var checkerEnabled
    @Shared(.checkerDeviceID) var deviceID
    @Shared(.checkerRegistrationError) var checkerRegistrationError
    guard checkerEnabled, BrightLightsSyncPolicy.isEnabled(
      debugOptIn: UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled")
    ),
      let id = UUID(uuidString: deviceID), SMAppService.mainApp.status != .enabled
    else { return }
    @Dependency(\.defaultDatabase) var db
    let holdsLease = (try? await db.read { try CheckerLease.holds(deviceID: id, in: $0) }) == true
    guard holdsLease else { return }
    do {
      try SMAppService.mainApp.register()
      $checkerRegistrationError.withLock { $0 = "" }
    } catch {
      let message = error.localizedDescription
      $checkerRegistrationError.withLock { $0 = message }
      Logger(subsystem: "com.jonphillips.BrightLights", category: "SourceChecks")
        .error("Could not restore login item registration: \(message)")
    }
  }

  static func stop() {
    scheduler?.invalidate()
    scheduler = nil
  }

  static func checkNow(all: Bool) async -> [SourceCheckReport] {
    await check(all: all, trigger: .manual)
  }

  private static func check(all: Bool, trigger: CheckReportTrigger) async -> [SourceCheckReport] {
    guard !isChecking else { return [] }
    isChecking = true
    defer { isChecking = false }
    let syncEnabled = BrightLightsSyncPolicy.isEnabled(
      debugOptIn: UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled")
    )
    @Shared(.checkerEnabled) var checkerEnabled
    let checkerIsEnabled = checkerEnabled
    guard syncEnabled, checkerIsEnabled else { return [] }
    @Shared(.checkerDeviceID) var deviceID
    guard let id = UUID(uuidString: deviceID) else { return [] }
    @Dependency(\.defaultDatabase) var db
    @Dependency(\.defaultSyncEngine) var syncEngine
    @Dependency(\.checkReportClient) var checkReportClient
    let mayCheck = (try? await db.read {
      try CheckerLease.mayCheck(deviceID: id, checkerEnabled: checkerIsEnabled, syncEnabled: syncEnabled, in: $0)
    }) == true
    guard mayCheck else { return [] }
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Checking Bright Lights sources")
    defer { ProcessInfo.processInfo.endActivity(activity) }
    do {
      try await syncEngine.syncChanges()
    } catch {
      Logger(subsystem: "com.jonphillips.BrightLights", category: "SourceChecks")
        .error("CloudKit sync before source check failed: \(error.localizedDescription, privacy: .public)")
    }
    let checker = SourceChecker()
    let checkedAt = Date.now
    let reports = await checker.runPass(in: db, checkAll: all, now: checkedAt)
    do {
      try await syncEngine.syncChanges()
    } catch {
      Logger(subsystem: "com.jonphillips.BrightLights", category: "SourceChecks")
        .error("CloudKit sync after source check failed: \(error.localizedDescription, privacy: .public)")
    }
    guard !reports.isEmpty else { return reports }
    do {
      let sources = try await db.read { try Source.canonical.fetchAll($0) }
      let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
      let deviceName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
      let build = BuildStamp.fromMainBundle().displayValue
      let records = reports.compactMap { report in
        sourcesByID[report.sourceID].map {
          CheckReportRecord(checkedAt: checkedAt, trigger: trigger, build: build,
            deviceName: deviceName, source: $0, report: report)
        }
      }
      try await checkReportClient.append(records, checkedAt, id)
    } catch {
      Logger(subsystem: "com.jonphillips.BrightLights", category: "SourceChecks")
        .error("Could not append check report: \(error.localizedDescription, privacy: .public)")
    }
    return reports
  }
}
#endif
