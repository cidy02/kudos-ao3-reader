import Foundation
import OSLog
import SwiftData

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
        var freed = 0
        for work in held {
            guard work.isFinished, !work.isProtected, !work.isPendingDeletion, work.hasEPUB else {
                work.freedAt = nil
                continue
            }
            if everything || (work.freedAt.map { now.timeIntervalSince($0) >= freedCopyWindow } ?? false) {
                freeEPUB(work)
                freed += 1
            }
        }
        if !held.isEmpty { context.saveBestEffort(reason: "Sweeping held copies failed") }
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
        if saved { work.freedAt = nil }
        work.markModified()
        context.saveBestEffort(reason: "Saving saved state failed")
    }

    /// Deletes the on-disk EPUB and its unzipped reader cache, keeping the record
    /// as history. Does not save the context — callers do.
    @MainActor
    static func freeEPUB(_ work: SavedWork) {
        try? FileManager.default.removeItem(at: work.fileURL)
        try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
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
        SyncTombstones.recordDeletion(of: work, in: context)
        // The cascade delete rule on SavedWork.queueMemberships removes these rows as a
        // side effect of context.delete(work) below — tombstone them explicitly first so
        // a future cloud merge doesn't resurrect a queue membership for a deleted work.
        for membership in work.queueMemberships {
            SyncTombstones.recordDeletion(of: membership, in: context)
        }
        // ReadingAnnotation.work has no @Relationship cascade rule (it's a plain
        // optional, unlike queueMemberships above), so SwiftData's default
        // .nullify would otherwise leave these rows behind forever — orphaned,
        // untombstoned, and invisible to every list (they all filter by
        // work?.id). Fetch and delete them explicitly, tombstoning each first so
        // a future restore from an older archive can't resurrect a mark whose
        // book no longer exists.
        let workID = work.id
        let orphanedAnnotations = (try? context.fetch(FetchDescriptor<ReadingAnnotation>()))?
            .filter { $0.work?.id == workID } ?? []
        for annotation in orphanedAnnotations {
            SyncTombstones.recordDeletion(of: annotation, in: context)
            context.delete(annotation)
        }
        try? FileManager.default.removeItem(at: work.fileURL)
        try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
        // A converted import keeps the original file it came from. Only permanent
        // deletion removes it — deliberately *not* `freeEPUB`, which exists to
        // reclaim space for works that can be re-downloaded from AO3, and the
        // original of a community copy is the one artifact that cannot.
        if let original = Storage.existingOriginalDocumentURL(for: work.id) {
            try? FileManager.default.removeItem(at: original)
        }
        // Its conversion record goes with it, or the Originals directory accumulates
        // sidecars pointing at files that no longer exist.
        WorkConversionRecord.delete(for: work.id)
        context.delete(work)
        context.saveBestEffort(reason: "Saving work deletion failed")
    }
}
