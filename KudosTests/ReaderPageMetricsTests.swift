import Foundation
import Testing
@testable import Kudos

/// Pure visual-page ↔ Readium-position mappings used by the position card,
/// scrub seek, and speech hold-to-seek. No navigator / UI.
@Suite("Reader page metrics")
struct ReaderPageMetricsTests {

    // MARK: - chapterRemainingPositions

    @Test func remainingWhenPageCountMatchesPositionsIsPageCountMinusPage() {
        // Position-list mode: pageCount is already the chapter's position count.
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 1, pageCount: 12, chapterPositionCount: 12
            ) == 11
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 7, pageCount: 12, chapterPositionCount: 12
            ) == 5
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 12, pageCount: 12, chapterPositionCount: 12
            ) == 0
        )
    }

    @Test func remainingScalesVisualPagesOntoPositionCount() {
        // Classic bug class: 95 visual swipe pages vs 10 ~1 KB positions.
        // Mid-chapter visual page must not claim "95 − page" minutes.
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 1, pageCount: 95, chapterPositionCount: 10
            ) == 10
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 48, pageCount: 95, chapterPositionCount: 10
            ) == 5
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 95, pageCount: 95, chapterPositionCount: 10
            ) == 0
        )
    }

    @Test func remainingNeverExceedsChapterPositionCount() {
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 0, pageCount: 20, chapterPositionCount: 8
            ) == 8
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: -3, pageCount: 20, chapterPositionCount: 8
            ) == 8
        )
    }

    @Test func remainingDegenerateInputsAreZero() {
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 1, pageCount: 0, chapterPositionCount: 10
            ) == 0
        )
        #expect(
            ReaderPageMetrics.chapterRemainingPositions(
                page: 1, pageCount: 10, chapterPositionCount: 0
            ) == 0
        )
    }

    // MARK: - page(progression:pageCount:)

    @Test func pageFromProgressionIsInverseOfProgression() {
        #expect(ReaderPageMetrics.page(progression: 0, pageCount: 95) == 1)
        #expect(ReaderPageMetrics.page(progression: 1, pageCount: 95) == 95)
        // Mid-chapter resume must not land on last page.
        let mid = ReaderPageMetrics.page(progression: 0.5, pageCount: 95)
        #expect(mid > 1 && mid < 95)
        // Round-trip through progression keeps us near the same page.
        let prog = ReaderPageMetrics.progression(page: mid, pageCount: 95)
        #expect(ReaderPageMetrics.page(progression: prog, pageCount: 95) == mid)
    }

    @Test func pageFromProgressionClamps() {
        #expect(ReaderPageMetrics.page(progression: -0.5, pageCount: 10) == 1)
        #expect(ReaderPageMetrics.page(progression: 1.5, pageCount: 10) == 10)
        #expect(ReaderPageMetrics.page(progression: 0.3, pageCount: 1) == 1)
    }

    // MARK: - positionIndex(visualPage:…)

    @Test func positionIndexMatchesPageMinusOneWhenCountsAgree() {
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 1, visualPageCount: 12, positionCount: 12
            ) == 0
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 7, visualPageCount: 12, positionCount: 12
            ) == 6
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 12, visualPageCount: 12, positionCount: 12
            ) == 11
        )
    }

    @Test func positionIndexScalesVisualPageOntoFewerPositions() {
        // Using page − 1 directly would clamp mid-book visual pages to the last
        // position (page 48 → index 47 → clamp 9). Proportional mapping keeps
        // mid-chapter near the middle of the position list.
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 1, visualPageCount: 95, positionCount: 10
            ) == 0
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 95, visualPageCount: 95, positionCount: 10
            ) == 9
        )
        let mid = ReaderPageMetrics.positionIndex(
            visualPage: 48, visualPageCount: 95, positionCount: 10
        )
        #expect(mid >= 4 && mid <= 5)
    }

    @Test func positionIndexSinglePageOrPositionIsZero() {
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 1, visualPageCount: 1, positionCount: 10
            ) == 0
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 5, visualPageCount: 10, positionCount: 1
            ) == 0
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 1, visualPageCount: 10, positionCount: 0
            ) == 0
        )
    }

    @Test func positionIndexClampsOutOfRangePages() {
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 0, visualPageCount: 10, positionCount: 10
            ) == 0
        )
        #expect(
            ReaderPageMetrics.positionIndex(
                visualPage: 99, visualPageCount: 10, positionCount: 10
            ) == 9
        )
    }

    // MARK: - progression

    @Test func progressionEndpointsAndMidpoint() {
        #expect(ReaderPageMetrics.progression(page: 1, pageCount: 12) == 0)
        #expect(ReaderPageMetrics.progression(page: 12, pageCount: 12) == 1)
        #expect(
            abs(ReaderPageMetrics.progression(page: 7, pageCount: 12) - 6.0 / 11.0)
                < 0.000_001
        )
        // A single-page chapter has nowhere left to go — page 1 of 1 reads as
        // fully progressed, not as the start. Matches the position card's bar.
        #expect(ReaderPageMetrics.progression(page: 1, pageCount: 1) == 1)
    }

    // MARK: - work remaining

    @Test func workRemainingUsesGlobalPosition() {
        #expect(
            ReaderPageMetrics.workRemainingPositions(globalPosition: 25, totalPositions: 100)
                == 75
        )
        #expect(
            ReaderPageMetrics.workRemainingPositions(globalPosition: 100, totalPositions: 100)
                == 0
        )
        #expect(
            ReaderPageMetrics.workRemainingPositions(globalPosition: 150, totalPositions: 100)
                == 0
        )
        #expect(
            ReaderPageMetrics.workRemainingPositions(globalPosition: nil, totalPositions: 100)
                == 0
        )
        #expect(
            ReaderPageMetrics.workRemainingPositions(globalPosition: 10, totalPositions: 0)
                == 0
        )
    }

    // MARK: - Speech hold composition (visual page → index → step)

    @Test func speechHoldSeekUsesScaledIndexNotRawVisualPage() {
        // Hold tick composes positionIndex → ReaderSpeechSkip.seekIndex.
        // Starting mid visual chapter must step a mid-list position, not the end.
        let current = ReaderPageMetrics.positionIndex(
            visualPage: 48, visualPageCount: 95, positionCount: 10
        )
        #expect(current < 9, "mid visual page must not clamp to last position")
        let next = ReaderSpeechSkip.seekIndex(current: current, count: 10, delta: 1)
        #expect(next == current + 1)
        let prev = ReaderSpeechSkip.seekIndex(current: current, count: 10, delta: -1)
        #expect(prev == current - 1)
    }

    @Test func speechHoldAtVisualEndDoesNotStepPastPositions() {
        let end = ReaderPageMetrics.positionIndex(
            visualPage: 95, visualPageCount: 95, positionCount: 10
        )
        #expect(end == 9)
        #expect(ReaderSpeechSkip.seekIndex(current: end, count: 10, delta: 1) == nil)
    }

    // MARK: - Scrub parity with ReaderChapterScrub

    @Test func progressionMatchesChapterScrubPositionIndexWhenCountsAgree() {
        // Scrub release uses ReaderChapterScrub.positionIndex for position-list
        // seek, and progression for visual seek. When counts agree both paths
        // must land on the same index.
        for page in 1...12 {
            let progression = ReaderPageMetrics.progression(page: page, pageCount: 12)
            let fromProgression = ReaderPageMetrics.positionIndex(
                visualPage: page, visualPageCount: 12, positionCount: 12
            )
            let fromScrub = ReaderChapterScrub.positionIndex(
                sliderValue: progression, pageCount: 12
            )
            #expect(fromProgression == fromScrub)
            #expect(fromProgression == page - 1)
        }
    }
}
