import Testing
@testable import Kudos

struct SearchPaginationTests {
    @Test func pageAnchorsUseCompactLabels() {
        #expect(SearchPaginationBar.abbreviate(999) == "999")
        #expect(SearchPaginationBar.abbreviate(1_000) == "1k")
        #expect(SearchPaginationBar.abbreviate(1_250) == "1.3k")
        #expect(SearchPaginationBar.abbreviate(1_500_000) == "1.5m")
    }

    // `compactPageWindow` and its two tests went with the scrubber's three
    // numbered circles: the readout above them already stated the page, so the
    // middle circle was the same number a third time. A −/+ pair replaced them
    // and needed no window.
    //
    // Artboard 1k then replaced the scrubber outright with a number field and a
    // grid of nearby pages, which needs a window again — a different one, ten
    // wide, and the interesting part is what it does at the ends.

    @Test func nearbyWindowCentresOnTheCurrentPage() {
        #expect(SearchPaginationBar.nearbyPageWindow(around: 100, totalPages: 3_216)
            == Array(96 ... 105))
    }

    @Test func nearbyWindowSlidesInsteadOfTruncatingAtTheEnds() {
        // Page 2 of a long list still offers ten choices, not two: the window
        // slides back inside the range rather than being cut off by it.
        #expect(SearchPaginationBar.nearbyPageWindow(around: 2, totalPages: 3_216)
            == Array(1 ... 10))
        #expect(SearchPaginationBar.nearbyPageWindow(around: 3_216, totalPages: 3_216)
            == Array(3_207 ... 3_216))
    }

    @Test func nearbyWindowShrinksToShortLists() {
        #expect(SearchPaginationBar.nearbyPageWindow(around: 2, totalPages: 3) == [1, 2, 3])
        #expect(SearchPaginationBar.nearbyPageWindow(around: 1, totalPages: 1) == [1])
    }

    @Test func nearbyWindowIsEmptyWithNoPages() {
        // Defends the `totalPages - windowSize + 1` arithmetic, which would
        // otherwise produce a negative range rather than nothing.
        #expect(SearchPaginationBar.nearbyPageWindow(around: 1, totalPages: 0).isEmpty)
    }

    @Test func arrowsUseTapForAdjacentAndLongPressForEnds() {
        #expect(SearchPaginationBar.navigationPage(
            .backward, longPress: false, currentPage: 20, totalPages: 100
        ) == 19)
        #expect(SearchPaginationBar.navigationPage(
            .backward, longPress: true, currentPage: 20, totalPages: 100
        ) == 1)
        #expect(SearchPaginationBar.navigationPage(
            .forward, longPress: false, currentPage: 20, totalPages: 100
        ) == 21)
        #expect(SearchPaginationBar.navigationPage(
            .forward, longPress: true, currentPage: 20, totalPages: 100
        ) == 100)
    }
}
