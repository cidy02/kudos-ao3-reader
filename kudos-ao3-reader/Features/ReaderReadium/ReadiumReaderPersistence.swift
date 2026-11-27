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
            // An unsorted string already stored is the same position as its sorted
            // re-encoding. Recording the stored spelling keeps the flush from
            // rewriting it (and bumping progress) on every close.
            let stable = Locator.persistenceStringKeepingStoredSpelling(
                stored: progressPersistence.latestLocatorString,
                updated: live
            )
            progressPersistence.record(
                locatorString: stable,
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

    /// Debounced settle. Same spelling rule as `flushProgress`: a re-encoded
    /// locator is not a new position.
    static func noteSettledLocator(
        _ locator: Locator,
        progressPersistence: ReadiumProgressPersistence
    ) {
        guard let raw = locator.persistenceString else { return }
        let stable = Locator.persistenceStringKeepingStoredSpelling(
            stored: progressPersistence.latestLocatorString,
            updated: raw
        )
        progressPersistence.note(
            locatorString: stable,
            totalProgression: locator.locations.totalProgression
        )
    }

    /// Highlight identity. Stored marks keep whatever key order they were saved
    /// with; a new selection encodes with sorted keys. Both name one passage.
    static func isSameHighlightPassage(stored: String, selection: String) -> Bool {
        let storedCanonical = Locator.canonicalPersistenceString(stored) ?? stored
        let selectionCanonical = Locator.canonicalPersistenceString(selection) ?? selection
        return ReadingAnnotationMatching.isSamePassage(
            existingLocator: storedCanonical,
            selectionLocator: selectionCanonical
        )
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
    /// True when this jump's target is at or past the locator speech left.
    private var pendingMovesForward = true
    /// Furthest position speech has reached in `heardHrefKey` on a forward jump.
    /// A later settle behind it is an echo, until the user navigates.
    private var heardHrefKey: String?
    private var heardPosition: Int?

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
        pendingMovesForward = Self.movesForward(from: currentLocator, to: locator)
        pendingLocator = locator
        pendingHrefKey = targetHref
        jumpSettled = false
        jumpsInFlight += 1
        return generation
    }

    mutating func endJump(generation completed: UInt64) {
        jumpsInFlight = max(0, jumpsInFlight - 1)
        guard completed == generation, jumpsInFlight == 0, jumpSettled else { return }
        // Drop the pending target but keep the chapters speech already left.
        // A late echo of one of those can arrive after `go` returns.
        pendingLocator = nil
        pendingHrefKey = nil
        jumpSettled = false
    }

    mutating func noteUserNavigation() {
        generation &+= 1
        clearPending()
    }

    /// Returns `true` when `settled` is a stale pre-jump settle from a chapter
    /// speech already moved past (so debounced persistence does not regress).
    ///
    /// A scroll-gesture flag is not a user navigation: the jump's own web view
    /// can be decelerating when the pre-jump locator settles. Scrubs, links,
    /// committed turns and explicit `go` call `noteUserNavigation`.
    mutating func noteLocationDidChange(_ settled: Locator) -> Bool {
        let settledHref = ReaderSectionBuilder.hrefKey(settled.href.string)
        guard let pendingHrefKey else {
            if supersededPreJumpHrefs.contains(settledHref) { return true }
            // Same chapter, but a page speech already moved past.
            if settledHref == heardHrefKey,
               let heardPosition,
               let settledPosition = settled.locations.position,
               settledPosition < heardPosition {
                return true
            }
            return false
        }
        if settledHref == pendingHrefKey {
            // Matching the chapter is not arrival. A forward jump's earlier
            // position, or a backward jump's later one, is still the pre-jump page.
            guard settledReachesPending(settled) else { return true }
            rememberHeardPosition()
            if jumpsInFlight > 0 {
                jumpSettled = true
            } else {
                pendingLocator = nil
                self.pendingHrefKey = nil
                jumpSettled = false
            }
            return false
        }
        if jumpsInFlight > 0 || supersededPreJumpHrefs.contains(settledHref) {
            return true
        }
        clearPending()
        return false
    }

    /// Position order through the book. Equal counts as forward so a jump to the
    /// page already on screen still settles.
    private static func movesForward(from current: Locator?, to target: Locator) -> Bool {
        if let currentPosition = current?.locations.position,
           let targetPosition = target.locations.position {
            return targetPosition >= currentPosition
        }
        let sameChapter = current.map { ReaderSectionBuilder.hrefKey($0.href.string) }
            == ReaderSectionBuilder.hrefKey(target.href.string)
        if sameChapter,
           let currentProgression = current?.locations.progression,
           let targetProgression = target.locations.progression {
            return targetProgression >= currentProgression
        }
        return true
    }

    /// The navigator has landed on the heard locator, not a page on the other
    /// side of it. Missing positions do not count as landing: the flush keeps
    /// the heard locator until a real one arrives.
    private func settledReachesPending(_ settled: Locator) -> Bool {
        guard let pending = pendingLocator else { return true }
        if let pendingPosition = pending.locations.position {
            guard let settledPosition = settled.locations.position else { return false }
            return pendingMovesForward
                ? settledPosition >= pendingPosition
                : settledPosition <= pendingPosition
        }
        if let pendingProgression = pending.locations.progression {
            guard let settledProgression = settled.locations.progression else { return false }
            return pendingMovesForward
                ? settledProgression >= pendingProgression
                : settledProgression <= pendingProgression
        }
        return true
    }

    private mutating func rememberHeardPosition() {
        guard pendingMovesForward,
              let pendingLocator,
              let position = pendingLocator.locations.position
        else {
            if !pendingMovesForward {
                heardHrefKey = nil
                heardPosition = nil
            }
            return
        }
        if heardHrefKey != pendingHrefKey {
            heardHrefKey = pendingHrefKey
            heardPosition = position
        } else {
            heardPosition = max(heardPosition ?? position, position)
        }
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
        heardHrefKey = nil
        heardPosition = nil
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
