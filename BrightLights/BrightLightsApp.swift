import CloudKit
import Dependencies
import OSLog
import SQLiteData
import SwiftUI
import BrightLightsSchema
import Sharing

@main
struct BrightLightsApp: App {
#if os(macOS)
  @NSApplicationDelegateAdaptor(BrightLightsMacDelegate.self) private var macDelegate
#endif

  init() {
    @Shared(.checkerDeviceID) var checkerDeviceID
    if UUID(uuidString: checkerDeviceID) == nil {
      $checkerDeviceID.withLock { $0 = UUID().uuidString }
    }
    do {
      try prepareDependencies {
        try $0.bootstrapBrightLightsDatabase()
        try $0.defaultDatabase.write { db in
          _ = try Household.ensureDefault(in: db)
          try Source.syncFromRegistry(in: db)
        }
      }
    } catch {
      fatalError("Bright Lights database setup failed: \(error)")
    }
    if ProcessInfo.processInfo.arguments.contains("-BrightLightsCloudKitSyncEnabled") {
      UserDefaults.standard.set(true, forKey: "BrightLightsCloudKitSyncEnabled")
    }
    Task { await startSyncIfEnabled() }
#if os(macOS)
    Task {
      await CheckerRuntime.restoreLoginItemIfNeeded()
      CheckerRuntime.startIfEnabled()
    }
#endif
  }

  var body: some Scene {
    WindowGroup { AppContainer() }
  }
}

private func startSyncIfEnabled() async {
  guard UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled") else { return }
  do {
    guard try await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").accountStatus() == .available else { return }
    @Dependency(\.defaultSyncEngine) var engine
    @Dependency(\.defaultDatabase) var database
    try await engine.start()
    try await engine.syncChanges()
    try await database.write { db in
      _ = try Household.ensureDefault(in: db)
      try Source.syncFromRegistry(in: db)
    }
    try await engine.syncChanges()
  } catch {
    Logger(subsystem: "com.jonphillips.BrightLights", category: "Sync")
      .error("CloudKit sync could not start; Bright Lights remains local-only: \(error)")
  }
}
