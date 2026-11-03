import Testing
@testable import Kudos

struct AO3ResultListPagingTests {
    @Test func titleFormattingPrefersSubjectOverQuery() {
        #expect(AO3ResultListPaging.title(subject: "Sherlock Holmes", query: "lighthouse") == "Sherlock Holmes")
        #expect(AO3ResultListPaging.title(subject: "  Doctor Who  ", query: nil) == "Doctor Who")
    }

    @Test func titleFormattingQuotesQueryWhenSubjectAbsent() {
        #expect(AO3ResultListPaging.title(subject: nil, query: "lighthouse") == "“lighthouse”")
        #expect(AO3ResultListPaging.title(subject: "lighthouse", query: "lighthouse") == "“lighthouse”")
        #expect(AO3ResultListPaging.title(subject: "", query: "enemies to lovers") == "“enemies to lovers”")
        #expect(AO3ResultListPaging.title(subject: "   ", query: "slow burn") == "“slow burn”")
    }

    @Test func titleFormattingFallsBackWhenBothAbsent() {
        #expect(AO3ResultListPaging.title(subject: nil, query: nil) == "Search Results")
        #expect(AO3ResultListPaging.title(subject: "", query: "") == "Search Results")
        #expect(AO3ResultListPaging.title(subject: "  ", query: "   ") == "Search Results")
    }

    @Test func titleFormattingShowsOnAO3WhenLibrarySectionsPresent() {
        #expect(AO3ResultListPaging.title(subject: "Sherlock Holmes", query: "lighthouse", hasLibrarySections: true) == "On AO3")
        #expect(AO3ResultListPaging.title(subject: nil, query: "Sodium", hasLibrarySections: true) == "On AO3")
        #expect(AO3ResultListPaging.title(subject: nil, query: nil, hasLibrarySections: true) == "On AO3")
    }

    @Test func countTextFormattingMatchesBoard11() {
        #expect(AO3ResultListPaging.countText(total: 1) == "1 work")
        #expect(AO3ResultListPaging.countText(total: 1_284) == "1,284 works")
        #expect(AO3ResultListPaging.countText(total: 0) == "0 works")
    }

    @Test func subtitleFormattingCountsWorks() {
        #expect(AO3ResultListPaging.subtitle(total: 1) == "1 work on AO3")
        #expect(AO3ResultListPaging.subtitle(total: 2_431) == "2,431 works on AO3")
        #expect(AO3ResultListPaging.subtitle(total: 0) == "0 works on AO3")
    }

    @Test func footerLoadingTextMatchesBoard18() {
        #expect(
            AO3ResultListPaging.footerLoadingText(loaded: 120, total: 2_431, page: 2)
            == "120 of 2,431 · loading page 2"
        )
        #expect(
            AO3ResultListPaging.footerLoadingText(loaded: 20, total: 1_284, page: 2)
            == "20 of 1_284 · loading page 2".replacingOccurrences(of: "1_284", with: 1284.formatted())
        )
    }

    @Test func footerLoadedTextHandlesTotalsAndFallbacks() {
        #expect(AO3ResultListPaging.footerLoadedText(loaded: 120, total: 2_431) == "120 of 2,431 works")
        #expect(AO3ResultListPaging.footerLoadedText(loaded: 1, total: 0) == "1 work")
        #expect(AO3ResultListPaging.footerLoadedText(loaded: 5, total: 0) == "5 works")
    }

    @Test func appendUniqueDeduplicatesAndPreservesOrder() {
        let work1 = makeWork(id: 101, title: "Work 1")
        let work2 = makeWork(id: 102, title: "Work 2")
        let work3 = makeWork(id: 103, title: "Work 3")
        let duplicateWork2 = makeWork(id: 102, title: "Work 2 (Duplicate)")

        let initial = [work1, work2]
        let incoming = [duplicateWork2, work3]

        let combined = AO3ResultListPaging.appendUnique(newWorks: incoming, to: initial)
        #expect(combined.count == 3)
        #expect(combined.map(\.id) == [101, 102, 103])
        #expect(combined[1].title == "Work 2")
    }

    @Test func rankLookaheadAdvancesOrdinaryPagingPastItsLoadedPages() {
        #expect(AO3ResultListPaging.furthestLoadedPage(currentPage: 1, loadedPages: [1, 2, 3, 4, 5]) == 5)
        #expect(AO3ResultListPaging.furthestLoadedPage(currentPage: 4, loadedPages: [1, 2]) == 4)
        #expect(AO3ResultListPaging.furthestLoadedPage(currentPage: 2, loadedPages: []) == 2)
    }

    private func makeWork(id: Int, title: String) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: [],
            authorIdentities: [],
            fandoms: [],
            rating: "",
            warnings: [],
            categories: [],
            isComplete: nil,
            dateUpdated: "01 Oct 2026",
            tags: [],
            summary: "",
            language: "",
            words: 1000,
            chapters: "1/1",
            comments: 0,
            kudos: 0,
            bookmarks: 0,
            hits: 0,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }
}
