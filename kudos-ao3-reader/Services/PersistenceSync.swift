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

nonisolated enum ICloudAccountStatus: Equatable {
    case available
    case unavailable

    var title: String {
        switch self {
        case .available: "iCloud Available"
        case .unavailable: "iCloud Unavailable"
        }
    }
}

struct PersistenceStatusSnapshot: Equatable {
    var migrationState: PersistenceMigrationState
    var iCloudAccountStatus: ICloudAccountStatus
    var lastMigrationAttempt: Date?
    var lastError: String

    var detail: String {
        if !lastError.isEmpty { return lastError }
        switch (migrationState, iCloudAccountStatus) {
        case (.completed, .available):
            return "Local metadata is ready for private iCloud sync."
        case (.completed, .unavailable):
            return "Local metadata is ready. Sign in to iCloud on this device to sync later."
        case (.failedRecoverable, _):
            return "The local sync-prep migration can be retried safely."
        default:
            return "Preparing local metadata for future iCloud sync."
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
            iCloudAccountStatus: FileManager.default.ubiquityIdentityToken == nil ? .unavailable : .available,
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

@MainActor
enum PersistenceMigrationService {
    @discardableResult
    static func runIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> PersistenceMigrationState {
        let current = PersistenceStatusStore.snapshot(defaults: defaults).migrationState
        guard current != .completed else { return current }
        return run(in: context, defaults: defaults)
    }

    @discardableResult
    static func run(
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> PersistenceMigrationState {
        do {
            PersistenceStatusStore.setState(.inProgress, defaults: defaults)
            try migrateMetadata(in: context)
            PersistenceStatusStore.setState(.metadataMigrated, defaults: defaults)
            try reconcileAssets(in: context)
            PersistenceStatusStore.setState(.assetsQueuedOrMigrated, defaults: defaults)
            try context.save()
            PersistenceStatusStore.setState(.completed, defaults: defaults)
            return .completed
        } catch {
            let message = error.localizedDescription
            PersistenceStatusStore.setState(.failedRecoverable, defaults: defaults, error: message)
            Log.library.error("Persistence migration failed: \(message, privacy: .public)")
            return .failedRecoverable
        }
    }

    // Migration touches every sync-ready model type in one idempotent pass.
    // swiftlint:disable:next cyclomatic_complexity
    private static func migrateMetadata(in context: ModelContext) throws {
        let now = Date()
        for work in try context.fetch(FetchDescriptor<SavedWork>()) {
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
        }

        for collection in try context.fetch(FetchDescriptor<WorkCollection>()) {
            if collection.createdAt > collection.dateAdded {
                collection.createdAt = collection.dateAdded
            }
            if collection.lastModifiedAt < collection.createdAt {
                collection.lastModifiedAt = collection.createdAt
            }
            if collection.syncStatus == .localOnly {
                collection.syncStatus = .pending
            }
        }

        for queue in try context.fetch(FetchDescriptor<ReadingQueue>()) {
            if queue.dateUpdated < queue.dateCreated {
                queue.dateUpdated = queue.dateCreated
            }
            if queue.syncStatus == .localOnly {
                queue.syncStatus = .pending
            }
        }

        for membership in try context.fetch(FetchDescriptor<ReadingQueueMembership>()) {
            if membership.lastModifiedAt < membership.queuedAt {
                membership.lastModifiedAt = membership.queuedAt
            }
            if membership.syncStatus == .localOnly {
                membership.syncStatus = .pending
            }
        }

        Log.library.info(
            "Persistence metadata migration checked at \(now.formatted(.iso8601), privacy: .public)"
        )
    }

    private static func reconcileAssets(in context: ModelContext) throws {
        for work in try context.fetch(FetchDescriptor<SavedWork>()) {
            guard work.hasEPUB else { continue }
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
    }
}

@MainActor
enum SyncTombstones {
    static func recordDeletion(of work: SavedWork, in context: ModelContext) {
        context.insert(SyncTombstone(
            recordID: work.id,
            recordType: .savedWork,
            sourceURL: work.sourceURL,
            ao3WorkID: work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
        ))
    }

    static func recordDeletion(of collection: WorkCollection, in context: ModelContext) {
        context.insert(SyncTombstone(recordID: collection.id, recordType: .workCollection))
    }

    static func recordDeletion(of queue: ReadingQueue, in context: ModelContext) {
        context.insert(SyncTombstone(recordID: queue.id, recordType: .readingQueue))
    }

    static func recordDeletion(of membership: ReadingQueueMembership, in context: ModelContext) {
        context.insert(SyncTombstone(recordID: membership.id, recordType: .readingQueueMembership))
    }
}

enum SyncMerge {
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
