#if os(iOS)
import Foundation
import ReadiumShared
import SwiftData

/// Model mutations shared by the reader's streamed, flush and end-of-book saves.
/// Kept outside the view so their cross-device contract can be regression tested.
@MainActor
enum ReadiumReaderPersistence {
    static func writePosition(
        _ locatorString: String, to work: SavedWork, sections: [ReaderSection], at date: Date = Date()
    ) {
        work.applyDebouncedReadiumLocator(locatorString, at: date)
        guard let locator = Locator(persistenceString: locatorString) else { return }
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        guard let index = sections.first(where: {
            ReaderSectionBuilder.hrefKey($0.href) == key
        })?.spineIndex else { return }
        // macOS resumes from this pair, never from the Readium locator.
        work.lastSpineIndex = index
        work.lastScrollFraction = min(max(locator.locations.progression ?? 0, 0), 1)
    }

    /// Flush point (dismiss / background / disappear): persists the confirmed
    /// speech locator when an async speech jump has not settled (and no later
    /// user navigation superseded it), else the live navigator locator.
    /// Returns `true` when a new position was written to `work`.
    @discardableResult
    static func flushProgress(
        liveLocator: Locator?,
        work: SavedWork,
        sections: [ReaderSection],
        progressPersistence: ReadiumProgressPersistence,
        allowsPersistence: Bool,
        exitCommitted: Bool,
        shelfStamp: Bool,
        in modelContext: ModelContext,
        at now: Date = Date()
    ) -> Bool {
        progressPersistence.cancelTrailingWrite()
        guard allowsPersistence else { return false }
        if !exitCommitted, let live = liveLocator?.persistenceString {
            progressPersistence.record(
                locatorString: live,
                totalProgression: liveLocator?.locations.totalProgression
            )
        }
        if let toWrite = progressPersistence.locatorForFlush() {
            writePosition(toWrite, to: work, sections: sections, at: now)
            if shelfStamp { work.markProgressModified(now) }
            progressPersistence.markPersisted(
                locatorString: toWrite,
                totalProgression: liveLocator?.locations.totalProgression
                    ?? progressPersistence.latestTotalProgression,
                at: now
            )
            try? modelContext.save()
            return true
        } else if shelfStamp, progressPersistence.hasSessionPosition {
            // Locator already on disk — still bump lastReadDate so the shelf
            // reflects this reading session on a quick open/close.
            ReadiumSessionStamp.noteUnchangedLocatorShelf(work, at: now)
            try? modelContext.save()
        }
        return false
    }

    static func deleteAnnotation(_ annotation: ReadingAnnotation, in context: ModelContext) {
        SyncTombstones.recordDeletion(of: annotation, in: context, reason: "annotationDeleted")
        context.delete(annotation)
    }
}

/// Tracks Read Aloud's pending navigator jump so a close/background flush never
/// writes a pre-jump locator before the async `navigator.go(to:)` settles, while
/// letting any later user navigation take over immediately.
struct ReadiumSpeechNavigationState {
    private(set) var pendingLocator: Locator?
    private(set) var pendingHrefKey: String?
    private(set) var jumpsInFlight = 0
    private var generation: UInt64 = 0
    private var jumpSettled = false
    /// Normalized href keys of chapters left behind by a pending speech jump.
    /// A late non-user settle in one of these chapters is a pre-jump echo.
    private var supersededPreJumpHrefs: Set<String> = []

    mutating func beginJump(to locator: Locator, currentLocator: Locator?) -> UInt64 {
        generation &+= 1
        let targetHref = ReaderSectionBuilder.hrefKey(locator.href.string)
        if let previousPending = pendingHrefKey, previousPending != targetHref {
            supersededPreJumpHrefs.insert(previousPending)
        }
        if let currentHref = currentLocator.map({ ReaderSectionBuilder.hrefKey($0.href.string) }),
           currentHref != targetHref {
            supersededPreJumpHrefs.insert(currentHref)
        }
        supersededPreJumpHrefs.remove(targetHref)
        pendingLocator = locator
        pendingHrefKey = targetHref
        jumpSettled = false
        jumpsInFlight += 1
        return generation
    }

    mutating func endJump(generation completed: UInt64) {
        jumpsInFlight = max(0, jumpsInFlight - 1)
        guard completed == generation, jumpsInFlight == 0, jumpSettled else { return }
        clearPending()
    }

    mutating func noteUserNavigation() {
        generation &+= 1
        clearPending()
    }

    /// Returns `true` when `settled` is a stale pre-jump settle from a chapter
    /// speech already moved past (so debounced persistence does not regress).
    mutating func noteLocationDidChange(_ settled: Locator, isUserScroll: Bool) -> Bool {
        if isUserScroll {
            noteUserNavigation()
            return false
        }
        guard let pendingHrefKey else { return false }
        let settledHref = ReaderSectionBuilder.hrefKey(settled.href.string)
        if settledHref == pendingHrefKey {
            if jumpsInFlight > 0 {
                jumpSettled = true
            } else {
                clearPending()
            }
            return false
        }
        if jumpsInFlight > 0 || supersededPreJumpHrefs.contains(settledHref) {
            return true
        }
        clearPending()
        return false
    }

    mutating func reset() {
        generation &+= 1
        jumpsInFlight = 0
        clearPending()
    }

    private mutating func clearPending() {
        pendingLocator = nil
        pendingHrefKey = nil
        jumpSettled = false
        supersededPreJumpHrefs.removeAll()
    }
}

extension ReadiumBook {
    /// Confirmed speech locator when an async speech jump has not settled (and no
    /// later user navigation superseded it), else the live navigator locator.
    var locatorForProgressFlush: Locator? {
        speechNavigation.pendingLocator ?? currentLocator
    }

    var pendingSpeechLocator: Locator? {
        speechNavigation.pendingLocator
    }

    var hasSpeechJumpInFlight: Bool {
        speechNavigation.jumpsInFlight > 0
    }

    /// Next intra-chapter position for hold-to-seek without moving the navigator.
    /// Steps from `pendingSeekLocator` when it is in the active chapter, else from
    /// `speechLocator` (when playing) or the live position on screen.
    func nextSpeechSeekLocator(
        forward: Bool,
        pendingSeekLocator: Locator?,
        speechLocator: Locator?,
        followsSpeech: Bool
    ) -> Locator? {
        let activeAnchor = followsSpeech ? (speechLocator ?? currentLocator) : currentLocator
        guard let chapterIdx = activeAnchor.flatMap({ speechSeekChapterIndex(for: $0) }),
              positionsByReadingOrder.indices.contains(chapterIdx)
        else { return nil }
        let positions = positionsByReadingOrder[chapterIdx]
        guard positions.count > 1 else { return nil }

        let sameChapterPending: Locator?
        if let pendingSeekLocator, speechSeekChapterIndex(for: pendingSeekLocator) == chapterIdx {
            sameChapterPending = pendingSeekLocator
        } else {
            sameChapterPending = nil
        }
        let anchor = sameChapterPending ?? activeAnchor

        let currentIdx: Int = {
            if let globalPos = anchor?.locations.position,
               let first = positions.first?.locations.position {
                return max(0, min(positions.count - 1, globalPos - first))
            }
            if let progression = anchor?.locations.progression {
                let idx = Int((progression * Double(positions.count - 1)).rounded())
                return max(0, min(positions.count - 1, idx))
            }
            if sameChapterPending == nil,
               let pos = readingPosition,
               pos.chapter == chapterIdx + 1 {
                return ReaderPageMetrics.positionIndex(
                    visualPage: pos.page,
                    visualPageCount: pos.pageCount,
                    positionCount: positions.count
                )
            }
            return 0
        }()

        let delta = forward ? 1 : -1
        guard let newIdx = ReaderSpeechSkip.seekIndex(
            current: currentIdx,
            count: positions.count,
            delta: delta
        ) else { return nil }
        return positions[newIdx]
    }

    private func speechSeekChapterIndex(for locator: Locator) -> Int? {
        if let chapter = spineChapter(for: locator) {
            return chapter - 1
        }
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        return positionsByReadingOrder.firstIndex { chapter in
            chapter.first.map { ReaderSectionBuilder.hrefKey($0.href.string) == key } ?? false
        }
    }
}
#endif
