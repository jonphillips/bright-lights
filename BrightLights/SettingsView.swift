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
  @FetchAll(Household.canonical) private var households: [Household]
  @FetchAll private var sources: [Source]
  @Dependency(\.defaultDatabase) private var db
  @Dependency(\.defaultSyncEngine) private var syncEngine
  @Dependency(\.apiKeyStore) private var apiKeyStore
  @State private var modelKey = ""
  @State private var savedModelKeyStatus: String?
  @State private var modelProvider: FrontierProvider = .anthropic
  @State private var showTakeover = false
  @State private var statusNote: String?
  @State private var lastPassReports: [SourceCheckReport] = []
  @State private var lastPassDuration: TimeInterval?
  @Shared(.appStorage("brightLights.checkerDeviceID")) private var deviceIDString = ""
  @Shared(.appStorage("brightLights.checkerEnabled")) private var checkerEnabled = false
  @Shared(.appStorage("BrightLightsCloudKitSyncEnabled")) private var syncEnabled = false

  private var household: Household? { households.first }
  private var deviceID: UUID? { UUID(uuidString: deviceIDString) }

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
          Button("Check all now") {
            Task {
              let startedAt = Date.now
              lastPassReports = await CheckerRuntime.checkNow(all: true)
              lastPassDuration = Date.now.timeIntervalSince(startedAt)
            }
          }
        }
      }
      if !lastPassReports.isEmpty {
        Section("Last manual pass") {
          if let lastPassDuration {
            LabeledContent("Duration", value: lastPassDuration.formatted(.number.precision(.fractionLength(1))) + " s")
          }
          LabeledContent("Model calls", value: String(lastPassReports.reduce(0) { $0 + $1.modelCalls }))
          LabeledContent("Listing rows written", value: String(lastPassReports.reduce(0) { $0 + $1.rowsWritten }))
          ForEach(lastPassReports) { report in
            VStack(alignment: .leading, spacing: 2) {
              Text(sources.first { $0.id == report.sourceID }?.name ?? report.sourceID.uuidString)
              Text("\(report.outcome.rawValue) · \(report.listingCount) listings · \(report.rungs.map(\.rawValue).joined(separator: ", ")) · \(report.pagesRead) pages · \(report.modelCalls) model calls · \(report.rowsWritten) rows written")
                .font(.caption).foregroundStyle(.secondary)
              if let note = report.note { Text(note).font(.caption).foregroundStyle(.secondary) }
              }
            }
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
        Text(savedModelKeyStatus ?? "No key saved")
          .font(.caption).foregroundStyle(.secondary)
        Button("Save model key") { saveModelKey() }
      }
      if let statusNote { Text(statusNote).foregroundStyle(.secondary) }
    }
    .navigationTitle("Settings")
    .onAppear { refreshSavedModelKeyStatus() }
    .onChange(of: modelProvider) { refreshSavedModelKeyStatus() }
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

  private func refreshSavedModelKeyStatus() {
    savedModelKeyStatus = apiKeyStore.maskedKey(modelProvider)
  }

  private func saveModelKey() {
    guard !modelKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      statusNote = "Enter an API key before saving."
      return
    }
    apiKeyStore.setKey(modelKey, for: modelProvider)
    modelKey = ""
    refreshSavedModelKeyStatus()
    statusNote = savedModelKeyStatus == nil ? "The key could not be read back from Keychain." : "Model key saved."
  }

#if os(macOS)
  private func enableChecker() {
    guard syncEnabled else {
      statusNote = "Turn on CloudKit sync before enabling source checks."; return
    }
    guard household != nil else { statusNote = "Household is not available yet."; return }
    guard let deviceID else { statusNote = "This Mac's checker identity is not available yet."; return }
    let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    do {
      try SMAppService.mainApp.register()
      try db.write { transactionDB in try CheckerLease.claim(deviceID: deviceID, name: name, at: .now, in: transactionDB) }
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
