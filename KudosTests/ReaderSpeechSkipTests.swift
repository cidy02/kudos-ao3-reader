import Foundation
import Testing
@testable import Kudos

@Suite("Reader speech skip (Music-like)")
struct ReaderSpeechSkipTests {
    // MARK: - Backward

    @Test func midChapterRestarts() {
        #expect(
            ReaderSpeechSkip.backwardAction(page: 5, chapter: 2, chapterCount: 10)
                == .restartChapter
        )
    }

    @Test func firstPageGoesToPreviousChapter() {
        #expect(
            ReaderSpeechSkip.backwardAction(page: 1, chapter: 3, chapterCount: 10)
                == .previousChapter
        )
    }

    @Test func polishSecondPageStillNearStart() {
        #expect(
            ReaderSpeechSkip.backwardAction(page: 2, chapter: 3, chapterCount: 10)
                == .previousChapter
        )
        #expect(
            ReaderSpeechSkip.backwardAction(page: 3, chapter: 3, chapterCount: 10)
                == .restartChapter
        )
    }

    @Test func firstChapterFirstPageIsNone() {
        #expect(
            ReaderSpeechSkip.backwardAction(page: 1, chapter: 1, chapterCount: 5)
                == .none
        )
    }

    @Test func firstChapterNearStartPastPageOneRestarts() {
        #expect(
            ReaderSpeechSkip.backwardAction(page: 2, chapter: 1, chapterCount: 5)
                == .restartChapter
        )
    }

    @Test func nearStartPagesCanBeStrictFirstPageOnly() {
        #expect(
            ReaderSpeechSkip.backwardAction(
                page: 2, chapter: 3, chapterCount: 10, nearStartPages: 1
            ) == .restartChapter
        )
    }

    // MARK: - Forward

    @Test func forwardAdvancesUntilLast() {
        #expect(ReaderSpeechSkip.forwardAction(chapter: 1, chapterCount: 3) == .nextChapter)
        #expect(ReaderSpeechSkip.forwardAction(chapter: 3, chapterCount: 3) == .none)
    }

    // MARK: - Seek index

    @Test func seekStepsWithinBounds() {
        #expect(ReaderSpeechSkip.seekIndex(current: 2, count: 10, delta: 1) == 3)
        #expect(ReaderSpeechSkip.seekIndex(current: 2, count: 10, delta: -1) == 1)
        #expect(ReaderSpeechSkip.seekIndex(current: 0, count: 10, delta: -1) == nil)
        #expect(ReaderSpeechSkip.seekIndex(current: 9, count: 10, delta: 1) == nil)
        #expect(ReaderSpeechSkip.seekIndex(current: 0, count: 0, delta: 1) == nil)
    }
}
