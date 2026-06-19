import Testing
@testable import Kudos

struct SearchPaginationTests {
    @Test func pageAnchorsUseCompactLabels() {
        #expect(SearchPaginationBar.abbreviate(999) == "999")
        #expect(SearchPaginationBar.abbreviate(1_000) == "1k")
        #expect(SearchPaginationBar.abbreviate(1_250) == "1.3k")
        #expect(SearchPaginationBar.abbreviate(1_500_000) == "1.5m")
    }
}
