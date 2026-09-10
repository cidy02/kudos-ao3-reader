import Foundation
import SwiftData

/// The bulk "Clear" actions spec 1ac puts on the privacy screen, and — more to
/// the point — the rules for *which* records each one touches.
///
/// Those rules live here rather than inside the view because they are the part
/// worth getting right and the part worth testing. A clear-downloads button that
/// frees one work too many has taken away a file the reader deliberately kept,
/// and the failure is silent: nothing is deleted, the record stays, and they
/// only find out the next time they open it on a train with no signal.
///
/// Every operation is written as `select…` (pure, returns what would be
/// affected) plus `clear…` (applies it). The screen calls `select` to put a real
/// count in front of the reader before they confirm, then calls `clear` — so the
/// number in the confirmation is produced by the same rule that does the work,
/// not by a second one that can drift from it.
enum LocalDataClearing {

    // MARK: Downloaded files

    /// Works whose EPUB may be freed: finished, still holding a file, and not
    /// protected.
    ///
    /// `isProtected` already covers Downloaded, favourited, queued, and any work
    /// with no AO3 id to re-fetch from — the four ways a reader says "keep this".
    /// Reusing it rather than restating the conditions means this button and the
    /// reader's own auto-free can never disagree about what is safe to drop.
    static func selectFreeableDownloads(from works: [SavedWork]) -> [SavedWork] {
        works.filter { $0.isFinished && $0.hasEPUB && !$0.isProtected && !$0.isPendingDeletion }
    }

    /// Frees every EPUB `selectFreeableDownloads` names. The records stay: a
    /// freed work is history, and re-opening it downloads it again.
    @discardableResult
    static func clearFreeableDownloads(from works: [SavedWork], in context: ModelContext) -> Int {
        let freeable = selectFreeableDownloads(from: works)
        for work in freeable {
            WorkLifecycle.freeEPUB(work)
        }
        guard !freeable.isEmpty else { return 0 }
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Freeing downloaded works failed")
        return freeable.count
    }

    // MARK: Reading positions

    /// Whether this work is holding a resume position at all — either reader's.
    ///
    /// Three fields rather than one because two readers wrote them: Readium
    /// persists a JSON locator, the legacy WKWebView reader a spine index and a
    /// scroll fraction. A work resumed only by the legacy reader has an empty
    /// locator and is still very much mid-read.
    static func hasReadingPosition(_ work: SavedWork) -> Bool {
        !work.readiumLocator.isEmpty || work.lastSpineIndex > 0 || work.lastScrollFraction > 0
    }

    static func selectReadingPositions(from works: [SavedWork]) -> [SavedWork] {
        works.filter { hasReadingPosition($0) && !$0.isPendingDeletion }
    }

    /// Forgets where the reader had got to in every work, keeping the works.
    ///
    /// Deliberately leaves `lastReadDate` alone. That is the Library's
    /// "Continue Reading" ordering and the answer to "what was I reading last
    /// week" — a fact about the shelf rather than a position inside a file, and
    /// clearing it would empty a shelf the reader did not ask to empty.
    @discardableResult
    static func clearReadingPositions(from works: [SavedWork], in context: ModelContext) -> Int {
        let positioned = selectReadingPositions(from: works)
        for work in positioned {
            work.readiumLocator = ""
            work.lastSpineIndex = 0
            work.lastScrollFraction = 0
            work.progressModifiedAt = Date()
            work.markModified()
        }
        guard !positioned.isEmpty else { return 0 }
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Clearing reading positions failed")
        return positioned.count
    }
}
