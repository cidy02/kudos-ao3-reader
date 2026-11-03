import Testing
@testable import Kudos

/// The pager above a list shows only on a long page; the one below always shows.
struct TopPagerRuleTests {
    @Test func shortPagesHaveNoTopPager() {
        #expect(!SearchPaginationBar.showsTopPager(rowCount: 2))
        #expect(!SearchPaginationBar.showsTopPager(rowCount: 8))
        #expect(SearchPaginationBar.showsTopPager(rowCount: 9))
    }
}
