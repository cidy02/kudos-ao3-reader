import Foundation
import OSLog
import SwiftData

#if os(iOS)
extension Notification.Name {
    static let kudosWorkEPUBWillChange = Notification.Name("kudosWorkEPUBWillChange")
}
#endif

/// Transitions for a work's storage lifecycle: Reading → (finished) → History or
/// Saved. Kept in one place so the reader, library, and detail views stay in sync.
enum WorkLifecycle {

    /// How long a finished, un-kept work's copy waits in Recently Deleted's
    /// "Finished, not kept" section before it is freed (owner, 2026-10-01).
    static let freedCopyWindow: TimeInterval = 60 * 86_400

    /// Marks a work finished and, unless something keeps it, holds its copy in
    /// Recently Deleted (`holdFinishedCopy`) on its way to being freed.
    @MainActor
    static func markFinished(_ work: SavedWork, in context: ModelContext) {
        work.isFinished = true
        work.markModified()
        if !work.isProtected { holdFinishedCopy(work) }
        context.saveBestEffort(reason: "Saving finished state failed")
    }

    /// Starts a finished, un-kept work's 60-day wait in Recently Deleted. The
    /// file stays; `sweepHeldCopies` frees it when the window is up. A copy
    /// already waiting keeps its first date.
    @MainActor
    static func holdFinishedCopy(_ work: SavedWork) {
        guard work.hasEPUB, work.freedAt == nil else { return }
        work.freedAt = Date()
    }

    /// Recently Deleted's Restore for a held copy: keeps it downloaded.
    @MainActor
    static func restoreHeldCopy(_ work: SavedWork, in context: ModelContext) {
        work.freedAt = nil
        setSaved(work, true, in: context)
    }

    /// Recently Deleted's Delete Permanently for a held copy: frees the file now.
    /// The work stays in the reading history.
    @MainActor
    static func freeHeldCopy(_ work: SavedWork, in context: ModelContext) {
        freeEPUB(work)
        context.saveBestEffort(reason: "Freeing a held copy failed")
    }

    /// Frees every held copy past its window, and lets go of any that no longer
    /// qualify — reopened, un-finished, or kept since (favorited, queued,
    /// downloaded). Runs with the Recently Deleted sweep. `everything` is Delete
    /// All Permanently.
    @MainActor
    @discardableResult
    static func sweepHeldCopies(in context: ModelContext, now: Date = Date(), everything: Bool = false) -> Int {
        let held = (try? context.fetch(FetchDescriptor<SavedWork>(predicate: #Predicate { $0.freedAt != nil }))) ?? []
        guard !held.isEmpty, PreservedWorkService.prepareDeletion(in: context) else { return 0 }
        var freed = 0
        let chunkSize = PreservedWorkService.deletionChunkSize
        for start in stride(from: 0, to: held.count, by: chunkSize) {
            var files: [WorkDeletionFiles] = []
            for work in held[start..<min(start + chunkSize, held.count)] {
                guard work.isFinished, !work.isProtected, !work.isPendingDeletion, work.hasEPUB else {
                    work.freedAt = nil
                    continue
                }
                if everything || (work.freedAt.map { now.timeIntervalSince($0) >= freedCopyWindow } ?? false) {
                    files.append(WorkDeletionFiles(id: work.id, epub: work.fileURL))
                    clearEPUBState(work)
                }
            }
            guard !context.hasChanges || PreservedWorkService.commitDeletion(in: context) else { break }
            for file in files { file.removeEPUB() }
            freed += files.count
        }
        return freed
    }

    /// Reading a held work again takes it out of Recently Deleted.
    @MainActor
    static func releaseHeldCopy(_ work: SavedWork) {
        work.freedAt = nil
    }

    /// Returns a finished work to the in-progress/reading state. If its EPUB was freed,
    /// the normal reader-open path restores it before reading.
    @MainActor
    static func markStillReading(_ work: SavedWork, in context: ModelContext) {
        work.isFinished = false
        work.freedAt = nil
        work.markModified()
        context.saveBestEffort(reason: "Saving still-reading state failed")
    }

    /// 1ai's "Move back to In progress". Abandoned is derived from a threshold
    /// (`ReadingLogService.isAbandoned`), so undoing it has to be stored — the
    /// spec: "the undo writes a manual override so the threshold cannot
    /// re-abandon it". Rides the existing `keepInProgressOverride`, which the
    /// backup manifest and its merge already carry (`KudosBackup`).
    @MainActor
    static func keepInProgress(_ work: SavedWork, in context: ModelContext) {
        work.keepInProgressOverride = true
        work.markModified()
        context.saveBestEffort(reason: "Saving keep-in-progress override failed")
    }

    /// Writes an explicit reading status and saves atomically. Rolls the context
    /// back on error so a failed status edit never stays dirty for a later autosave.
    @MainActor
    static func setReadingStatus(
        _ status: SavedWork.ExplicitReadingStatus?,
        for work: SavedWork,
        in context: ModelContext,
        at date: Date = Date(),
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        work.setReadingStatus(status, at: date)
        do {
            try save(context)
            FolderSyncService.markDirty()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Records a work as Stopped with its local reason, tag and note, saving
    /// atomically and rolling the context back on failure.
    @MainActor
    static func recordStopped(
        _ work: SavedWork,
        reason: String,
        tag: String,
        note: String,
        in context: ModelContext,
        at date: Date = Date(),
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        work.recordStopped(reason: reason, tag: tag, note: note, at: date)
        do {
            try save(context)
            FolderSyncService.markDirty()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 1ah's "Remove from history" — "the only destructive thing this page can
    /// do", and it must not delete the work. Sets a hide marker and nothing else:
    /// the record, its EPUB, its progress and its reading log all stay, and
    /// reading it again clears the marker (`SavedWork.markProgressModified`).
    @MainActor
    static func removeFromHistory(_ work: SavedWork, in context: ModelContext, at date: Date = Date()) {
        work.hiddenFromHistoryAt = date
        work.markModified(date)
        context.saveBestEffort(reason: "Saving remove-from-history failed")
    }

    /// Holds a finished, unprotected work's copy in Recently Deleted if it still
    /// has one (`holdFinishedCopy`). Safe to call repeatedly (e.g. when leaving
    /// the reader). Saves only if something changed.
    @MainActor
    static func freeEPUBIfFinished(_ work: SavedWork, in context: ModelContext) {
        guard work.isFinished, !work.isProtected, work.hasEPUB, work.freedAt == nil else { return }
        holdFinishedCopy(work)
        context.saveBestEffort(reason: "Saving held copy failed")
    }

    /// Settings › Downloads › "Keep works you read" (owner, 2026-10-01). Off by
    /// default; read by `keepIfKeepingWorksYouRead`.
    static let keepsWorksYouReadKey = "keepsWorksYouRead"

    /// Opening a work in the reader marks it Downloaded when the reader asked
    /// for that, so finishing it never frees its EPUB. Only ever keeps — the
    /// setting turned off later leaves what it kept alone, as if each had been
    /// downloaded by hand.
    @MainActor
    static func keepIfKeepingWorksYouRead(
        _ work: SavedWork,
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.bool(forKey: keepsWorksYouReadKey), !work.isSaved else { return }
        setSaved(work, true, in: context)
    }

    /// Saves (keeps) or un-saves a work. Saving protects its EPUB from being freed.
    @MainActor
    static func setSaved(_ work: SavedWork, _ saved: Bool, in context: ModelContext) {
        work.isSaved = saved
        if saved && work.coverRecipeJSON == nil { work.pinCover(salt: 0, automatic: true) }
        if saved { work.freedAt = nil }
        work.markModified()
        context.saveBestEffort(reason: "Saving saved state failed")
    }

    /// Deletes the on-disk EPUB and its unzipped reader cache, keeping the record
    /// as history. Does not save the context — callers do.
    @MainActor
    static func freeEPUB(_ work: SavedWork) {
        WorkDeletionFiles(id: work.id, epub: work.fileURL).removeEPUB()
        clearEPUBState(work)
    }

    @MainActor
    private static func clearEPUBState(_ work: SavedWork) {
        work.hasEPUB = false
        work.freedAt = nil
        // A promised remote copy is a promise about bytes this device wanted.
        // Freeing is the reader saying they do not want them, so the promise
        // goes too — otherwise the next export advertises an EPUB that was
        // deliberately deleted, and peers skip sending the real one.
        work.remoteEPUBPending = false
        if work.isQueuedForLater {
            work.epubPreservationStatus = .missingFile
        }
        work.markModified()
    }

    /// Permanently removes a work from the Library: its EPUB, reader cache, and
    /// record. Saves the context. Called only by `PreservedWorkService` (after the
    /// 90-day Recently Deleted window expires, or an explicit "Delete Permanently"
    /// action) — everyday deletion goes through `PreservedWorkService.softDelete`
    /// instead, so a work is always recoverable first.
    @MainActor
    static func hardDelete(_ work: SavedWork, in context: ModelContext) {
        _ = hardDelete([work], in: context)
    }

    @MainActor
    static func hardDelete(_ works: [SavedWork], in context: ModelContext) -> Int {
        guard !works.isEmpty else { return 0 }
        var repeatedIDs = Set<UUID>()
        let workIDs = works.reduce(into: Set<UUID>()) { ids, work in
            if !ids.insert(work.id).inserted { repeatedIDs.insert(work.id) }
        }
        // Annotations are not cascaded. Index them once for the whole sweep and
        // stop if the fetch fails: deleting the book would orphan its notes.
        var annotationsByWork: [UUID: [ReadingAnnotation]] = [:]
        let annotationEntity = Schema.entityName(for: ReadingAnnotation.self)
        if context.container.schema.entitiesByName[annotationEntity] != nil {
            guard let annotations = try? context.fetch(FetchDescriptor<ReadingAnnotation>()) else { return 0 }
            for annotation in annotations {
                guard let id = annotation.work?.id, workIDs.contains(id) else { continue }
                annotationsByWork[id, default: []].append(annotation)
            }
        }
        let originals = Storage.existingOriginalDocumentURLs()
        guard PreservedWorkService.prepareDeletion(in: context) else { return 0 }

        var deleted = 0
        for start in stride(from: 0, to: works.count, by: PreservedWorkService.deletionChunkSize) {
            let chunk = works[start..<min(start + PreservedWorkService.deletionChunkSize, works.count)]
            let files = chunk.map { WorkDeletionFiles(id: $0.id, epub: $0.fileURL) }
            // Let the reader release its file before staging any changes that
            // its notification handler could incidentally save.
            #if os(iOS)
            for file in files {
                NotificationCenter.default.post(name: .kudosWorkEPUBWillChange, object: file.id)
            }
            #endif
            var memberships: [ReadingQueueMembership] = []
            for work in chunk {
                memberships.append(contentsOf: stageDeletion(
                    of: work, annotations: annotationsByWork.removeValue(forKey: work.id) ?? [], in: context
                ))
            }
            if chunk.count > 1 {
                detachDeletedWorks(chunk, memberships: memberships)
                // The stage captured these before removing their queue inverses.
                for membership in memberships { context.delete(membership) }
            }
            for work in chunk { context.delete(work) }
            guard PreservedWorkService.commitDeletion(in: context) else { break }
            for file in files {
                let original = repeatedIDs.contains(file.id)
                    ? Storage.existingOriginalDocumentURL(for: file.id) : originals[file.id]
                file.remove(original: original)
            }
            deleted += chunk.count
        }
        return deleted
    }

    @MainActor
    private static func stageDeletion(
        of work: SavedWork, annotations: [ReadingAnnotation], in context: ModelContext
    ) -> [ReadingQueueMembership] {
        SyncTombstones.recordDeletion(of: work, in: context, permanently: true)
        // SavedWork cascades its queue memberships. They need their own
        // tombstones before the cascade so older backups cannot revive them.
        let memberships = work.queueMemberships
        for membership in memberships {
            SyncTombstones.recordDeletion(of: membership, in: context)
        }
        for annotation in annotations {
            SyncTombstones.recordDeletion(of: annotation, in: context)
            context.delete(annotation)
        }
        return memberships
    }

    /// Update each surviving inverse once per chunk. Shelf clocks and reading order stay the same.
    @MainActor
    private static func detachDeletedWorks(_ works: ArraySlice<SavedWork>, memberships: [ReadingQueueMembership]) {
        let workIDs = Set(works.map(ObjectIdentifier.init))
        let membershipIDs = Set(memberships.map(ObjectIdentifier.init))
        var collections: [ObjectIdentifier: WorkCollection] = [:]
        var queues: [ObjectIdentifier: ReadingQueue] = [:]
        for work in works {
            for collection in work.collections { collections[ObjectIdentifier(collection)] = collection }
        }
        for membership in memberships {
            if let queue = membership.queue { queues[ObjectIdentifier(queue)] = queue }
        }
        for collection in collections.values {
            collection.works.removeAll { workIDs.contains(ObjectIdentifier($0)) }
        }
        for queue in queues.values {
            queue.memberships.removeAll { membershipIDs.contains(ObjectIdentifier($0)) }
        }
    }

    private struct WorkDeletionFiles {
        let id: UUID
        let epub: URL

        func removeEPUB() {
            try? FileManager.default.removeItem(at: epub)
            try? FileManager.default.removeItem(at: Storage.readerDirectory(for: id))
        }

        func remove(original: URL?) {
            removeEPUB()
            if let original { try? FileManager.default.removeItem(at: original) }
            WorkConversionRecord.delete(for: id)
        }
    }
}
