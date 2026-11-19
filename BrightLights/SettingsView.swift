import BrightLightsChecking
import BrightLightsSchema
import CloudKit
import Dependencies
import LLMClientKit
import SQLiteData
import Sharing
import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
  @FetchAll private var households: [Household]
  @FetchAll private var sources: [Source]
  @Dependency(\.defaultDatabase) private var db
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @Dependency(\.apiKeyStore) private var apiKeyStore
  @State private var modelKey = ""
  @State private var modelProvider: FrontierProvider = .anthropic
  @State private var showTakeover = false
  @State private var statusNote: String?
  @Shared(.appStorage("brightLights.checkerDeviceID")) private var deviceIDString = ""
  @Shared(.appStorage("brightLights.checkerEnabled")) private var checkerEnabled = false
  @Shared(.appStorage("BrightLightsCloudKitSyncEnabled")) private var syncEnabled = false

  private var household: Household? { households.first }
  private var deviceID: UUID {
    if let id = UUID(uuidString: deviceIDString) { return id }
    let id = UUID(); $deviceIDString.withLock { $0 = id.uuidString }; return id
  }

  var body: some View {
    Form {
      Section("Sync") {
        Toggle("iCloud sync", isOn: Binding(get: { syncEnabled }, set: { setSync($0) }))
      }
      #if os(macOS)
      Section("Source checking") {
        Toggle("Check sources on this Mac", isOn: Binding(
          get: { checkerEnabled }, set: { newValue in
            guard newValue else { disableChecker(); return }
            if let other = household?.checkerDeviceID, other != deviceID {
              showTakeover = true
            } else { enableChecker() }
          }
        ))
        if let household {
          LabeledContent("Checking Mac", value: household.checkerDeviceName ?? "None")
          LabeledContent("Last household check", value: sources.compactMap(\.lastCheckedAt).max()?.formatted() ?? "Never")
        }
        if SMAppService.mainApp.status == .requiresApproval {
          Text("macOS needs approval to start Bright Lights at login.").foregroundStyle(.secondary)
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
        }
        if syncEnabled, household?.checkerDeviceID == deviceID {
          Button("Check all now") { Task { await CheckerRuntime.checkNow(all: true) } }
        }
      }
      #else
      Section("Source checking") {
        LabeledContent("Checking Mac", value: household?.checkerDeviceName ?? "Not configured")
        LabeledContent("Last household check", value: sources.compactMap(\.lastCheckedAt).max()?.formatted() ?? "Never")
      }
      #endif
      Section("Model") {
        Picker("Provider", selection: $modelProvider) {
          ForEach(FrontierProvider.allCases) { provider in Text(provider.displayName).tag(provider) }
        }
        SecureField("\(modelProvider.displayName) API key", text: $modelKey)
        Text(apiKeyStore.maskedKey(modelProvider) ?? "No key saved")
          .font(.caption).foregroundStyle(.secondary)
        Button("Save model key") { apiKeyStore.setKey(modelKey, for: modelProvider); modelKey = "" }
      }
      if let statusNote { Text(statusNote).foregroundStyle(.secondary) }
    }
    .navigationTitle("Settings")
#if os(macOS)
    .confirmationDialog(
      "\(household?.checkerDeviceName ?? "Another Mac") is checking now. Make this Mac the checker?",
      isPresented: $showTakeover,
      titleVisibility: .visible
    ) {
      Button("Make this Mac the checker", role: .destructive) { enableChecker() }
      Button("Cancel", role: .cancel) {}
    }
#endif
  }

#if os(macOS)
  private func enableChecker() {
    guard syncEnabled else {
      statusNote = "Turn on CloudKit sync before enabling source checks."; return
    }
    guard let household else { statusNote = "Household is not available yet."; return }
    let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    do {
      try SMAppService.mainApp.register()
      try db.write { transactionDB in
        try Household.find(household.id).update {
          $0.checkerDeviceID = #bind(deviceID); $0.checkerDeviceName = #bind(name); $0.checkerClaimedAt = #bind(Date.now)
        }.execute(transactionDB)
      }
      $checkerEnabled.withLock { $0 = true }
      statusNote = nil
      CheckerRuntime.startIfEnabled()
      Task { await CheckerRuntime.checkNow(all: true) }
    } catch { statusNote = error.localizedDescription }
  }

  private func disableChecker() {
    do {
      try SMAppService.mainApp.unregister()
      $checkerEnabled.withLock { $0 = false }
      CheckerRuntime.stop()
    } catch { statusNote = error.localizedDescription }
  }
#endif

  private func setSync(_ enabled: Bool) {
    $syncEnabled.withLock { $0 = enabled }
    guard enabled else { syncEngine.stop(); return }
    Task {
      do {
        guard try await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").accountStatus() == .available else {
          $syncEnabled.withLock { $0 = false }; statusNote = "An available iCloud account is required."; return
        }
        try await syncEngine.start()
      } catch {
        $syncEnabled.withLock { $0 = false }; statusNote = error.localizedDescription
      }
    }
  }
}
