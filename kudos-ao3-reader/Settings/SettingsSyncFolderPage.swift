import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Library & Sync › Sync Folder: deletion signing (tombstone trust),
/// folder sync, its status and last result — moved as-is from the old single
/// Settings page.
struct SettingsSyncFolderPage: View {
    @Environment(\.modelContext) private var context

    @State private var isChoosingFolder = false
    @State private var persistenceStatus = PersistenceStatusStore.snapshot()
    @State private var isPreparingPersistence = false
    @State private var folderSyncStatus = FolderSyncService.snapshot()
    @State private var isFolderSyncing = false
    @State private var showingSyncDetails = false
    @State private var lastFolderSyncResult: FolderSyncResult?
    @State private var notice: SettingsNotice?

    var body: some View {
        SettingsPageForm(route: .syncFolder) {
            FolderSyncSettingsSection(
                folderStatus: folderSyncStatus,
                isPreparing: isPreparingPersistence,
                isSyncing: isFolderSyncing,
                onChooseFolder: { isChoosingFolder = true },
                onSyncNow: startFolderSyncNow,
                onDisconnect: disconnectSyncFolder,
                onToggleAutoSync: setAutoSyncEnabled,
                onShowSyncDetails: { showingSyncDetails = true }
            )

            TombstoneTrustSettingsSection()

            FolderSyncMetadataSection(
                persistenceStatus: persistenceStatus,
                isPreparing: isPreparingPersistence,
                isSyncing: isFolderSyncing,
                onRetryPreparation: preparePersistenceForSync
            )
        }
        .onAppear {
            persistenceStatus = PersistenceStatusStore.snapshot()
            folderSyncStatus = FolderSyncService.snapshot()
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            connectSyncFolder(result)
        }
        .settingsNoticeAlert($notice)
        .sheet(isPresented: $showingSyncDetails) {
            NavigationStack {
                FolderSyncDetailsView(folderStatus: folderSyncStatus, lastResult: lastFolderSyncResult)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func preparePersistenceForSync() {
        guard !isPreparingPersistence else { return }
        isPreparingPersistence = true
        Task { @MainActor in
            let state = await PersistenceMigrationService.run(in: context)
            persistenceStatus = PersistenceStatusStore.snapshot()
            isPreparingPersistence = false
            if state == .failedRecoverable {
                notice = SettingsNotice(
                    title: "Folder Sync Prep Needs Retry",
                    message: persistenceStatus.detail
                )
            }
        }
    }

    private func connectSyncFolder(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try FolderSyncService.connect(to: url)
            folderSyncStatus = FolderSyncService.snapshot()
            startFolderSyncNow()
        } catch {
            folderSyncStatus = FolderSyncService.snapshot()
            notice = SettingsNotice(
                title: "Couldn't Connect Sync Folder",
                message: error.localizedDescription
            )
        }
    }

    private func startFolderSyncNow() {
        guard !isFolderSyncing else { return }
        isFolderSyncing = true
        Task { @MainActor in
            defer {
                folderSyncStatus = FolderSyncService.snapshot()
                persistenceStatus = PersistenceStatusStore.snapshot()
                isFolderSyncing = false
            }
            do {
                lastFolderSyncResult = try await FolderSyncService.syncNow(in: context)
            } catch {
                notice = SettingsNotice(
                    title: "Folder Sync Couldn't Finish",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func disconnectSyncFolder() {
        FolderSyncService.disconnect()
        folderSyncStatus = FolderSyncService.snapshot()
    }

    private func setAutoSyncEnabled(_ enabled: Bool) {
        FolderSyncService.setAutoSyncEnabled(enabled)
        folderSyncStatus = FolderSyncService.snapshot()
    }
}

/// Pure copy helpers for the Sync folder card (`Settings-Backup-Sync`).
enum SyncFolderDisplayCopy {
    static let footerText =
        "Kudos keeps a copy of your library in this folder. Other devices that use the same folder stay in step."

    static func folderHeading(_ sync: FolderSyncSnapshot) -> String {
        let name = sync.folderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Sync Folder" }
        if sync.folderPath.contains("com~apple~CloudDocs") {
            return "iCloud Drive › \(name)"
        }
        return name
    }

    static func isUpToDate(_ sync: FolderSyncSnapshot, isSyncing: Bool = false) -> Bool {
        !isSyncing && sync.isConnected && sync.lastError.isEmpty && !sync.isDirty && sync.lastSyncAt != nil
    }

    static func statusLine(
        _ sync: FolderSyncSnapshot,
        isSyncing: Bool = false,
        now: Date = Date()
    ) -> String {
        if isSyncing { return "Syncing library…" }
        if !sync.lastError.isEmpty { return sync.lastError }
        guard let date = sync.lastSyncAt else { return "Not synced yet" }
        let age = relativeSyncAge(from: date, to: now)
        if sync.isDirty {
            return "Changes pending · synced \(age)"
        }
        return "Up to date · synced \(age)"
    }

    static func relativeSyncAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 {
            let hours = seconds / 3600
            return "\(hours) \(hours == 1 ? "hr" : "hrs") ago"
        }
        return WorkStat.displayDate(date, time: .shortened)
    }

    static func pendingLabel(isDirty: Bool) -> String {
        isDirty ? "Pending" : "0 pending"
    }
}

struct FolderSyncSettingsSection: View {
    let folderStatus: FolderSyncSnapshot
    let isPreparing: Bool
    let isSyncing: Bool
    let onChooseFolder: () -> Void
    let onSyncNow: () -> Void
    let onDisconnect: () -> Void
    let onToggleAutoSync: (Bool) -> Void
    let onShowSyncDetails: () -> Void

    private var statusStyle: AnyShapeStyle {
        if !folderStatus.lastError.isEmpty {
            return AnyShapeStyle(.red)
        }
        if SyncFolderDisplayCopy.isUpToDate(folderStatus, isSyncing: isSyncing) {
            return AnyShapeStyle(.green)
        }
        return AnyShapeStyle(.secondaryInk)
    }

    private var connectedHeaderRow: some View {
        let heading = SyncFolderDisplayCopy.folderHeading(folderStatus)
        let status = SyncFolderDisplayCopy.statusLine(folderStatus, isSyncing: isSyncing)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.blue.opacity(0.15))
                Image(systemName: "cloud")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(heading)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(statusStyle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heading)
        .accessibilityValue(status)
    }

    @ViewBuilder
    private var connectedActionRows: some View {
        Toggle(isOn: Binding(
            get: { folderStatus.autoSyncEnabled },
            set: onToggleAutoSync
        )) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Auto Sync")
            }
        }
        .accentFill()

        Button(action: onSyncNow) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundStyle(.accentInk)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Sync Now")
                    .foregroundStyle(.accentInk)
            }
        }
        .disabled(isSyncing || isPreparing)
        .accessibilityLabel("Sync Now")

        Button(action: onShowSyncDetails) {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(SyncFolderDisplayCopy.pendingLabel(isDirty: folderStatus.isDirty))
                        .foregroundStyle(.secondaryInk)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .foregroundStyle(.secondaryInk)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text("Sync Details")
                        .foregroundStyle(.primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync Details")
        .accessibilityValue(SyncFolderDisplayCopy.pendingLabel(isDirty: folderStatus.isDirty))

        Button(action: onChooseFolder) {
            LabeledContent {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.body)
                        .foregroundStyle(.secondaryInk)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text("Change Folder")
                        .foregroundStyle(.primary)
                }
            }
        }
        .disabled(isSyncing || isPreparing)
        .accessibilityLabel("Change Folder")

        Button(role: .destructive, action: onDisconnect) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle")
                    .font(.body)
                    .foregroundStyle(.red)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Disconnect")
                    .foregroundStyle(.red)
            }
        }
        .disabled(isSyncing)
        .accessibilityLabel("Disconnect")
    }

    var body: some View {
        Section {
            if folderStatus.isConnected {
                connectedHeaderRow
                connectedActionRows
            } else {
                Button(action: onChooseFolder) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.body)
                            .foregroundStyle(.accentInk)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text("Choose Sync Folder")
                            .foregroundStyle(.accentInk)
                    }
                }
                .disabled(isSyncing || isPreparing)
                .accessibilityLabel("Choose Sync Folder")
            }

            if isPreparing || isSyncing {
                HStack(spacing: 12) {
                    ProgressView().accentFill()
                    Text(isSyncing ? "Syncing library…" : "Preparing your library…")
                        .foregroundStyle(.secondaryInk)
                }
            }
        } header: {
            Text("Sync folder")
        } footer: {
            Text(SyncFolderDisplayCopy.footerText)
        }
    }
}

private struct FolderSyncMetadataSection: View {
    let persistenceStatus: PersistenceStatusSnapshot
    let isPreparing: Bool
    let isSyncing: Bool
    let onRetryPreparation: () -> Void

    var body: some View {
        Section {
            LabeledContent("Metadata", value: persistenceStatus.migrationState.title)
            if let date = persistenceStatus.lastMigrationAttempt {
                LabeledContent("Last Checked", value: WorkStat.displayDate(date, time: .shortened))
            }
            Button(action: onRetryPreparation) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(.accentInk)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(
                        persistenceStatus.migrationState == .completed ? "Check Metadata" : "Retry Metadata Prep"
                    )
                    .foregroundStyle(.accentInk)
                }
            }
            .disabled(isPreparing || isSyncing)
        } header: {
            Text("Library metadata")
        }
    }
}

/// Lightweight diagnostics, mainly useful during development/testing — deliberately
/// tucked behind its own screen rather than cluttering the main Settings list.
struct FolderSyncDetailsView: View {
    let folderStatus: FolderSyncSnapshot
    let lastResult: FolderSyncResult?

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Connected", value: folderStatus.isConnected ? "Yes" : "No")
                LabeledContent("Auto Sync", value: folderStatus.autoSyncEnabled ? "On" : "Off")
                LabeledContent("Pending Changes", value: folderStatus.isDirty ? "Yes" : "No")
                if let date = folderStatus.lastSyncAt {
                    LabeledContent("Last Synced", value: WorkStat.displayDate(date, time: .standard))
                }
                if !folderStatus.lastError.isEmpty {
                    LabeledContent("Last Error", value: folderStatus.lastError)
                }
            }
            if let lastResult {
                Section("Last Sync Result") {
                    LabeledContent("Read Remote File", value: lastResult.didReadRemoteFile ? "Yes" : "No")
                    LabeledContent("Wrote Remote File", value: lastResult.didWriteRemoteFile ? "Yes" : "No")
                    LabeledContent("Missing Remote File", value: lastResult.missingRemoteFile ? "Yes" : "No")
                    LabeledContent("Conflicts Folded", value: "\(lastResult.foldedConflicts)")
                    LabeledContent("Works Restored", value: "\(lastResult.restoredWorks)")
                    LabeledContent("Queues Suppressed", value: "\(lastResult.suppressedQueues)")
                    LabeledContent("Queues Revived", value: "\(lastResult.revivedQueues)")
                    LabeledContent("Ambiguous Queue Conflicts", value: "\(lastResult.ambiguousQueueConflicts)")
                }
            } else {
                Section {
                    Text("No sync has run yet this session.")
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
        .navigationTitle("Sync Details")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
