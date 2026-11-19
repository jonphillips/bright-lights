import CloudKit
import Dependencies
import OSLog
import SQLiteData
import SwiftUI
import BrightLightsSchema

@main
struct BrightLightsApp: App {
  init() {
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
  }

  var body: some Scene {
    WindowGroup {
      SourcesView()
    }
  }
}

private func startSyncIfEnabled() async {
  guard UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled") else { return }
  do {
    guard try await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").accountStatus() == .available else {
      return
    }
    @Dependency(\.defaultSyncEngine) var engine
    try await engine.start()
  } catch {
    Logger(subsystem: "com.jonphillips.BrightLights", category: "Sync")
      .error("CloudKit sync could not start; Bright Lights remains local-only: \(error)")
  }
}
