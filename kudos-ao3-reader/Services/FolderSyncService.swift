import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    /// Posted by SettingsView when a UserDefaults value included in the backup/sync
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

    /// Folds another result's counts into this one — used when a sub-step (e.g. resolving
    /// File-Provider conflict versions, or the legacy-package migration fold) already
    /// accumulated its own `FolderSyncResult` and the caller needs those counts reflected
    /// in its own total rather than discarded. The read/write flags merge as ORs; the
    /// outer-level flags (`missingRemoteFile`, `skippedUnchanged`) stay the caller's.
    mutating func absorb(_ other: FolderSyncResult) {
        restoredWorks += other.restoredWorks
        suppressedQueues += other.suppressedQueues
        revivedQueues += other.revivedQueues
        ambiguousQueueConflicts += other.ambiguousQueueConflicts
        foldedConflicts += other.foldedConflicts
        didReadRemoteFile = didReadRemoteFile || other.didReadRemoteFile
        didWriteRemoteFile = didWriteRemoteFile || other.didWriteRemoteFile
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
    /// The live sync payload: a plain directory of per-record files, so iCloud
    /// Drive uploads/downloads only what actually changed instead of the whole
    /// library. `manifest.json` is the commit point — assets are written before
    /// it, so a manifest always describes files that already exist.
    nonisolated static let syncDirectoryName = "KudosLibrary"
    nonisolated static let manifestFileName = "manifest.json"
    nonisolated static let worksSubdirectoryName = "Works"
    nonisolated static let fontsSubdirectoryName = "Fonts"

    /// The pre-2026 payload: the whole library as one `.kudosbackup` directory
    /// package. Strictly read-only now — folded into local state during
    /// sync-down (so not-yet-updated devices' changes still arrive) but never
    /// written or deleted, which makes the migration idempotent and immune to
    /// interruption.
    nonisolated static let legacySyncFileName = "KudosLibrary.kudosbackup"

    private static let bookmarkDataKey = "folderSyncBookmarkData"
    private static let folderDisplayNameKey = "folderSyncFolderDisplayName"
    private static let folderPathKey = "folderSyncFolderPath"
    private static let lastSyncAtKey = "folderSyncLastSyncAt"
    private static let lastErrorKey = "folderSyncLastError"
    private static let dirtyFlagKey = "hasPendingFolderSyncChanges"
    private static let autoSyncEnabledKey = "folderSyncAutoSyncEnabled"
    private static let lastRestoredRemoteStampKey = "folderSyncLastRestoredRemoteStamp"
    private static let lastRestoredLegacyStampKey = "folderSyncLastRestoredLegacyStamp"
    /// Set when a sync-down couldn't fetch every asset the remote manifest
    /// references (typically not-yet-uploaded iCloud files). While set, the
    /// skip-unchanged stamp is withheld so the next sync-down retries the
    /// fetch even though the manifest itself hasn't changed.
    private static let pendingRemoteAssetsKey = "folderSyncPendingRemoteAssets"

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
        defaults.removeObject(forKey: lastRestoredLegacyStampKey)
        defaults.removeObject(forKey: pendingRemoteAssetsKey)
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
            result.absorb(await foldLegacyPackageIfPresent(
                in: folderURL,
                into: context,
                defaults: defaults
            ))

            let syncDirectoryURL = folderURL.appendingPathComponent(
                syncDirectoryName,
                isDirectory: true
            )
            let manifestURL = syncDirectoryURL.appendingPathComponent(manifestFileName)
            requestDownloadIfNeeded(manifestURL)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                // A legacy-only folder isn't "missing" — its fold above already
                // carried the data; the next sync-up creates the new layout.
                let legacyURL = folderURL.appendingPathComponent(legacySyncFileName)
                if !FileManager.default.fileExists(atPath: legacyURL.path) {
                    result.missingRemoteFile = true
                }
                return
            }
            // Skip the restore when the manifest hasn't changed since the last
            // successful sync-down or this device's own write. Never skip while
            // asset fetches are still outstanding or unresolved conflict
            // versions exist — both can need work without the manifest's
            // modification date moving.
            let remoteStamp = try? await Task.detached {
                try coordinatedContentModificationDate(of: manifestURL)
            }.value
            if let storedStamp = defaults.object(forKey: lastRestoredRemoteStampKey) as? Date,
               let remoteStamp,
               remoteStamp == storedStamp,
               !defaults.bool(forKey: pendingRemoteAssetsKey),
               NSFileVersion.unresolvedConflictVersionsOfItem(at: manifestURL)?.isEmpty ?? true {
                result.skippedUnchanged = true
                return
            }
            let manifest = try await Task.detached {
                try coordinatedReadManifest(from: manifestURL)
            }.value
            // Fetch only assets that are missing or changed relative to local
            // state — unchanged EPUBs never leave disk, unlike the old
            // whole-package read that materialized every blob in memory.
            let assets = await Task.detached {
                readChangedRemoteAssets(in: syncDirectoryURL, manifest: manifest)
            }.value
            result.didReadRemoteFile = true
            let contents = KudosBackupContents(
                manifest: manifest,
                epubFiles: assets.epubFiles,
                fontFiles: assets.fontFiles
            )
            let summary = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            result.absorb(summary)
            result.absorb(try await foldConflictVersions(
                at: manifestURL,
                into: context,
                defaults: defaults,
                read: { url in KudosBackupContents(manifest: try coordinatedReadManifest(from: url)) }
            ))
            defaults.set(assets.missingAssetCount > 0, forKey: pendingRemoteAssetsKey)
            if assets.missingAssetCount == 0, let remoteStamp {
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
        let contents = try makeLocalContents(in: context, defaults: defaults)
        try await withFolderAccess(folderURL) {
            let syncDirectoryURL = folderURL.appendingPathComponent(
                syncDirectoryName,
                isDirectory: true
            )
            try await Task.detached {
                try coordinatedWriteSyncDirectory(contents, to: syncDirectoryURL)
            }.value
            result.didWriteRemoteFile = true
            // Stamp our own manifest write so the next sync-down doesn't fully
            // re-restore it — unless a previous sync-down still has asset
            // fetches outstanding, in which case the stamp stays withheld so
            // those fetches retry.
            let manifestURL = syncDirectoryURL.appendingPathComponent(manifestFileName)
            if !defaults.bool(forKey: pendingRemoteAssetsKey),
               let stamp = try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey])
                   .contentModificationDate {
                defaults.set(stamp, forKey: lastRestoredRemoteStampKey)
            }
        }
        return result
    }

    private static func makeLocalContents(
        in context: ModelContext,
        defaults: UserDefaults
    ) throws -> KudosBackupContents {
        try KudosBackupService.makeDocument(
            works: context.fetch(FetchDescriptor<SavedWork>()),
            bookmarks: context.fetch(FetchDescriptor<Bookmark>()),
            fonts: context.fetch(FetchDescriptor<CustomFont>()),
            collections: context.fetch(FetchDescriptor<WorkCollection>()),
            readingQueues: context.fetch(FetchDescriptor<ReadingQueue>()),
            tombstones: context.fetch(FetchDescriptor<SyncTombstone>()),
            defaults: defaults
        ).contents
    }

    /// Reads the pre-archive `KudosLibrary.kudosbackup` directory package, if
    /// one exists, and folds it into local state. The package is strictly
    /// read-only: not-yet-updated devices keep writing it and their changes
    /// keep flowing in here, while updated devices only ever write the new
    /// directory layout — so an interrupted or repeated migration can never
    /// corrupt or destroy the old data. Failures are logged and swallowed: a
    /// damaged legacy package must not block syncing of the current layout,
    /// and with its stamp unset the fold retries on the next sync anyway.
    private static func foldLegacyPackageIfPresent(
        in folderURL: URL,
        into context: ModelContext,
        defaults: UserDefaults
    ) async -> FolderSyncResult {
        var result = FolderSyncResult()
        let legacyURL = folderURL.appendingPathComponent(legacySyncFileName)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return result }
        requestDownloadIfNeeded(legacyURL)
        let legacyStamp = try? await Task.detached {
            try coordinatedContentModificationDate(of: legacyURL)
        }.value
        if let storedStamp = defaults.object(forKey: lastRestoredLegacyStampKey) as? Date,
           let legacyStamp,
           legacyStamp == storedStamp,
           NSFileVersion.unresolvedConflictVersionsOfItem(at: legacyURL)?.isEmpty ?? true {
            return result
        }
        do {
            let contents = try await Task.detached {
                try coordinatedReadLegacyContents(from: legacyURL)
            }.value
            let summary = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            result.absorb(summary)
            result.didReadRemoteFile = true
            result.absorb(try await foldConflictVersions(
                at: legacyURL,
                into: context,
                defaults: defaults,
                read: coordinatedReadLegacyContents
            ))
            if let legacyStamp {
                defaults.set(legacyStamp, forKey: lastRestoredLegacyStampKey)
            }
        } catch {
            Log.library.notice(
                "Legacy sync package fold failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        return result
    }

    /// Folds every unresolved File-Provider conflict version of a sync file
    /// into `context`, one restore per version. Returns the accumulated
    /// `FolderSyncResult` (not just a bare count) so a caller's own totals —
    /// e.g. the counts `SettingsView` displays — reflect works/queues restored
    /// from a folded conflict instead of silently dropping them.
    private static func foldConflictVersions(
        at url: URL,
        into context: ModelContext,
        defaults: UserDefaults,
        read: @escaping @Sendable (URL) throws -> KudosBackupContents
    ) async throws -> FolderSyncResult {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !versions.isEmpty
        else { return FolderSyncResult() }

        var result = FolderSyncResult()
        for version in versions {
            let conflictURL = version.url
            let contents = try await Task.detached {
                try read(conflictURL)
            }.value
            let summary = try KudosBackupService.restore(contents, into: context, defaults: defaults)
            result.absorb(summary)
            result.foldedConflicts += 1
            version.isResolved = true
        }

        if result.foldedConflicts == versions.count {
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return result
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

/// Reads the legacy directory-package sync payload (read-only migration path).
nonisolated private func coordinatedReadLegacyContents(from url: URL) throws -> KudosBackupContents {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readResult: Result<KudosBackupContents, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        readResult = Result {
            try KudosBackupContents(fileWrapper: FileWrapper(url: coordinatedURL, options: .immediate))
        }
    }
    if let coordinationError { throw coordinationError }
    guard let readResult else { throw FolderSyncError.unreadableSyncFile }
    return try readResult.get()
}

nonisolated private func coordinatedReadData(from url: URL) throws -> Data {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readResult: Result<Data, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        readResult = Result {
            try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
        }
    }
    if let coordinationError { throw coordinationError }
    guard let readResult else { throw FolderSyncError.unreadableSyncFile }
    return try readResult.get()
}

nonisolated private func coordinatedReadManifest(from url: URL) throws -> KudosBackupManifest {
    try KudosBackupContents.decodeManifest(coordinatedReadData(from: url))
}

/// The subset of remote assets a sync-down actually needs to move: files that
/// are missing locally or differ from the local copy. `missingAssetCount`
/// tracks manifest-referenced assets that couldn't be fetched (typically not
/// yet uploaded by the writing device) so the caller can withhold the
/// skip-unchanged stamp and retry them on the next sync.
nonisolated private struct RemoteAssetSelection: Sendable {
    var epubFiles: [UUID: Data] = [:]
    var fontFiles: [String: Data] = [:]
    var missingAssetCount = 0
}

nonisolated private func readChangedRemoteAssets(
    in syncDirectoryURL: URL,
    manifest: KudosBackupManifest
) -> RemoteAssetSelection {
    let fileManager = FileManager.default
    let worksDirectory = syncDirectoryURL.appendingPathComponent(
        FolderSyncService.worksSubdirectoryName,
        isDirectory: true
    )
    let fontsDirectory = syncDirectoryURL.appendingPathComponent(
        FolderSyncService.fontsSubdirectoryName,
        isDirectory: true
    )

    var selection = RemoteAssetSelection()
    for work in manifest.works where work.hasEPUB {
        let remoteURL = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
        let localURL = Storage.workAssetURL(
            identifier: work.assetIdentifier ?? "",
            fallbackID: work.id
        )
        // Genuinely absent remotely (not even an iCloud placeholder): nothing
        // to fetch. The manifest can claim an EPUB that no longer exists
        // anywhere (`hasEPUB` outliving a lost file) — restore records that
        // miss locally, exactly like the old whole-package path, rather than
        // retrying forever. A late upload is picked up when it materializes as
        // a placeholder or on the next manifest change.
        guard remoteAssetExists(remoteURL) else { continue }
        // Size is the change signal: EPUB replacements virtually never keep the
        // exact byte count, and the restore path re-validates whatever arrives.
        let localSize = fileSize(of: localURL)
        if let localSize, let remoteSize = fileSize(of: remoteURL), localSize == remoteSize {
            continue
        }
        requestDownloadIfNeeded(remoteURL)
        if let data = try? coordinatedReadData(from: remoteURL) {
            selection.epubFiles[work.id] = data
        } else {
            // Exists but not readable yet (typically a not-yet-downloaded
            // iCloud file): outstanding, so the skip stamp is withheld and the
            // next sync-down retries the fetch.
            selection.missingAssetCount += 1
        }
    }
    for font in manifest.fonts where KudosBackupContents.isSafeFileName(font.fileName) {
        // Font files are immutable once imported (UUID-based names), so only
        // locally-missing ones ever need fetching.
        let localURL = Storage.fontsDirectory.appendingPathComponent(font.fileName)
        guard !fileManager.fileExists(atPath: localURL.path) else { continue }
        let remoteURL = fontsDirectory.appendingPathComponent(font.fileName)
        guard remoteAssetExists(remoteURL) else { continue }
        requestDownloadIfNeeded(remoteURL)
        if let data = try? coordinatedReadData(from: remoteURL) {
            selection.fontFiles[font.fileName] = data
        } else {
            selection.missingAssetCount += 1
        }
    }
    return selection
}

/// Whether a remote asset exists in any form — as a materialized file or as a
/// legacy-style iCloud placeholder (".name.icloud") standing in for content
/// that hasn't downloaded yet.
nonisolated private func remoteAssetExists(_ url: URL) -> Bool {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: url.path) { return true }
    let placeholder = url.deletingLastPathComponent()
        .appendingPathComponent(".\(url.lastPathComponent).icloud")
    return fileManager.fileExists(atPath: placeholder.path)
}

nonisolated private func coordinatedWriteSyncDirectory(
    _ contents: KudosBackupContents,
    to directoryURL: URL
) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeResult: Result<Void, Error>?
    coordinator.coordinate(
        writingItemAt: directoryURL,
        options: .forMerging,
        error: &coordinationError
    ) { coordinatedURL in
        writeResult = Result {
            try writeSyncDirectoryContents(contents, at: coordinatedURL)
        }
    }
    if let coordinationError { throw coordinationError }
    try writeResult?.get()
}

nonisolated private func writeSyncDirectoryContents(
    _ contents: KudosBackupContents,
    at directoryURL: URL
) throws {
    let fileManager = FileManager.default
    let worksDirectory = directoryURL.appendingPathComponent(
        FolderSyncService.worksSubdirectoryName,
        isDirectory: true
    )
    let fontsDirectory = directoryURL.appendingPathComponent(
        FolderSyncService.fontsSubdirectoryName,
        isDirectory: true
    )
    try fileManager.createDirectory(at: worksDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)

    // Assets first, manifest last: the manifest is the commit point, so a
    // manifest never references an asset file that wasn't already written.
    // Each write is individually atomic and unchanged files are left alone
    // entirely (same inode), which is what lets iCloud Drive upload only the
    // delta. An interruption leaves the previous manifest — and therefore the
    // previous consistent view — in place.
    for (id, data) in contents.epubFiles {
        try writeIfChanged(data, to: worksDirectory.appendingPathComponent("\(id.uuidString).epub"))
    }
    for (fileName, data) in contents.fontFiles
    where KudosBackupContents.isSafeFileName(fileName) {
        try writeIfChanged(data, to: fontsDirectory.appendingPathComponent(fileName))
    }

    try contents.manifestData().write(
        to: directoryURL.appendingPathComponent(FolderSyncService.manifestFileName),
        options: .atomic
    )

    // After the commit point: drop asset files no manifest record references
    // anymore (permanent deletions). Best-effort — a failure is retried by any
    // later sync-up. A work still listed in the manifest keeps its remote EPUB
    // even when this device holds no local copy, so one device can never
    // discard an EPUB another device preserved.
    removeOrphans(
        in: worksDirectory,
        keeping: Set(contents.manifest.works.map { "\($0.id.uuidString).epub" })
    )
    removeOrphans(
        in: fontsDirectory,
        keeping: Set(contents.manifest.fonts.map(\.fileName))
    )
}

nonisolated private func writeIfChanged(_ data: Data, to url: URL) throws {
    if let existingSize = fileSize(of: url), existingSize == data.count { return }
    try data.write(to: url, options: .atomic)
}

nonisolated private func fileSize(of url: URL) -> Int? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
}

nonisolated private func removeOrphans(in directory: URL, keeping expected: Set<String>) {
    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
    for name in names {
        // Map iCloud placeholder names (".X.icloud") back to their real name so
        // a not-yet-downloaded file is never mistaken for an orphan.
        var realName = name
        if realName.hasPrefix("."), realName.hasSuffix(".icloud") {
            realName = String(realName.dropFirst().dropLast(".icloud".count))
        }
        guard !realName.hasPrefix(".") else { continue } // other hidden/system files
        guard !expected.contains(realName) else { continue }
        try? fileManager.removeItem(at: directory.appendingPathComponent(name))
    }
}

nonisolated private func requestDownloadIfNeeded(_ url: URL) {
    let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    guard let values = try? url.resourceValues(forKeys: keys),
          values.isUbiquitousItem == true,
          values.ubiquitousItemDownloadingStatus != .current
    else { return }
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
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
