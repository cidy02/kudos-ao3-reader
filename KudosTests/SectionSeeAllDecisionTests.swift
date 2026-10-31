import Testing
@testable import Kudos

/// Tests for the See All and "+N more" / "N more" closer decision rules (T-483).
@MainActor
struct SectionSeeAllDecisionTests {
    @Test func itemsHiddenShowsSeeAllAndCloser() {
        // Shelf with 7 works total, 4 visible (Board 00 Reading Now)
        let decision = SectionSeeAllDecision(totalCount: 7, visibleCount: 4)
        #expect(decision.isSomethingHidden == true)
        #expect(decision.hiddenCount == 3)
        #expect(decision.headerLinkLabel == "See All")
        #expect(decision.showsCarouselMoreTile == true)
        #expect(decision.showsListMoreRow == true)
    }

    @Test func allItemsFitHidesSeeAllAndCloser() {
        // Shelf where all 4 items fit
        let decision = SectionSeeAllDecision(totalCount: 4, visibleCount: 4)
        #expect(decision.isSomethingHidden == false)
        #expect(decision.hiddenCount == 0)
        #expect(decision.headerLinkLabel == nil)
        #expect(decision.showsCarouselMoreTile == false)
        #expect(decision.showsListMoreRow == false)
    }

    @Test func allItemsFitWithActionNamesAction() {
        // Reading queues where all 3 queues fit: link names action "Organise" (Board 56)
        let decision = SectionSeeAllDecision(totalCount: 3, visibleCount: 3, actionTitleWhenFitting: "Organise")
        #expect(decision.isSomethingHidden == false)
        #expect(decision.hiddenCount == 0)
        #expect(decision.headerLinkLabel == "Organise")
        #expect(decision.showsCarouselMoreTile == false)
        #expect(decision.showsListMoreRow == false)
    }

    @Test func hiddenItemsOverrideActionTitleWithSeeAll() {
        // Reading queues when count exceeds shelf visible limit (15 queues, 12 visible)
        let decision = SectionSeeAllDecision(totalCount: 15, visibleCount: 12, actionTitleWhenFitting: "Organise")
        #expect(decision.isSomethingHidden == true)
        #expect(decision.hiddenCount == 3)
        #expect(decision.headerLinkLabel == "See All")
        #expect(decision.showsCarouselMoreTile == true)
        #expect(decision.showsListMoreRow == true)
    }

    @Test func shelvesSectionEditActionWhenFitting() {
        // Shelves with "Edit" action when all shelves fit (Board 01)
        let decision = SectionSeeAllDecision(totalCount: 4, visibleCount: 4, actionTitleWhenFitting: "Edit")
        #expect(decision.isSomethingHidden == false)
        #expect(decision.headerLinkLabel == "Edit")
    }

    @Test func emptySectionShowsNoLinkAndNoCloser() {
        let decision = SectionSeeAllDecision(totalCount: 0, visibleCount: 0, actionTitleWhenFitting: "Organise")
        #expect(decision.isSomethingHidden == false)
        #expect(decision.hiddenCount == 0)
        #expect(decision.headerLinkLabel == nil)
        #expect(decision.showsCarouselMoreTile == false)
        #expect(decision.showsListMoreRow == false)
    }

    @Test func listWithManyHiddenItems() {
        // Subscriptions list: 27 total, 2 displayed in preview (Board 00)
        let decision = SectionSeeAllDecision(totalCount: 27, visibleCount: 2)
        #expect(decision.isSomethingHidden == true)
        #expect(decision.hiddenCount == 25)
        #expect(decision.headerLinkLabel == "See All")
        #expect(decision.showsListMoreRow == true)
    }

    @Test func negativeCountsAreClamped() {
        let decision = SectionSeeAllDecision(totalCount: -5, visibleCount: -1)
        #expect(decision.totalCount == 0)
        #expect(decision.visibleCount == 0)
        #expect(decision.isSomethingHidden == false)
        #expect(decision.hiddenCount == 0)
        #expect(decision.headerLinkLabel == nil)
    }
}
