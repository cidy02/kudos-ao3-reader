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

    /// Next index for hold-to-seek within a chapter's position list, or `nil` at a bound.
    static func seekIndex(current: Int, count: Int, delta: Int) -> Int? {
        guard count > 0, delta != 0 else { return nil }
        let next = current + delta
        guard next >= 0, next < count else { return nil }
        return next
    }
}
