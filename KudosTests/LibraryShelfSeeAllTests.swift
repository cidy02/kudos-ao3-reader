import Testing
@testable import Kudos

/// Tests for Library shelf header "See All" links and destinations (FID46).
@MainActor
struct LibraryShelfSeeAllTests {
    @Test func everyLibraryShelfHasDestination() {
        for shelf in LibraryShelfID.allCases {
            let destination = LibraryShelfDestination.destination(for: shelf)
            #expect(destination != nil)

            switch shelf {
            case .favourites:
                let expected = LibrarySectionRoute(kind: .favorites, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .collections:
                #expect(destination as? AllCollectionsDestination == AllCollectionsDestination())
            case .downloaded:
                let expected = LibrarySectionRoute(kind: .downloaded, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .wantToRead:
                let expected = LibrarySectionRoute(kind: .savedForLater, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .readingNow:
                let expected = LibrarySectionRoute(kind: .readingNow, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .finished:
                let expected = LibrarySectionRoute(kind: .finished, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .queues:
                let expected = AllReadingQueuesDestination(initialQueueID: nil)
                #expect(destination as? AllReadingQueuesDestination == expected)
            case .history:
                let expected = LibrarySectionRoute(kind: .history, originKicker: "Library")
                #expect(destination as? LibrarySectionRoute == expected)
            case .imported:
                let expected = LibraryCatalogueDestination(kind: .imported)
                #expect(destination as? LibraryCatalogueDestination == expected)
            }
        }
    }

    @Test func shelfHeaderSeeAllDecisionWithActionTitle() {
        // When shelf items fit (e.g. 4 collections on shelf, 4 visible), "See All" actionTitle ensures the link is shown
        let fittingDecision = SectionSeeAllDecision(totalCount: 4, visibleCount: 4, actionTitleWhenFitting: "See All")
        #expect(fittingDecision.headerLinkLabel == "See All")
        #expect(fittingDecision.isSomethingHidden == false)
        #expect(fittingDecision.showsCarouselMoreTile == false)

        // When shelf items exceed visible capacity (e.g. 19 favourites, 12 visible), "See All" is shown with closer
        let hiddenDecision = SectionSeeAllDecision(totalCount: 19, visibleCount: 12, actionTitleWhenFitting: "See All")
        #expect(hiddenDecision.headerLinkLabel == "See All")
        #expect(hiddenDecision.isSomethingHidden == true)
        #expect(hiddenDecision.showsCarouselMoreTile == true)

        // When shelf is empty, no "See All" header link is shown
        let emptyDecision = SectionSeeAllDecision(totalCount: 0, visibleCount: 0, actionTitleWhenFitting: "See All")
        #expect(emptyDecision.headerLinkLabel == nil)
    }
}
