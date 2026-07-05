import Foundation
import OSLog
import SwiftData

nonisolated enum PersistenceMigrationState: String, Codable, CaseIterable {
    case notStarted
    case inProgress
    case metadataMigrated
    case assetsQueuedOrMigrated
    case completed
    case failedRecoverable

    var title: String {
        switch self {
        case .notStarted: "Not Started"
        case .inProgress: "Preparing"
        case .metadataMigrated: "Metadata Ready"
        case .assetsQueuedOrMigrated: "Assets Checked"
        case .completed: "Ready"
        case .failedRecoverable: "Needs Retry"
        }
    }
}

struct PersistenceStatusSnapshot: Equatable {
    var migrationState: PersistenceMigrationState
    var lastMigrationAttempt: Date?
    var lastError: String

    var detail: String {
        if !lastError.isEmpty { return lastError }
        switch migrationState {
        case .completed:
            return "Local metadata is ready for folder sync."
        case .failedRecoverable:
            return "The local sync-prep migration can be retried safely."
        default:
            return "Preparing local metadata for folder sync."
        }
    }
}

enum PersistenceStatusStore {
    static let migrationStateKey = "persistenceMigrationState"
    static let lastMigrationAttemptKey = "persistenceMigrationLastAttempt"
    static let lastMigrationErrorKey = "persistenceMigrationLastError"

    static func snapshot(defaults: UserDefaults = .standard) -> PersistenceStatusSnapshot {
        let raw = defaults.string(forKey: migrationStateKey) ?? PersistenceMigrationState.notStarted.rawValue
        return PersistenceStatusSnapshot(
            migrationState: PersistenceMigrationState(rawValue: raw) ?? .notStarted,
            lastMigrationAttempt: defaults.object(forKey: lastMigrationAttemptKey) as? Date,
            lastError: defaults.string(forKey: lastMigrationErrorKey) ?? ""
        )
    }

    static func setState(
        _ state: PersistenceMigrationState,
        defaults: UserDefaults = .standard,
        error: String = ""
    ) {
        defaults.set(state.rawValue, forKey: migrationStateKey)
        defaults.set(Date(), forKey: lastMigrationAttemptKey)
        defaults.set(error, forKey: lastMigrationErrorKey)
    }
}

nonisolated enum PersistenceOperationKind: String, Equatable {
    case migration
    case backupImport
    case folderSync

    var title: String {
        switch self {
        case .migration: "metadata preparation"
        case .backupImport: "backup import"
        case .folderSync: "folder sync"
        }
    }
}

@MainActor
enum PersistenceOperationGate {
    private static var activeOperation: PersistenceOperationKind?

    static var active: PersistenceOperationKind? {
        activeOperation
    }

    static func begin(_ operation: PersistenceOperationKind) -> Bool {
        guard activeOperation == nil else { return false }
        activeOperation = operation
        return true
    }

    static func end(_ operation: PersistenceOperationKind) {
        if activeOperation == operation {
            activeOperation = nil
        }
    }
}

enum PersistenceDevice {
    private static let deviceIDKey = "persistenceSyncDeviceID"

    static func currentID(defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: deviceIDKey), !id.isEmpty {
            return id
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: deviceIDKey)
        return id
    }
}

@MainActor
enum PersistenceMigrationService {
    /// Yield to the run loop every N records so a large library doesn't freeze the UI
    /// for the whole migration and a caller's loading indicator gets a chance to render.
    private static let yieldInterval = 50

    @discardableResult
    static func runIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) async -> PersistenceMigrationState {
        let current = PersistenceStatusStore.snapshot(defaults: defaults).migrationState
        guard current != .completed else { return current }
        return await run(in: context, defaults: defaults)
    }

    @discardableResult
    static func run(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) async -> PersistenceMigrationState {
        guard PersistenceOperationGate.begin(.migration) else {
            return PersistenceStatusStore.snapshot(defaults: defaults).migrationState
        }
        defer { PersistenceOperationGate.end(.migration) }
        do {
            PersistenceStatusStore.setState(.inProgress, defaults: defaults)
            try await migrateMetadata(in: context, stage: "metadata migration")
            PersistenceStatusStore.setState(.metadataMigrated, defaults: defaults)
            try await reconcileAssets(in: context, stage: "asset reconciliation")
            PersistenceStatusStore.setState(.assetsQueuedOrMigrated, defaults: defaults)
            try context.save()
            PersistenceStatusStore.setState(.completed, defaults: defaults)
            return .completed
        } catch let error as MigrationStageError {
            PersistenceStatusStore.setState(.failedRecoverable, defaults: defaults, error: error.message)
            let stage = error.stage
            let message = error.message
            Log.library.error("Persistence migration failed (\(stage, privacy: .public)): \(message, privacy: .public)")
            return .failedRecoverable
        } catch {
            let message = error.localizedDescription
            PersistenceStatusStore.setState(.failedRecoverable, defaults: defaults, error: message)
            Log.library.error("Persistence migration failed while saving: \(message, privacy: .public)")
            return .failedRecoverable
        }
    }

    private struct MigrationStageError: Error {
        let stage: String
        let message: String
    }

    // Migration touches every sync-ready model type in one idempotent pass.
    // swiftlint:disable:next cyclomatic_complexity
    private static func migrateMetadata(in context: ModelContext, stage: String) async throws {
        let now = Date()
        do {
            var processed = 0
            for work in try context.fetch(FetchDescriptor<SavedWork>()) {
                // The fetched array is a snapshot; a record deleted during a yield has
                // no context anymore and must not be touched.
                guard work.modelContext != nil else { continue }
                if work.assetIdentifier.isEmpty {
                    work.assetIdentifier = Storage.defaultEPUBAssetIdentifier(for: work.id)
                }
                if work.ao3WorkID == nil {
                    work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
                }
                if work.createdAt > work.dateAdded {
                    work.createdAt = work.dateAdded
                }
                if work.lastModifiedAt < work.createdAt {
                    work.lastModifiedAt = max(work.lastReadDate ?? work.createdAt, work.createdAt)
                }
                if work.hasStartedReading, work.progressModifiedAt == nil {
                    work.progressModifiedAt = work.lastReadDate ?? work.lastModifiedAt
                }
                if work.syncStatus == .localOnly {
                    work.syncStatus = .pending
                }
                processed += 1
                if processed.isMultiple(of: yieldInterval) { await Task.yield() }
            }

            for collection in try context.fetch(FetchDescriptor<WorkCollection>()) {
                guard collection.modelContext != nil else { continue }
                if collection.createdAt > collection.dateAdded {
                    collection.createdAt = collection.dateAdded
                }
                if collection.lastModifiedAt < collection.createdAt {
                    collection.lastModifiedAt = collection.createdAt
                }
                if collection.syncStatus == .localOnly {
                    collection.syncStatus = .pending
                }
                processed += 1
                if processed.isMultiple(of: yieldInterval) { await Task.yield() }
            }

            for queue in try context.fetch(FetchDescriptor<ReadingQueue>()) {
                guard queue.modelContext != nil else { continue }
                if queue.dateUpdated < queue.dateCreated {
                    queue.dateUpdated = queue.dateCreated
                }
                let newestMembershipChange = queue.memberships
                    .map(\.lastModifiedAt)
                    .max()
                let membershipChangedAt = max(
                    queue.lastMembershipChangedAt,
                    newestMembershipChange ?? queue.dateCreated
                )
                if membershipChangedAt > queue.lastMembershipChangedAt {
                    queue.lastMembershipChangedAt = membershipChangedAt
                }
                if queue.syncStatus == .localOnly {
                    queue.syncStatus = .pending
                }
                processed += 1
                if processed.isMultiple(of: yieldInterval) { await Task.yield() }
            }

            for membership in try context.fetch(FetchDescriptor<ReadingQueueMembership>()) {
                guard membership.modelContext != nil else { continue }
                if membership.lastModifiedAt < membership.queuedAt {
                    membership.lastModifiedAt = membership.queuedAt
                }
                if membership.syncStatus == .localOnly {
                    membership.syncStatus = .pending
                }
                processed += 1
                if processed.isMultiple(of: yieldInterval) { await Task.yield() }
            }
        } catch {
            throw MigrationStageError(stage: stage, message: error.localizedDescription)
        }

        Log.library.info(
            "Persistence metadata migration checked at \(now.formatted(.iso8601), privacy: .public)"
        )
    }

    private static func reconcileAssets(in context: ModelContext, stage: String) async throws {
        do {
            var processed = 0
            for work in try context.fetch(FetchDescriptor<SavedWork>()) {
                processed += 1
                if processed.isMultiple(of: yieldInterval) { await Task.yield() }
                guard work.modelContext != nil, work.hasEPUB else { continue }
                if FileManager.default.fileExists(atPath: work.fileURL.path) {
                    continue
                }
                work.hasEPUB = false
                work.syncStatus = .assetsMissing
                if work.epubPreservationStatus == .preserved {
                    work.epubPreservationStatus = .missingFile
                }
                Log.library.notice(
                    "EPUB asset missing for work \(work.id.uuidString, privacy: .public)"
                )
            }
        } catch {
            throw MigrationStageError(stage: stage, message: error.localizedDescription)
        }
    }
}

@MainActor
enum SyncTombstones {
    static func recordDeletion(of work: SavedWork, in context: ModelContext) {
        context.insert(SyncTombstone(
            recordID: work.id,
            recordType: .savedWork,
            sourceURL: work.sourceURL,
            ao3WorkID: work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL),
            deletedOnDeviceID: PersistenceDevice.currentID(),
            deletionReason: "workDeleted"
        ))
    }

    static func recordDeletion(of collection: WorkCollection, in context: ModelContext) {
        context.insert(SyncTombstone(
            recordID: collection.id,
            recordType: .workCollection,
            deletedOnDeviceID: PersistenceDevice.currentID(),
            deletionReason: "collectionDeleted"
        ))
    }

    static func recordDeletion(of queue: ReadingQueue, in context: ModelContext) {
        context.insert(SyncTombstone(
            recordID: queue.id,
            recordType: .readingQueue,
            deletedOnDeviceID: PersistenceDevice.currentID(),
            deletionReason: "queueDeleted"
        ))
    }

    static func recordDeletion(of membership: ReadingQueueMembership, in context: ModelContext) {
        context.insert(SyncTombstone(
            recordID: membership.id,
            recordType: .readingQueueMembership,
            deletedOnDeviceID: PersistenceDevice.currentID(),
            deletionReason: "queueMembershipRemoved"
        ))
    }

    /// Records that `work` was explicitly removed from `collection`, so a stale sync
    /// file (an older manifest that still lists this work in the collection) can't
    /// silently re-add it on the next merge — the same class of bug tombstones already
    /// prevent for deleted works/queues/queue memberships.
    static func recordCollectionMembershipRemoval(
        work: SavedWork,
        collection: WorkCollection,
        in context: ModelContext
    ) {
        context.insert(SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(collectionID: collection.id, workID: work.id),
            recordType: .workCollectionMembership,
            deletedOnDeviceID: PersistenceDevice.currentID(),
            deletionReason: "collectionMembershipRemoved"
        ))
    }
}

nonisolated enum SyncMerge {
    enum TombstoneResolution: Equatable {
        case noTombstone
        case suppressStaleData
        case reviveNewerData
        case preserveAmbiguous
    }

    struct ProgressSnapshot: Equatable {
        var lastSpineIndex: Int
        var lastScrollFraction: Double
        var readiumLocator: String
        var lastReadDate: Date?
        var modifiedAt: Date?
    }

    static func shouldApplyIncoming(localModifiedAt: Date?, incomingModifiedAt: Date?) -> Bool {
        guard let incomingModifiedAt else { return false }
        guard let localModifiedAt else { return true }
        return incomingModifiedAt >= localModifiedAt
    }

    // Deliberately does NOT take a "restore/import/export wall-clock time" parameter:
    // when a backup file was written or imported has no bearing on whether the
    // queue's own content changed, and folding it in here previously let a
    // content-stale backup revive an explicitly-deleted queue just because the file
    // itself happened to be newer than the tombstone.
    static func effectiveQueueModifiedAt(
        queueUpdatedAt: Date?,
        lastMembershipChangedAt: Date?,
        membershipModifiedAts: [Date]
    ) -> Date? {
        ([queueUpdatedAt, lastMembershipChangedAt].compactMap { $0 }
            + membershipModifiedAts).max()
    }

    @MainActor
    static func effectiveQueueModifiedAt(_ queue: ReadingQueue) -> Date {
        effectiveQueueModifiedAt(
            queueUpdatedAt: queue.dateUpdated,
            lastMembershipChangedAt: queue.lastMembershipChangedAt,
            membershipModifiedAts: queue.memberships.map(\.lastModifiedAt)
        ) ?? queue.dateUpdated
    }

    static func tombstoneResolution(
        incomingModifiedAt: Date?,
        tombstoneDeletedAt: Date?
    ) -> TombstoneResolution {
        guard let tombstoneDeletedAt else { return .noTombstone }
        guard let incomingModifiedAt else { return .preserveAmbiguous }
        return incomingModifiedAt > tombstoneDeletedAt ? .reviveNewerData : .suppressStaleData
    }

    @MainActor
    static func applyProgress(_ incoming: ProgressSnapshot, to work: SavedWork) {
        let localModifiedAt = work.progressModifiedAt ?? work.lastReadDate
        let incomingModifiedAt = incoming.modifiedAt ?? incoming.lastReadDate
        let incomingHasProgress = incoming.lastReadDate != nil
            || incoming.lastSpineIndex > 0
            || incoming.lastScrollFraction > 0
            || !incoming.readiumLocator.isEmpty
        guard incomingHasProgress else { return }
        if work.hasStartedReading {
            guard shouldApplyIncoming(
                localModifiedAt: localModifiedAt,
                incomingModifiedAt: incomingModifiedAt
            ) else { return }
        }

        work.lastSpineIndex = incoming.lastSpineIndex
        work.lastScrollFraction = incoming.lastScrollFraction
        work.readiumLocator = incoming.readiumLocator
        work.lastReadDate = incoming.lastReadDate
        work.progressModifiedAt = incomingModifiedAt
        work.markModified(work.progressModifiedAt ?? Date())
    }

    @MainActor
    static func deterministicMembershipOrder(_ memberships: [ReadingQueueMembership]) -> [ReadingQueueMembership] {
        memberships.sorted {
            if $0.sortOrderInQueue != $1.sortOrderInQueue {
                return $0.sortOrderInQueue < $1.sortOrderInQueue
            }
            if $0.queuedAt != $1.queuedAt {
                return $0.queuedAt < $1.queuedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
