import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    /// Posted by SettingsView when a UserDefaults value included in the `.kudosbackup`
    /// manifest (reader/privacy preferences) changes, so ContentView's folder-sync
    /// lifecycle — which only observes SwiftData @Query state directly — knows to mark
    /// the sync folder dirty too.
    static let kudosSyncRelevantSettingChanged = Notification.Name("kudosSyncRelevantSettingChanged")
}

struct FolderSyncSnapshot: Equatable {
    var isConnected: Bool
    var folderDisplayName: String
    var folderPath: String
    var lastSyncAt: Date?
    var lastError: String
    var isDirty: Bool
    var autoSyncEnabled: Bool
}

struct FolderSyncResult: Equatable {
    var didReadRemoteFile = false
    var didWriteRemoteFile = false
    var missingRemoteFile = false
    var skippedUnchanged = false
    var foldedConflicts = 0
    var restoredWorks = 0
    var suppressedQueues = 0
    var revivedQueues = 0
    var ambiguousQueueConflicts = 0

    mutating func absorb(_ summary: KudosBackupRestoreSummary) {
        restoredWorks += summary.works
        suppressedQueues += summary.suppressedQueues
        revivedQueues += summary.revivedQueues
        ambiguousQueueConflicts += summary.ambiguousQueueConflicts
    }
}

enum FolderSyncError: LocalizedError, Equatable {
    case notConnected
    case couldNotAccessFolder
    case operationInProgress(String)
    case unreadableSyncFile

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Choose a Library Sync Folder first."
        case .couldNotAccessFolder:
            "Kudos couldn't access the selected sync folder. Choose it again in Settings."
        case let .operationInProgress(operation):
            "Kudos is already running \(operation). Try again when it finishes."
        case .unreadableSyncFile:
            "Kudos couldn't read the Library Sync Folder backup file."
        }
    }
}

@MainActor
enum FolderSyncService {
    static let syncFileName = "KudosLibrary.kudosbackup"

    private static let bookmarkDataKey = "folderSyncBookmarkData"
    private static let folderDisplayNameKey = "folderSyncFolderDisplayName"
    private static let folderPathKey = "folderSyncFolderPath"
    private static let lastSyncAtKey = "folderSyncLastSyncAt"
    private static let lastErrorKey = "folderSyncLastError"
    private static let dirtyFlagKey = "hasPendingFolderSyncChanges"
    private static let autoSyncEnabledKey = "folderSyncAutoSyncEnabled"
    private static let lastRestoredRemoteStampKey = "folderSyncLastRestoredRemoteStamp"

    static func snapshot(defaults: UserDefaults = .standard) -> FolderSyncSnapshot {
        let bookmarkData = defaults.data(forKey: bookmarkDataKey)
        return FolderSyncSnapshot(
            isConnected: bookmarkData?.isEmpty == false,
            folderDisplayName: defaults.string(forKey: folderDisplayNameKey) ?? "",
            folderPath: defaults.string(forKey: folderPathKey) ?? "",
            lastSyncAt: defaults.object(forKey: lastSyncAtKey) as? Date,
            lastError: defaults.string(forKey: lastErrorKey) ?? "",
            isDirty: defaults.bool(forKey: dirtyFlagKey),
            // Defaults to on: once a folder is connected, automatic sync is the
            // expected experience unless the user explicitly turns it off.
            autoSyncEnabled: defaults.object(forKey: autoSyncEnabledKey) == nil
                ? true
                : defaults.bool(forKey: autoSyncEnabledKey)
        )
    }

    /// Marks local state as having changes not yet written to the sync folder.
    /// Durable (UserDefaults-backed) so a change survives a force-quit before the
    /// debounced sync-up fires — the next launch/foreground/background trigger will
    /// still attempt to catch it up instead of silently losing it.
    static func markDirty(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dirtyFlagKey)
    }

    static func setAutoSyncEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: autoSyncEnabledKey)
    }

    static func connect(to folderURL: URL, defaults: UserDefaults = .standard) throws {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        let bookmark = try bookmarkData(for: folderURL)
        defaults.set(bookmark, forKey: bookmarkDataKey)
        defaults.set(folderURL.lastPathComponent, forKey: folderDisplayNameKey)
        defaults.set(folderURL.path, forKey: folderPathKey)
        defaults.set("", forKey: lastErrorKey)
    }

    static func disconnect(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkDataKey)
        defaults.removeObject(forKey: folderDisplayNameKey)
        defaults.removeObject(forKey: folderPathKey)
        defaults.removeObject(forKey: lastSyncAtKey)
        defaults.removeObject(forKey: lastErrorKey)
        defaults.removeObject(forKey: dirtyFlagKey)
        defaults.removeObject(forKey: lastRestoredRemoteStampKey)
    }

    @discardableResult
    static func syncNow(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) async throws -> FolderSyncResult {
        try await runGuarded(defaults: defaults) {
            var result = try await performSyncDown(in: context, defaults: defaults)
            let upResult = try await performSyncUp(in: context, defaults: defaults)
            result.didWriteRemoteFile = upResult.didWriteRemoteFile
            recordSuccess(defaults: defaults)
            defaults.set(false, forKey: dirtyFlagKey)
            return result
        }
    }

    @discardableResult
    static func syncDown(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) async throws -> FolderSyncResult {
        guard snapshot(defaults: defaults).isConnected else { return FolderSyncResult() }
        return try await runGuarded(defaults: defaults) {
            let result = try await performSyncDown(in: context, defaults: defaults)
            recordSuccess(defaults: defaults)
            return result
        }
    }

    @discardableResult
    static func syncUp(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) async throws -> FolderSyncResult {
        guard snapshot(defaults: defaults).isConnected else { return FolderSyncResult() }
        return try await runGuarded(defaults: defaults) {
            let result = try await performSyncUp(in: context, defaults: defaults)
            recordSuccess(defaults: defaults)
            defaults.set(false, forKey: dirtyFlagKey)
            return result
        }
    }

    @discardableResult
    static func foldConflictContents(
        _ conflictContents: [KudosBackupContents],
        into context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> FolderSyncResult {
        var result = FolderSyncResult()
        for contents in conflictContents {
            let summary = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            result.absorb(summary)
            result.foldedConflicts += 1
        }
        return result
    }

    private static func runGuarded(
        defaults: UserDefaults,
        operation: @MainActor () async throws -> FolderSyncResult
    ) async throws -> FolderSyncResult {
        do {
            guard PersistenceOperationGate.begin(.folderSync) else {
                throw FolderSyncError.operationInProgress(
                    PersistenceOperationGate.active?.title ?? "another persistence operation"
                )
            }
            defer { PersistenceOperationGate.end(.folderSync) }
            return try await operation()
        } catch {
            // Record even a gate-rejection, not just "real" failures — otherwise a sync
            // that silently loses a contention race leaves no trace anywhere the user
            // or a developer could see, unlike every other failure mode.
            recordError(error, defaults: defaults)
            throw error
        }
    }

    private static func performSyncDown(
        in context: ModelContext,
        defaults: UserDefaults
    ) async throws -> FolderSyncResult {
        var result = FolderSyncResult()
        let folderURL = try resolveFolder(defaults: defaults)
        try await withFolderAccess(folderURL) {
            let syncFileURL = folderURL.appendingPathComponent(syncFileName)
            guard FileManager.default.fileExists(atPath: syncFileURL.path) else {
                result.missingRemoteFile = true
                return
            }
            requestDownloadIfNeeded(syncFileURL)
            // A full restore loads every EPUB blob into memory, so skip it when the
            // package hasn't changed since the last successful restore or this device's
            // own write. Never skip while unresolved conflict versions exist — those can
            // arrive without the main file's modification date moving.
            let remoteStamp = try? await Task.detached {
                try coordinatedContentModificationDate(of: syncFileURL)
            }.value
            if let storedStamp = defaults.object(forKey: lastRestoredRemoteStampKey) as? Date,
               let remoteStamp,
               remoteStamp == storedStamp,
               NSFileVersion.unresolvedConflictVersionsOfItem(at: syncFileURL)?.isEmpty ?? true {
                result.skippedUnchanged = true
                return
            }
            let contents = try await Task.detached {
                try coordinatedReadContents(from: syncFileURL)
            }.value
            result.didReadRemoteFile = true
            let summary = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            result.absorb(summary)
            result.foldedConflicts += try await foldFileProviderConflicts(
                at: syncFileURL,
                into: context,
                defaults: defaults
            )
            if let remoteStamp {
                defaults.set(remoteStamp, forKey: lastRestoredRemoteStampKey)
            } else {
                defaults.removeObject(forKey: lastRestoredRemoteStampKey)
            }
        }
        return result
    }

    private static func performSyncUp(
        in context: ModelContext,
        defaults: UserDefaults
    ) async throws -> FolderSyncResult {
        var result = FolderSyncResult()
        let folderURL = try resolveFolder(defaults: defaults)
        let document = try makeLocalDocument(in: context, defaults: defaults)
        try await withFolderAccess(folderURL) {
            let syncFileURL = folderURL.appendingPathComponent(syncFileName)
            let contents = document.contents
            try await Task.detached {
                try coordinatedWriteContents(contents, to: syncFileURL)
            }.value
            result.didWriteRemoteFile = true
            // Stamp our own write so the next sync-down doesn't fully re-restore it.
            if let stamp = try? syncFileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate {
                defaults.set(stamp, forKey: lastRestoredRemoteStampKey)
            }
        }
        return result
    }

    private static func makeLocalDocument(
        in context: ModelContext,
        defaults: UserDefaults
    ) throws -> KudosBackupDocument {
        try KudosBackupService.makeDocument(
            works: context.fetch(FetchDescriptor<SavedWork>()),
            bookmarks: context.fetch(FetchDescriptor<Bookmark>()),
            fonts: context.fetch(FetchDescriptor<CustomFont>()),
            collections: context.fetch(FetchDescriptor<WorkCollection>()),
            readingQueues: context.fetch(FetchDescriptor<ReadingQueue>()),
            tombstones: context.fetch(FetchDescriptor<SyncTombstone>()),
            defaults: defaults
        )
    }

    private static func foldFileProviderConflicts(
        at syncFileURL: URL,
        into context: ModelContext,
        defaults: UserDefaults
    ) async throws -> Int {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: syncFileURL),
              !versions.isEmpty
        else { return 0 }

        var folded = 0
        for version in versions {
            let conflictURL = version.url
            let contents = try await Task.detached {
                try coordinatedReadContents(from: conflictURL)
            }.value
            _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            version.isResolved = true
            folded += 1
        }

        if folded == versions.count {
            try? NSFileVersion.removeOtherVersionsOfItem(at: syncFileURL)
        }
        return folded
    }

    private static func resolveFolder(defaults: UserDefaults) throws -> URL {
        guard let storedBookmarkData = defaults.data(forKey: bookmarkDataKey),
              !storedBookmarkData.isEmpty
        else {
            throw FolderSyncError.notConnected
        }
        var isStale = false
        let url = try resolveBookmarkData(storedBookmarkData, isStale: &isStale)
        if isStale {
            defaults.set(try bookmarkData(for: url), forKey: bookmarkDataKey)
            defaults.set(url.lastPathComponent, forKey: folderDisplayNameKey)
            defaults.set(url.path, forKey: folderPathKey)
        }
        return url
    }

    private static func withFolderAccess(
        _ folderURL: URL,
        operation: @MainActor () async throws -> Void
    ) async throws {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        guard accessed || FileManager.default.isReadableFile(atPath: folderURL.path) else {
            throw FolderSyncError.couldNotAccessFolder
        }
        try await operation()
    }

    private static func recordSuccess(defaults: UserDefaults) {
        defaults.set(Date(), forKey: lastSyncAtKey)
        defaults.set("", forKey: lastErrorKey)
    }

    private static func recordError(_ error: Error, defaults: UserDefaults) {
        let message = error.localizedDescription
        defaults.set(message, forKey: lastErrorKey)
        Log.library.error("Library folder sync failed: \(message, privacy: .public)")
    }

    private static func requestDownloadIfNeeded(_ url: URL) {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true,
              values.ubiquitousItemDownloadingStatus != .current
        else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        // iOS marks `.withSecurityScope` unavailable for bookmarks; the resolved
        // URL is still accessed with `startAccessingSecurityScopedResource()`.
        #if os(macOS)
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    private static func resolveBookmarkData(_ data: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
    }
}

nonisolated private func coordinatedReadContents(from url: URL) throws -> KudosBackupContents {
    let wrapper = try coordinatedReadFileWrapper(from: url)
    return try KudosBackupContents(fileWrapper: wrapper)
}

nonisolated private func coordinatedReadFileWrapper(from url: URL) throws -> FileWrapper {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readResult: Result<FileWrapper, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        readResult = Result {
            try FileWrapper(url: coordinatedURL, options: .immediate)
        }
    }
    if let coordinationError { throw coordinationError }
    guard let readResult else { throw FolderSyncError.unreadableSyncFile }
    return try readResult.get()
}

nonisolated private func coordinatedWriteContents(_ contents: KudosBackupContents, to url: URL) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeResult: Result<Void, Error>?
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
        writeResult = Result {
            let wrapper = try contents.fileWrapper()
            // Stage into a temp location and swap it in, so a failed write can never
            // leave the destination missing — the existing package must survive.
            // itemReplacementDirectory keeps the staging area on the destination's
            // own volume; a global temp dir would make the swap a cross-volume move
            // (EXDEV) for sync folders on external drives.
            let stagingDirectory = (try? FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: coordinatedURL,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            let tempURL = stagingDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try wrapper.write(to: tempURL, options: .atomic, originalContentsURL: nil)
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    _ = try FileManager.default.replaceItemAt(
                        coordinatedURL,
                        withItemAt: tempURL,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: coordinatedURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
        }
    }
    if let coordinationError { throw coordinationError }
    try writeResult?.get()
}

nonisolated private func coordinatedContentModificationDate(of url: URL) throws -> Date? {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var dateResult: Result<Date?, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        dateResult = Result {
            try coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        }
    }
    if let coordinationError { throw coordinationError }
    guard let dateResult else { throw FolderSyncError.unreadableSyncFile }
    return try dateResult.get()
}
