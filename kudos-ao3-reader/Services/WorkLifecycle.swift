import Foundation
import OSLog
import SwiftData

/// Transitions for a work's storage lifecycle: Reading → (finished) → History or
/// Saved. Kept in one place so the reader, library, and detail views stay in sync.
enum WorkLifecycle {

    /// Marks a work finished and, unless it's saved or favorited, frees its EPUB
    /// (turning it into a revisitable history entry).
    @MainActor
    static func markFinished(_ work: SavedWork, in context: ModelContext) {
        work.isFinished = true
        work.markModified()
        if !work.isProtected { freeEPUB(work) }
        context.saveBestEffort(reason: "Saving finished state failed")
    }

    /// Returns a finished work to the in-progress/reading state. If its EPUB was freed,
    /// the normal reader-open path restores it before reading.
    @MainActor
    static func markStillReading(_ work: SavedWork, in context: ModelContext) {
        work.isFinished = false
        work.markModified()
        context.saveBestEffort(reason: "Saving still-reading state failed")
    }

    /// Frees a finished, unprotected work's EPUB if it still has one. Safe to call
    /// repeatedly (e.g. when leaving the reader). Saves only if something changed.
    @MainActor
    static func freeEPUBIfFinished(_ work: SavedWork, in context: ModelContext) {
        guard work.isFinished, !work.isProtected, work.hasEPUB else { return }
        freeEPUB(work)
        context.saveBestEffort(reason: "Saving freed EPUB state failed")
    }

    /// Saves (keeps) or un-saves a work. Saving protects its EPUB from being freed.
    @MainActor
    static func setSaved(_ work: SavedWork, _ saved: Bool, in context: ModelContext) {
        work.isSaved = saved
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
        try? FileManager.default.removeItem(at: work.fileURL)
        try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
        context.delete(work)
        context.saveBestEffort(reason: "Saving work deletion failed")
    }
}
