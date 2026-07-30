import Foundation

/// Pure mappings between **visual swipe pages** (1:1 with paged turns) and
/// Readium's ~1 KB **positions** list. Extracted so the position card's "min left",
/// scrub seek, and speech hold-to-seek can share one arithmetic and stay under
/// unit tests without a live navigator.
///
/// Visual page counts and position counts often diverge (e.g. 95 swipe pages vs
/// 10 content positions in one chapter). Treating a visual page number as a
/// position index is a known bug class — every caller should go through these
/// helpers instead.
nonisolated enum ReaderPageMetrics {
    /// Chapter positions still ahead, scaled from the current visual (or position-
    /// list) page onto the chapter's real position count.
    ///
    /// Matches `ReadiumBook.remainingPositions` chapter branch when visual metrics
    /// are live: `round((pageCount - page) / pageCount * chapterPositionCount)`.
    /// When `pageCount == chapterPositionCount` this equals `pageCount - page`.
    ///
    /// - Parameters:
    ///   - page: 1-based current page (visual or position-list).
    ///   - pageCount: total pages in the same metric as `page`.
    ///   - chapterPositionCount: Readium positions in the current spine chapter.
    static func chapterRemainingPositions(
        page: Int,
        pageCount: Int,
        chapterPositionCount: Int
    ) -> Int {
        guard pageCount > 0, chapterPositionCount > 0 else { return 0 }
        let page = min(pageCount, max(1, page))
        let remFrac = Double(max(0, pageCount - page)) / Double(pageCount)
        return max(0, Int((remFrac * Double(chapterPositionCount)).rounded()))
    }

    /// Zero-based index into a chapter's Readium position list for a 1-based
    /// visual (or position-list) page.
    ///
    /// Uses the same end-inclusive progression as the scrub slider
    /// (`(page - 1) / (pageCount - 1)`), then snaps onto `positionCount - 1`.
    /// When `visualPageCount == positionCount` this is simply `page - 1`.
    static func positionIndex(
        visualPage: Int,
        visualPageCount: Int,
        positionCount: Int
    ) -> Int {
        guard positionCount > 0 else { return 0 }
        guard visualPageCount > 1, positionCount > 1 else { return 0 }
        let page = min(visualPageCount, max(1, visualPage))
        let progression = Double(page - 1) / Double(visualPageCount - 1)
        let index = Int((progression * Double(positionCount - 1)).rounded())
        return min(positionCount - 1, max(0, index))
    }

    /// Resource progression (0…1) for a 1-based page within `pageCount` pages.
    /// Same end-inclusive spacing as `ReaderChapterScrub` / scrub-on-release seek.
    /// A single-page chapter has nowhere left to go, so it reads as fully
    /// progressed (1), matching the position card's bar and keeping a
    /// scrub-on-release seek on a 1-page chapter consistent with what the bar
    /// showed before the release.
    static func progression(page: Int, pageCount: Int) -> Double {
        guard pageCount > 1 else { return 1 }
        let page = min(pageCount, max(1, page))
        return Double(page - 1) / Double(pageCount - 1)
    }

    /// Inverse of `progression(page:pageCount:)` — 1-based page for a 0…1
    /// resource progression. Used on open when visual pageCount is known but
    /// the JS scroll digit hasn't settled to the resume locator yet.
    static func page(progression: Double, pageCount: Int) -> Int {
        guard pageCount > 1 else { return 1 }
        let prog = min(1, max(0, progression))
        let page = Int((prog * Double(pageCount - 1)).rounded()) + 1
        return min(pageCount, max(1, page))
    }

    /// Whole-work positions still ahead from a 1-based global Readium position.
    static func workRemainingPositions(
        globalPosition: Int?,
        totalPositions: Int
    ) -> Int {
        guard totalPositions > 0, let globalPosition else { return 0 }
        return max(0, totalPositions - globalPosition)
    }
}
