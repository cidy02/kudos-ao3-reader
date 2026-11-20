import Foundation

/// Pure skip / seek rules for the read-aloud mini player, modeled on Apple Music:
/// - Tap `<<`: restart current spine chapter, or previous chapter when near the start
/// - Tap `>>`: next spine chapter
/// - Hold `<<` / `>>`: step within the current chapter's Readium positions
///
/// "Chapter" here means a **spine item** (`positionsByReadingOrder` index), the same
/// unit as the position card's page slider — not AO3 story-chapter numbering alone.
nonisolated enum ReaderSpeechSkip {
    /// How many leading pages (1-based) count as "near the start" for `<<`.
    /// Page 1 is always near start; the default of 2 is the optional polish so a
    /// single spoken sentence doesn't block jumping to the previous chapter.
    static let nearStartPageCount: Int = 2

    enum BackwardAction: Equatable {
        /// Jump to the first position of the current spine chapter.
        case restartChapter
        /// Jump to the first position of the previous spine chapter.
        case previousChapter
        /// First page of the first chapter — nothing to do.
        case none
    }

    enum ForwardAction: Equatable {
        case nextChapter
        case none
    }

    /// - Parameters:
    ///   - page: 1-based page within the current spine chapter.
    ///   - chapter: 1-based spine chapter index.
    ///   - chapterCount: total spine chapters.
    ///   - nearStartPages: pages that count as near the start (default 2).
    static func backwardAction(
        page: Int,
        chapter: Int,
        chapterCount: Int,
        nearStartPages: Int = nearStartPageCount
    ) -> BackwardAction {
        let page = max(1, page)
        let chapter = max(1, chapter)
        let nearStart = page <= max(1, nearStartPages)

        if !nearStart {
            return .restartChapter
        }
        if chapter > 1 {
            return .previousChapter
        }
        // First chapter, near start: restart if we've moved past page 1, else nothing.
        return page > 1 ? .restartChapter : .none
    }

    static func forwardAction(chapter: Int, chapterCount: Int) -> ForwardAction {
        let chapter = max(1, chapter)
        let chapterCount = max(0, chapterCount)
        return chapter < chapterCount ? .nextChapter : .none
    }

    /// Resolves the next 1-based spine chapter for skip-forward / auto-advance,
    /// preferring Read Aloud's synchronously-updated `speechChapter` over the
    /// asynchronously-settling navigator `bookChapter`.
    static func nextChapterForSkipForward(
        speechChapter: Int?,
        bookChapter: Int?,
        chapterCount: Int
    ) -> Int? {
        guard let currentChapter = speechChapter ?? bookChapter else { return nil }
        switch forwardAction(chapter: currentChapter, chapterCount: chapterCount) {
        case .nextChapter:
            return currentChapter + 1
        case .none:
            return nil
        }
    }

    /// Where a Read Aloud chapter skip counts from: a 1-based spine chapter and the
    /// 1-based page within it.
    struct Origin: Equatable {
        var chapter: Int
        var page: Int
    }

    /// One rule for ⏭ and ⏮ (review 4 P3 #1).
    /// - `followsSpeech` (playing, or Read Aloud advancing itself past an unspeakable
    ///   chapter): count from the speech position. The navigator settles
    ///   asynchronously, so right after a chapter jump `visibleChapter` is stale;
    ///   counting from it re-skipped the same chapter.
    /// - Otherwise (paused or stopped): count from the page the user is looking at.
    ///   Paused without browsing, the two agree; paused after browsing to another
    ///   chapter, the visible page wins, so ⏭ never jumps backwards.
    /// When the speech chapter is used but differs from the visible one, the page
    /// is taken as 1: the speech position has just moved to that chapter's start.
    static func origin(
        followsSpeech: Bool,
        speechChapter: Int?,
        visibleChapter: Int?,
        visiblePage: Int
    ) -> Origin? {
        guard let visibleChapter else {
            return speechChapter.map { Origin(chapter: $0, page: 1) }
        }
        if followsSpeech, let speechChapter, speechChapter != visibleChapter {
            return Origin(chapter: speechChapter, page: 1)
        }
        return Origin(chapter: visibleChapter, page: max(1, visiblePage))
    }

    /// 1-based target chapter for a skip from `origin`, or `nil` when there is nothing
    /// to do (⏭ on the last chapter, ⏮ on the first page of the first chapter).
    static func targetChapter(forward: Bool, from origin: Origin, chapterCount: Int) -> Int? {
        if forward {
            return forwardAction(chapter: origin.chapter, chapterCount: chapterCount) == .nextChapter
                ? origin.chapter + 1
                : nil
        }
        switch backwardAction(page: origin.page, chapter: origin.chapter, chapterCount: chapterCount) {
        case .restartChapter: return origin.chapter
        case .previousChapter: return origin.chapter - 1
        case .none: return nil
        }
    }

    /// Next index for hold-to-seek within a chapter's position list, or `nil` at a bound.
    static func seekIndex(current: Int, count: Int, delta: Int) -> Int? {
        guard count > 0, delta != 0 else { return nil }
        let next = current + delta
        guard next >= 0, next < count else { return nil }
        return next
    }
}
