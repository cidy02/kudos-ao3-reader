import Foundation
import Testing
@testable import Kudos

@MainActor
struct BrowseBoardCopyTests {
    @Test func categoryFiguresUseTheBoardSeparatorAndKeepUnknownCountsOut() {
        #expect(BrowseBoardCopy.categoryStats(fandomCount: 12, workCount: 48, approximate: true)
                == "12 fandoms · ~48 works")
        #expect(BrowseBoardCopy.categoryStats(fandomCount: 1, workCount: 1, approximate: false)
                == "1 fandom · 1 work")
        #expect(BrowseBoardCopy.categoryStats(fandomCount: 12, workCount: nil, approximate: false)
                == "12 fandoms")
        #expect(BrowseBoardCopy.allFandomsLabel(category: "Books & Literature", count: nil)
                == "All fandoms in Books & Literature")
        #expect(BrowseBoardCopy.allFandomsLabel(category: "Books & Literature", count: 12)
                == "All 12 fandoms in Books & Literature")
    }

    @Test func fandomSelectionReflectsTheAppliedSortAndFilters() {
        #expect(BrowseBoardCopy.selectionFact(selectedCount: 2, sort: "kudos", filters: ["Complete"])
                == "2 selected · sorted by kudos · filters: Complete")
        #expect(BrowseBoardCopy.selectionFact(selectedCount: 0, sort: nil, filters: []) == "0 selected")
    }

    @Test func bulkTagRowsGiveTheExactCoverage() {
        #expect(BrowseBoardCopy.tagCoverage(tagged: 3, selected: 3) == "all 3")
        #expect(BrowseBoardCopy.tagCoverage(tagged: 1, selected: 3) == "1 of 3")
        #expect(BrowseBoardCopy.tagCoverage(tagged: 0, selected: 3) == "none")
    }

    @Test func bookmarkContextOmitsMissingFacts() {
        let words = 18_420.formatted()
        #expect(BrowseBoardCopy.bookmarkMeta(author: "quietharbor", words: 18_420, chapters: "6/6")
                == "quietharbor · \(words) words · 6/6")
        #expect(BrowseBoardCopy.bookmarkMeta(author: "quietharbor", words: nil, chapters: "")
                == "quietharbor")
    }

    @Test func recentlyDeletedExplainsRecoveryAndShowsRealChapters() {
        #expect(BrowseBoardCopy.deletedRecovery(days: 90)
                == "Works stay here for 90 days, then they're gone for good. "
                + "Restoring brings back the EPUB, your progress and your tags.")
        #expect(BrowseBoardCopy.irreplaceableCount(0) == nil)
        #expect(BrowseBoardCopy.irreplaceableCount(1) == "1 of these can't be downloaded again once it's gone.")
        #expect(BrowseBoardCopy.irreplaceableCount(2) == "2 of these can't be downloaded again once they're gone.")
        #expect(BrowseBoardCopy.deletedWorkDetail(words: 0, chapters: "", readingState: "unread") == "unread")
        #expect(BrowseBoardCopy.deletedWorkDetail(words: 25, chapters: "1/1", readingState: "finished")
                == "25 words · 1/1 · finished")
    }

    @Test func deletionCopyNamesTheWork() {
        #expect(BrowseBoardCopy.deleteWorkTitle("Thornfield, Rebuilt") == "Delete “Thornfield, Rebuilt”?")
    }

    @Test func collectionsShowWorkCountHomePlacementAndUpdateDate() {
        #expect(BrowseBoardCopy.emptyCollections == "No collections yet")
        #expect(BrowseBoardCopy.collectionRow(workCount: 12, showsOnHome: true, updatedLabel: "updated today")
                == "12 works · on Home · updated today")
        #expect(BrowseBoardCopy.collectionRow(workCount: 1, showsOnHome: false, updatedLabel: "Oct 20")
                == "1 work · Oct 20")
    }

    @Test func availabilityHistoryAndTheUnsavedLandingUseBoardCopy() {
        #expect(BrowseBoardCopy.availabilityProgress(completed: 38, total: 214) == "38 of 214 · stops if you leave")
        #expect(BrowseBoardCopy.historyHeader(pageFacts: "20 works · page 2 of 12")
                == "On AO3 · 20 works · page 2 of 12 · last visited first")
        #expect(BrowseBoardCopy.unsavedCopy == "You haven’t saved anything on this device yet")
        #expect(BrowseBoardCopy.restrictedWorkMessage == "This work may be available only to logged-in AO3 readers.")
        #expect(AO3ArchivePage.faqs.title == "FAQ")
        #expect(AO3ArchivePage.contentPolicy.title == "Content Policy")
    }
}
