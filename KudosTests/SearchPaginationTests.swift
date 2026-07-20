import Testing
@testable import Kudos

struct SearchPaginationTests {
    @Test func pageAnchorsUseCompactLabels() {
        #expect(SearchPaginationBar.abbreviate(999) == "999")
        #expect(SearchPaginationBar.abbreviate(1_000) == "1k")
        #expect(SearchPaginationBar.abbreviate(1_250) == "1.3k")
        #expect(SearchPaginationBar.abbreviate(1_500_000) == "1.5m")
    }

    @Test func compactWindowKeepsCurrentPageAndNeighbors() {
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 5, totalPages: 10) == 4 ... 6)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 1, totalPages: 10) == 1 ... 2)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 10, totalPages: 10) == 9 ... 10)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 1, totalPages: 1) == 1 ... 1)
    }

    @Test func compactWindowClampsOutOfRangeStateInsteadOfTrapping() {
        // A stale currentPage past a shrunken totalPages built the invalid
        // range 6...5 before the clamp existed.
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 7, totalPages: 5) == 4 ... 5)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 6, totalPages: 5) == 4 ... 5)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 0, totalPages: 5) == 1 ... 2)
        #expect(SearchPaginationBar.compactPageWindow(currentPage: 1, totalPages: 0) == 1 ... 1)
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
