import Foundation
import Testing
@testable import Kudos

@Suite("Reader chapter scrub")
struct ReaderChapterScrubTests {
    @Test func singlePageChapterIsAlwaysPageOne() {
        #expect(ReaderChapterScrub.page(sliderValue: 0, pageCount: 1) == 1)
        #expect(ReaderChapterScrub.page(sliderValue: 1, pageCount: 1) == 1)
        #expect(ReaderChapterScrub.pageLabel(sliderValue: 0.5, pageCount: 1) == "Page 1 of 1")
    }

    @Test func endpointsMapToFirstAndLastPage() {
        #expect(ReaderChapterScrub.page(sliderValue: 0, pageCount: 12) == 1)
        #expect(ReaderChapterScrub.page(sliderValue: 1, pageCount: 12) == 12)
    }

    @Test func midTrackRoundsToNearestPage() {
        // 12 pages → 11 steps; 0.5 → index 6 → page 7.
        #expect(ReaderChapterScrub.page(sliderValue: 0.5, pageCount: 12) == 7)
        #expect(ReaderChapterScrub.pageLabel(sliderValue: 0.5, pageCount: 12) == "Page 7 of 12")
    }

    @Test func positionIndexMatchesPageMinusOne() {
        #expect(ReaderChapterScrub.positionIndex(sliderValue: 0, pageCount: 12) == 0)
        #expect(ReaderChapterScrub.positionIndex(sliderValue: 1, pageCount: 12) == 11)
        #expect(ReaderChapterScrub.positionIndex(sliderValue: 0.5, pageCount: 12) == 6)
    }

    @Test func clampsOutOfRangeValues() {
        #expect(ReaderChapterScrub.page(sliderValue: -1, pageCount: 10) == 1)
        #expect(ReaderChapterScrub.page(sliderValue: 2, pageCount: 10) == 10)
    }

    @Test func snapsToOriginWhenPageMatches() {
        // 12 pages → page boundaries are wide; any value that rounds to the
        // same page as origin should pin exactly to origin.
        let origin = 0.40
        let originPage = ReaderChapterScrub.page(sliderValue: origin, pageCount: 12)
        // Nearby track value on the same page. 0.40 rounds to index 4 (page 5),
        // whose window only spans slider values in [0.318, 0.409] — 0.42 already
        // crosses into index 5 (page 6), so it isn't actually "same page" as the
        // test originally assumed. 0.405 stays inside the window.
        let samePage = 0.405
        #expect(ReaderChapterScrub.page(sliderValue: samePage, pageCount: 12) == originPage)
        #expect(
            ReaderChapterScrub.snapped(value: samePage, toOrigin: origin, pageCount: 12)
                == origin
        )
        // Farther value that still maps to a different page must not snap.
        let otherPage = 0.90
        #expect(ReaderChapterScrub.page(sliderValue: otherPage, pageCount: 12) != originPage)
        #expect(
            ReaderChapterScrub.snapped(value: otherPage, toOrigin: origin, pageCount: 12)
                == otherPage
        )
        #expect(
            ReaderChapterScrub.snapped(value: 0.50, toOrigin: nil, pageCount: 12) == 0.50
        )
    }

    @Test func deviationUsesPageNotRawTrack() {
        // Same page after rounding → not deviated even if track values differ slightly.
        #expect(
            ReaderChapterScrub.isDeviatedFromOrigin(
                sliderValue: 0.50, origin: 0.51, pageCount: 12
            ) == false
        )
        #expect(
            ReaderChapterScrub.isDeviatedFromOrigin(
                sliderValue: 0.90, origin: 0.10, pageCount: 12
            ) == true
        )
        #expect(
            ReaderChapterScrub.isDeviatedFromOrigin(
                sliderValue: 0.5, origin: nil, pageCount: 12
            ) == false
        )
    }
}
