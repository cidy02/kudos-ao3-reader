import Testing
@testable import Kudos

/// Home's "Reading Now" header counts only the cards under it, excluding the
/// Resume hero card shown above the header (T-551).
@MainActor
struct HomeReadingNowCountTests {
    @Test func readingNowCountExcludesHeroCard() {
        let threeInProgress = HomeReadingNowCount.shelfCounts(total: 3)
        #expect(threeInProgress.sectionCount == 2)
        #expect(threeInProgress.visibleCount == 2)

        let fittingDecision = SectionSeeAllDecision(
            totalCount: threeInProgress.sectionCount,
            visibleCount: threeInProgress.visibleCount
        )
        #expect(fittingDecision.hiddenCount == 0)
        #expect(fittingDecision.headerLinkLabel == nil)
        #expect(fittingDecision.showsCarouselMoreTile == false)
    }

    @Test func readingNowOverflowLeavesHeroOutOfHeaderAndMoreTile() {
        let sixInProgress = HomeReadingNowCount.shelfCounts(total: 6)
        #expect(sixInProgress.sectionCount == 5)
        #expect(sixInProgress.visibleCount == 3)

        let overflowDecision = SectionSeeAllDecision(
            totalCount: sixInProgress.sectionCount,
            visibleCount: sixInProgress.visibleCount
        )
        #expect(overflowDecision.hiddenCount == 2)
        #expect(overflowDecision.headerLinkLabel == "See All")
        #expect(overflowDecision.showsCarouselMoreTile == true)
    }

    @Test func singleInProgressWorkHasZeroUnderHeader() {
        let oneInProgress = HomeReadingNowCount.shelfCounts(total: 1)
        #expect(oneInProgress.sectionCount == 0)
        #expect(oneInProgress.visibleCount == 0)

        let empty = HomeReadingNowCount.shelfCounts(total: 0)
        #expect(empty.sectionCount == 0)
        #expect(empty.visibleCount == 0)
    }
}
