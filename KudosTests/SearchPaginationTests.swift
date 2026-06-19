import Testing
@testable import Kudos

struct SearchPaginationTests {
    @Test func pageAnchorsUseCompactLabels() {
        #expect(SearchPaginationBar.abbreviate(999) == "999")
        #expect(SearchPaginationBar.abbreviate(1_000) == "1k")
        #expect(SearchPaginationBar.abbreviate(1_250) == "1.3k")
        #expect(SearchPaginationBar.abbreviate(1_500_000) == "1.5m")
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
