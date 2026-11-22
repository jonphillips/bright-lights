import CloudKit
import Dependencies
import OSLog
import SQLiteData
import SwiftUI
import BrightLightsSchema
import Sharing
#if os(iOS)
import UIKit
#endif

@main
struct BrightLightsApp: App {
#if os(macOS)
  @NSApplicationDelegateAdaptor(BrightLightsMacDelegate.self) private var macDelegate
#elseif os(iOS)
  @UIApplicationDelegateAdaptor(BrightLightsIOSDelegate.self) private var iosDelegate
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
          _ = try TasteRecord.backfill(in: db)
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
  guard BrightLightsSyncPolicy.isEnabled(
    debugOptIn: UserDefaults.standard.bool(forKey: "BrightLightsCloudKitSyncEnabled")
  ) else { return }
  do {
    guard try await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").accountStatus() == .available else { return }
    @Dependency(\.defaultSyncEngine) var engine
    @Dependency(\.defaultDatabase) var database
    try await engine.start()
    try await engine.syncChanges()
    let recordName = try? await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").userRecordID().recordName
    try await database.write { db in
      let household = try Household.ensureDefault(in: db)
      try Source.syncFromRegistry(in: db)
      _ = try TasteRecord.backfill(in: db)
      bindCurrentPerson(recordName, household, in: db)
    }
    try await engine.syncChanges()
  } catch {
    Logger(subsystem: "com.jonphillips.BrightLights", category: "Sync")
      .error("CloudKit sync could not start; Bright Lights remains local-only: \(error)")
  }
}

private func bindCurrentPerson(_ recordName: String?, _ household: Household, in db: Database) {
  guard let recordName else { return }
  let metadata = (try? SyncMetadata.fetchAll(db))?.first(where: {
    $0.recordType == "households" && $0.recordPrimaryKey == household.id.uuidString
  })
  let givenName = metadata?.share?.currentUserParticipant?.userIdentity.nameComponents?.givenName
  let id = try? Person.bind(recordName: recordName, participantGivenName: givenName, in: household, db: db)
  if let id {
    @Shared(.currentPersonID) var currentPersonID
    $currentPersonID.withLock { $0 = id.uuidString }
  }
}

#if os(iOS)
@MainActor
final class BrightLightsIOSDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = BrightLightsSceneDelegate.self
    return configuration
  }
}

final class BrightLightsSceneDelegate: UIResponder, UIWindowSceneDelegate {
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @Dependency(\.defaultDatabase) private var database

  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    accept(metadata)
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    if let metadata = options.cloudKitShareMetadata { accept(metadata) }
  }

  private func accept(_ metadata: CKShare.Metadata) {
    Task {
      do {
        try await syncEngine.acceptShare(metadata: metadata)
        try await syncEngine.syncChanges()
        let recordName = try? await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").userRecordID().recordName
        try await database.write { db in
          let household = try Household.ensureDefault(in: db)
          try Source.syncFromRegistry(in: db)
          _ = try TasteRecord.backfill(in: db)
          bindCurrentPerson(recordName, household, in: db)
        }
      } catch {
        Logger(subsystem: "com.jonphillips.BrightLights", category: "Sharing")
          .error("CloudKit share acceptance failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
#endif
