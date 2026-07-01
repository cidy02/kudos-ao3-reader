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
        if !work.isProtected { freeEPUB(work) }
        saveBestEffort(context, reason: "Saving finished state failed")
    }

    /// Frees a finished, unprotected work's EPUB if it still has one. Safe to call
    /// repeatedly (e.g. when leaving the reader). Saves only if something changed.
    @MainActor
    static func freeEPUBIfFinished(_ work: SavedWork, in context: ModelContext) {
        guard work.isFinished, !work.isProtected, work.hasEPUB else { return }
        freeEPUB(work)
        saveBestEffort(context, reason: "Saving freed EPUB state failed")
    }

    /// Saves (keeps) or un-saves a work. Saving protects its EPUB from being freed.
    @MainActor
    static func setSaved(_ work: SavedWork, _ saved: Bool, in context: ModelContext) {
        work.isSaved = saved
        saveBestEffort(context, reason: "Saving saved state failed")
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
    }

    /// Removes a work from the Library entirely: its EPUB, reader cache, and record.
    /// Saves the context.
    @MainActor
    static func delete(_ work: SavedWork, in context: ModelContext) {
        try? FileManager.default.removeItem(at: work.fileURL)
        try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
        context.delete(work)
        saveBestEffort(context, reason: "Saving work deletion failed")
    }

    @MainActor
    private static func saveBestEffort(_ context: ModelContext, reason: StaticString) {
        do {
            try context.save()
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
