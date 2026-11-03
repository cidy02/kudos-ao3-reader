import Foundation
import Testing
@testable import Kudos

struct SearchCombinedResultsLogicTests {
    @Test func hasLibrarySectionsDetectsAnyMatchingSection() {
        // All zero -> false
        #expect(!SearchCombinedResultsLogic.hasLibrarySections(
            worksCount: 0,
            chipsCount: 0,
            ao3FandomsCount: 0
        ))

        // Works only -> true
        #expect(SearchCombinedResultsLogic.hasLibrarySections(
            worksCount: 2,
            chipsCount: 0,
            ao3FandomsCount: 0
        ))

        // Chips only -> true
        #expect(SearchCombinedResultsLogic.hasLibrarySections(
            worksCount: 0,
            chipsCount: 3,
            ao3FandomsCount: 0
        ))

        // AO3 fandoms only -> true
        #expect(SearchCombinedResultsLogic.hasLibrarySections(
            worksCount: 0,
            chipsCount: 0,
            ao3FandomsCount: 1
        ))

        // All present -> true
        #expect(SearchCombinedResultsLogic.hasLibrarySections(
            worksCount: 2,
            chipsCount: 3,
            ao3FandomsCount: 2
        ))
    }

    @Test func sectionVisibilityChecksIndividualCounts() {
        #expect(!SearchCombinedResultsLogic.showInLibrarySection(worksCount: 0))
        #expect(SearchCombinedResultsLogic.showInLibrarySection(worksCount: 1))

        #expect(!SearchCombinedResultsLogic.showChipsSection(chipsCount: 0))
        #expect(SearchCombinedResultsLogic.showChipsSection(chipsCount: 1))

        #expect(!SearchCombinedResultsLogic.showAO3FandomsSection(ao3FandomsCount: 0))
        #expect(SearchCombinedResultsLogic.showAO3FandomsSection(ao3FandomsCount: 1))
    }


    @Test func libraryWorkCapAndSeeAllRowLogic() {
        #expect(SearchCombinedResultsLogic.libraryRowCap == 5)

        // 3 works: displays all 3, no "See all" row
        #expect(SearchCombinedResultsLogic.displayedWorksCount(total: 3, isExpanded: false) == 3)
        #expect(!SearchCombinedResultsLogic.showsSeeAllRow(total: 3, isExpanded: false))

        // 5 works: displays all 5, no "See all" row
        #expect(SearchCombinedResultsLogic.displayedWorksCount(total: 5, isExpanded: false) == 5)
        #expect(!SearchCombinedResultsLogic.showsSeeAllRow(total: 5, isExpanded: false))

        // 8 works, unexpanded: displays 5, shows "See all 8" row
        #expect(SearchCombinedResultsLogic.displayedWorksCount(total: 8, isExpanded: false) == 5)
        #expect(SearchCombinedResultsLogic.showsSeeAllRow(total: 8, isExpanded: false))
        #expect(SearchCombinedResultsLogic.seeAllRowTitle(total: 8) == "See all 8")

        // 8 works, expanded: displays 8, hides "See all" row
        #expect(SearchCombinedResultsLogic.displayedWorksCount(total: 8, isExpanded: true) == 8)
        #expect(!SearchCombinedResultsLogic.showsSeeAllRow(total: 8, isExpanded: true))
    }

    @Test func ao3HeaderTitleChoiceMatchesSpec() {
        // When library sections are present above, header title is always "On AO3"
        #expect(SearchCombinedResultsLogic.ao3HeaderTitle(
            hasLibrarySections: true,
            subject: "Sherlock Holmes",
            query: "lighthouse"
        ) == "On AO3")

        #expect(SearchCombinedResultsLogic.ao3HeaderTitle(
            hasLibrarySections: true,
            subject: nil,
            query: "Sodium"
        ) == "On AO3")

        // When library sections are absent, header title retains today's title
        #expect(SearchCombinedResultsLogic.ao3HeaderTitle(
            hasLibrarySections: false,
            subject: "Sherlock Holmes",
            query: "lighthouse"
        ) == "Sherlock Holmes")

        #expect(SearchCombinedResultsLogic.ao3HeaderTitle(
            hasLibrarySections: false,
            subject: nil,
            query: "Sodium"
        ) == "“Sodium”")
    }

    @Test func ao3HeaderCountFormatting() {
        #expect(SearchCombinedResultsLogic.ao3HeaderCount(total: 1) == "1 work")
        #expect(SearchCombinedResultsLogic.ao3HeaderCount(total: 1_284) == "1,284 works")
        #expect(SearchCombinedResultsLogic.ao3HeaderCount(total: 0) == "0 works")
    }

    @Test func localChipsConstructionAndOrdering() {
        let colUUID = UUID()
        let chips = SearchLocalChip.makeChips(
            tags: [("lighthouses", 4)],
            collections: [(colUUID, "Comfort Reads", 1)],
            fandoms: [("Original Work", 3)]
        )

        #expect(chips.count == 3)
        #expect(chips[0].kind == .tag)
        #expect(chips[0].label == "lighthouses")
        #expect(chips[0].count == 4)
        #expect(chips[0].target == .tag("lighthouses"))

        #expect(chips[1].kind == .collection)
        #expect(chips[1].label == "Comfort Reads")
        #expect(chips[1].count == 1)
        #expect(chips[1].target == .collection(colUUID, name: "Comfort Reads"))

        #expect(chips[2].kind == .fandom)
        #expect(chips[2].label == "Original Work")
        #expect(chips[2].count == 3)
        #expect(chips[2].target == .fandom("Original Work"))
    }
}
