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
            TombstoneTrustSettingsSection()

            FolderSyncSettingsSection(
                persistenceStatus: persistenceStatus,
                folderStatus: folderSyncStatus,
                isPreparing: isPreparingPersistence,
                isSyncing: isFolderSyncing,
                onChooseFolder: { isChoosingFolder = true },
                onSyncNow: startFolderSyncNow,
                onDisconnect: disconnectSyncFolder,
                onRetryPreparation: preparePersistenceForSync,
                onToggleAutoSync: setAutoSyncEnabled,
                onShowSyncDetails: { showingSyncDetails = true }
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

struct FolderSyncSettingsSection: View {
    let persistenceStatus: PersistenceStatusSnapshot
    let folderStatus: FolderSyncSnapshot
    let isPreparing: Bool
    let isSyncing: Bool
    let onChooseFolder: () -> Void
    let onSyncNow: () -> Void
    let onDisconnect: () -> Void
    let onRetryPreparation: () -> Void
    let onToggleAutoSync: (Bool) -> Void
    let onShowSyncDetails: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(persistenceStatus.migrationState.title)
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(color: Color(hex: "#64D2FF") ?? .cyan, systemImage: "externaldrive")
                    Text("Metadata")
                }
            }

            if folderStatus.isConnected {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(folderStatus.folderDisplayName)
                        if !folderStatus.folderPath.isEmpty {
                            Text(folderStatus.folderPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "folder")
                        Text("Folder")
                    }
                }

                Toggle(isOn: Binding(
                    get: { folderStatus.autoSyncEnabled },
                    set: onToggleAutoSync
                )) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "arrow.triangle.2.circlepath.circle")
                        Text("Auto Sync")
                    }
                }
                .accentFill()

                Button(action: onSyncNow) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "arrow.triangle.2.circlepath")
                        Text("Sync Now")
                    }
                }
                .disabled(isSyncing || isPreparing)

                Button(action: onChooseFolder) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "folder.badge.gearshape")
                        Text("Change Folder")
                    }
                }
                .disabled(isSyncing || isPreparing)

                Button(action: onShowSyncDetails) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#6C6C70") ?? .gray, systemImage: "list.bullet.rectangle")
                        Text("Sync Details")
                    }
                }

                Button(role: .destructive, action: onDisconnect) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#D70015") ?? .red, systemImage: "xmark.circle")
                        Text("Disconnect")
                    }
                }
                .disabled(isSyncing)
            } else {
                Button(action: onChooseFolder) {
                    HStack(spacing: 12) {
                        SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "folder.badge.plus")
                        Text("Choose Sync Folder")
                    }
                }
                .disabled(isSyncing || isPreparing)
            }

            if let date = persistenceStatus.lastMigrationAttempt {
                LabeledContent("Last Checked", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            if let date = folderStatus.lastSyncAt {
                LabeledContent("Last Synced", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            Button(action: onRetryPreparation) {
                HStack(spacing: 12) {
                    SettingsIconTile(color: Color(hex: "#007AFF") ?? .blue, systemImage: "arrow.clockwise")
                    Text(
                        persistenceStatus.migrationState == .completed ? "Check Metadata" : "Retry Metadata Prep"
                    )
                }
            }
            .disabled(isPreparing || isSyncing)

            if isPreparing || isSyncing {
                HStack(spacing: 12) {
                    ProgressView().accentFill()
                    Text(isSyncing ? "Syncing library…" : "Preparing your library…")
                        .foregroundStyle(.secondary)
                }
            }

            if !folderStatus.lastError.isEmpty {
                Text(folderStatus.lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Kudos stores your library data, including reading history, in the folder you "
                + "choose using the same kind of file as a backup. If the folder is in iCloud "
                + "Drive, Apple shares changes through your personal iCloud account; changes may "
                + "not appear immediately, and Kudos still works offline. Turning off Auto Sync "
                + "stops automatic updates, but Sync Now still works.")
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
                    LabeledContent("Last Synced", value: date.formatted(date: .abbreviated, time: .standard))
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
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sync Details")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
