import BrightLightsChecking
import BrightLightsSchema
import BrightLightsTaste
import CloudKit
import CloudSyncKit
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
  @FetchAll private var people: [Person]
  @FetchAll(SyncMetadata.where { $0.recordType.eq("households") }) private var syncMetadata: [SyncMetadata]
  @FetchAll private var sources: [Source]
  @FetchAll private var tasteRecords: [TasteRecord]
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
  @State private var syncStatusSummary = "Checking sync status…"
  @State private var sharedRecord: SharedRecord?
  @State private var currentPersonNameDraft = ""
  @State private var savedPersonName: String?
  @Shared(.checkerDeviceID) private var deviceIDString
  @Shared(.checkerEnabled) private var checkerEnabled
  @Shared(.checkerRegistrationError) private var checkerRegistrationError
  @Shared(.appStorage("BrightLightsCloudKitSyncEnabled")) private var syncEnabled = false

  private var household: Household? {
    households.isEmpty ? nil : Household.survivor(in: households) {
      Household.sharingState(of: $0, metadata: syncMetadata)
    }
  }
  private var sharing: HouseholdSharing {
    household.map { Household.sharingState(of: $0, metadata: syncMetadata) } ?? .private
  }
  private var deviceID: UUID? { UUID(uuidString: deviceIDString) }
  private var syncIsEnabled: Bool {
    BrightLightsSyncPolicy.isEnabled(debugOptIn: syncEnabled)
  }

  var body: some View {
    Form {
      Section("Sync") {
        LabeledContent("Build", value: "\(BuildStamp.fromMainBundle().displayValue) · \(BrightLightsSyncPolicy.environmentName)")
        LabeledContent("Status", value: syncStatusSummary)
        #if DEBUG
          Toggle("iCloud sync", isOn: Binding(get: { syncEnabled }, set: { setSync($0) }))
        #else
          LabeledContent("iCloud sync", value: "On")
        #endif
      }
      Section("Household") {
        switch sharing {
        case .sharedWithMe:
          LabeledContent("Sharing", value: "Shared by \(householdOwnerName)")
        case .private, .sharedByMe:
          LabeledContent("Sharing", value: sharing == .sharedByMe ? "Shared by you" : "Private")
          #if os(iOS)
          Button("Share household") { shareHousehold() }
          #endif
        }
      }
      Section("People") {
        if currentPerson != nil {
          VStack(alignment: .leading, spacing: 6) {
            Text("Your name")
            TextField("Your name", text: $currentPersonNameDraft)
              .onSubmit(saveCurrentPersonName)
          }
        }
        ForEach(people.sorted { $0.createdAt < $1.createdAt }) { person in
          LabeledContent(person.displayName.isEmpty ? "Unnamed person" : person.displayName,
            value: person.id == currentPersonID ? "You" : "")
        }
      }
      .onAppear(perform: loadCurrentPersonName)
      .onDisappear(perform: saveCurrentPersonName)
      .onChange(of: currentPerson?.id) { _, _ in loadCurrentPersonName() }
      .onChange(of: currentPerson?.displayName) { _, value in
        guard let value, savedPersonName == currentPersonNameDraft else { return }
        currentPersonNameDraft = value
        savedPersonName = value
      }
      Section("Taste") {
        NavigationLink("Taste notes") { TasteNotesView() }
        LabeledContent("Suggestion provider", value: suggestionProviderName)
        LabeledContent("Last 30 days", value: tasteAgreementSummary)
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
        if !checkerRegistrationError.isEmpty {
          Text("Could not register Bright Lights as a login item: \(checkerRegistrationError)")
            .font(.caption).foregroundStyle(.secondary)
        }
        if syncIsEnabled, household?.checkerDeviceID == deviceID {
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
      Section("About") {
        LabeledContent("App", value: "Bright Lights")
      }
      Section("Model") {
        Picker("Provider", selection: $modelProvider) {
          ForEach(FrontierProvider.allCases) { provider in Text(provider.displayName).tag(provider) }
        }
        SecureField("\(modelProvider.displayName) API key", text: $modelKey)
        Text(savedModelKeyStatus ?? "No key saved")
          .font(.caption).foregroundStyle(.secondary)
        Button("Save model key") { saveModelKey() }
        if savedModelKeyStatus != nil {
          Button("Remove key", role: .destructive) { removeModelKey() }
        }
      }
      if let statusNote { Text(statusNote).foregroundStyle(.secondary) }
    }
    .navigationTitle("Settings")
    .onAppear { refreshSavedModelKeyStatus() }
#if os(iOS)
    .sheet(item: $sharedRecord) { CloudSharingView(sharedRecord: $0) }
#endif
    .task { await refreshSyncStatus() }
    .onChange(of: syncEngine.isSynchronizing) { _, _ in
      Task { await refreshSyncStatus() }
    }
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

  @Shared(.currentPersonID) private var currentPersonIDString
  private var currentPersonID: UUID? { UUID(uuidString: currentPersonIDString) }
  private var suggestionProviderName: String {
    FrontierResolver().resolve(isConfigured: { apiKeyStore.key($0) != nil })?.displayName ?? "None"
  }
  private var tasteAgreementSummary: String {
    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
    let result = TastePrompt.agreement(records: tasteRecords, since: cutoff)
    return "\(result.kept) of \(result.suggestedKeep) keeps · \(result.clearedOrPassed) of \(result.suggestedClear) clears · \(result.unsure) unsure"
  }
  private var currentPerson: Person? { people.first { $0.id == currentPersonID } }
  private var householdOwnerName: String { syncMetadata.first(where: {
    $0.recordType == "households" && UUID(uuidString: $0.recordPrimaryKey) == household?.id
  })?.share?.owner.userIdentity.nameComponents?.givenName ?? "the owner" }

  private func shareHousehold() {
    guard let household else { return }
    Task {
      do {
        let record = try await syncEngine.share(record: household) {
          $0[CKShare.SystemFieldKey.title] = "Bright Lights"
        }
        await MainActor.run { sharedRecord = record }
      } catch { statusNote = error.localizedDescription }
    }
  }

  private func loadCurrentPersonName() {
    guard let currentPerson else { return }
    currentPersonNameDraft = currentPerson.displayName
    savedPersonName = currentPerson.displayName
  }

  private func saveCurrentPersonName() {
    guard let person = currentPerson, let savedPersonName,
      currentPersonNameDraft != savedPersonName
    else { return }
    let previousName = savedPersonName
    let updatedName = currentPersonNameDraft
    self.savedPersonName = updatedName
    Task {
      do {
        try await db.write { db in
          try Person.find(person.id).update { $0.displayName = #bind(updatedName) }.execute(db)
        }
        statusNote = nil
      } catch {
        if self.savedPersonName == updatedName { self.savedPersonName = previousName }
        statusNote = error.localizedDescription
      }
    }
  }

  private func refreshSavedModelKeyStatus() {
    savedModelKeyStatus = apiKeyStore.maskedKey(modelProvider)
  }

  private func refreshSyncStatus() async {
    let accountStatus = (try? await CKContainer(identifier: "iCloud.com.jonphillips.BrightLights").accountStatus()) ?? .couldNotDetermine
    let account: SyncAccountStatus = switch accountStatus {
    case .available: .available
    case .noAccount: .noAccount
    case .restricted: .restricted
    case .couldNotDetermine: .couldNotDetermine
    case .temporarilyUnavailable: .temporarilyUnavailable
    @unknown default: .unknown
    }
    let pending = (try? await CloudSync.pendingRecordZoneChangeCount(in: db)) ?? 0
    let health = SyncHealth(
      isManuallyEnabled: syncIsEnabled, account: account,
      isEngineRunning: syncEngine.isRunning, pendingChangeCount: pending,
      isFetchingChanges: syncEngine.isFetchingChanges
    )
    syncStatusSummary = health.displayStatus.summary
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

  private func removeModelKey() {
    apiKeyStore.setKey(nil, for: modelProvider)
    modelKey = ""
    refreshSavedModelKeyStatus()
    statusNote = "Model key removed."
  }

#if os(macOS)
  private func enableChecker() {
    guard syncIsEnabled else {
      statusNote = "Turn on CloudKit sync before enabling source checks."; return
    }
    guard household != nil else { statusNote = "Household is not available yet."; return }
    guard let deviceID else { statusNote = "This Mac's checker identity is not available yet."; return }
    let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    do {
      try SMAppService.mainApp.register()
      $checkerRegistrationError.withLock { $0 = "" }
      try db.write { transactionDB in
        let sharing = try Household.sharingLookup(in: transactionDB)
        try CheckerLease.claim(
          deviceID: deviceID, name: name, at: .now, sharing: sharing, in: transactionDB
        )
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
      $checkerRegistrationError.withLock { $0 = "" }
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
