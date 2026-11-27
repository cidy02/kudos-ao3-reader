import Foundation
import Testing
@testable import Kudos

/// Pins the Search board copy, formatting, and ordering rules updated in the T-507
/// detail sweep across `Search`, `Search-Filters`, `Search-Sort`, `Search-Save`,
/// `Search-Saved`, and `Filter-Tags`.
@MainActor
struct SearchBoardCopyTests {
    // MARK: - Search (`Search.dc.html`)

    @Test func fandomRowFormatsCompactCountsAndAccessibleLabels() {
        let lighthouse = AO3Fandom(name: "To the Lighthouse - Virginia Woolf", workCount: 312)
        let single = AO3Fandom(name: "Rare Fandom", workCount: 1)
        let unknown = AO3Fandom(name: "Uncounted Fandom", workCount: nil)

        #expect(SearchAO3FandomRow.countText(for: 312) == "312")
        #expect(SearchAO3FandomRow.countText(for: 48) == "48")
        #expect(SearchAO3FandomRow.countText(for: nil) == nil)

        #expect(
            SearchAO3FandomRow.accessibilityLabel(for: lighthouse)
                == "To the Lighthouse - Virginia Woolf, 312 works"
        )
        #expect(SearchAO3FandomRow.accessibilityLabel(for: single) == "Rare Fandom, 1 work")
        #expect(SearchAO3FandomRow.accessibilityLabel(for: unknown) == "Uncounted Fandom")
    }

    // MARK: - Search-Filters (`Search-Filters.dc.html`)

    @Test func warningChipTitlesMatchBoardShortCopy() {
        #expect(AO3FilterPanel.warningChipTitle(.noWarnings) == "No Warnings Apply")
        #expect(AO3FilterPanel.warningChipTitle(.chooseNotTo) == "Creator Chose Not To Use")
        #expect(AO3FilterPanel.warningChipTitle(.violence) == "Graphic Violence")
        #expect(AO3FilterPanel.warningChipTitle(.death) == "Major Character Death")
        #expect(AO3FilterPanel.warningChipTitle(.nonCon) == "Rape/Non-Con")
        #expect(AO3FilterPanel.warningChipTitle(.underage) == "Underage Sex")
    }

    @Test func completionSegmentTitlesMatchBoardSegments() {
        #expect(AO3FilterPanel.completionSegmentTitle(.any) == "Any")
        #expect(AO3FilterPanel.completionSegmentTitle(.complete) == "Complete")
        #expect(AO3FilterPanel.completionSegmentTitle(.inProgress) == "WIP")
    }

    @Test func ratingWordsAndPopularityLabelsMatchBoardFormatting() {
        #expect(AO3FilterPanel.ratingActiveLabel(rating: .teen, match: .exact) == "Teen And Up")
        #expect(AO3FilterPanel.ratingActiveLabel(rating: .teen, match: .orHigher) == "Teen And Up+")
        #expect(AO3FilterPanel.ratingActiveLabel(rating: .teen, match: .orLower) == "Teen And Up−")

        #expect(AO3FilterPanel.compactFilterNumber("10000") == "10k")
        #expect(AO3FilterPanel.compactFilterNumber("60000") == "60k")
        #expect(AO3FilterPanel.compactFilterNumber("1000") == "1k")
        #expect(AO3FilterPanel.compactFilterNumber("1500") == 1_500.formatted())

        #expect(AO3FilterPanel.wordsActiveLabel(from: "10000", to: "60000") == "10k–60k words")
        #expect(AO3FilterPanel.wordsActiveLabel(from: "10000", to: "") == "10k+ words")
        #expect(AO3FilterPanel.wordsActiveLabel(from: "", to: "1000") == "Under 1k words")
        #expect(AO3FilterPanel.wordsActiveLabel(from: "", to: "100000") == "Under 100k words")
        #expect(AO3FilterPanel.wordsActiveLabel(from: "", to: "") == nil)

        #expect(AO3FilterPanel.popularityActiveLabel(name: "kudos", from: "100", to: "") == "100+ kudos")
        #expect(AO3FilterPanel.popularityActiveLabel(name: "kudos", from: "100", to: "500") == "100–500 kudos")
        #expect(AO3FilterPanel.popularityActiveLabel(name: "hits", from: "", to: "500") == "Up to 500 hits")
        #expect(AO3FilterPanel.popularityActiveLabel(name: "kudos", from: "", to: "") == nil)

        #expect(AO3FilterPanel.rangeRowSummary(from: "", to: "") == "Any")
        #expect(AO3FilterPanel.rangeRowSummary(from: "100", to: "") == "100 or more")
        #expect(AO3FilterPanel.rangeRowSummary(from: "1000", to: "") == "\(1_000.formatted()) or more")
        #expect(AO3FilterPanel.rangeRowSummary(from: "", to: "500") == "Up to 500")
        #expect(AO3FilterPanel.rangeRowSummary(from: "100", to: "500") == "100–500")
    }

    @Test func tagSelectFieldShowsAddWhenEmptyAndHidesRedundantSummaryWhenFilled() {
        #expect(TagSelectField.selectionSummary(includedCount: 0, excludedCount: 0) == "Add")
        #expect(TagSelectField.selectionSummary(includedCount: 1, excludedCount: 0) == nil)
        #expect(TagSelectField.selectionSummary(includedCount: 0, excludedCount: 1) == nil)

        #expect(
            TagSelectField.buttonAccessibilityLabel(title: "Fandoms", included: [], excluded: [])
                == "Fandoms, Add"
        )
        #expect(
            TagSelectField.buttonAccessibilityLabel(
                title: "Additional Tags",
                included: ["Found Family"],
                excluded: ["Major Character Death"]
            ) == "Additional Tags, 1 included, 1 excluded"
        )
    }

    // MARK: - Search-Sort (`Search-Sort.dc.html`)

    @Test func sortByColumnOrderAndCopyMatchBoard() {
        #expect(
            SearchSortByView.displayedColumns(allowsRelevanceSort: true)
                == [
                    .relevance, .dateUpdated, .datePosted, .workTitle, .creator,
                    .words, .hits, .kudos, .comments, .bookmarks,
                ]
        )
        #expect(
            SearchSortByView.displayedColumns(allowsRelevanceSort: false)
                == [
                    .dateUpdated, .datePosted, .workTitle, .creator,
                    .words, .hits, .kudos, .comments, .bookmarks,
                ]
        )
        #expect(LoadedWorksRank.momentum.subtitle == "Kudos gained since you last saw each work")
        #expect(
            SearchSortByView.rankingFooter(rankTop100Enabled: true)
                == "Ranks the works already loaded, or up to 100 at once with Rank Top 100."
        )
        #expect(
            SearchSortByView.rankingFooter(rankTop100Enabled: false)
                == "Ranks only the works already loaded from AO3. Kudos never loads extra pages to rank."
        )
    }

    @Test func sortByTopLoadedResultPreviewFormatsActiveRank() {
        let now = WorkStat.date(from: "29 Oct 2026") ?? Date(timeIntervalSince1970: 0)
        let works = [
            sampleWork(id: 1, kudos: 50, hits: 1_000, bookmarks: 10),
            sampleWork(id: 2, kudos: 100, hits: 1_000, bookmarks: 25),
            sampleWork(id: 3, kudos: 240, hits: 1_000, bookmarks: 60),
        ]
        var settings = LoadedWorksRanking()
        settings.ranksCautiously = false

        #expect(
            SearchSortByView.topLoadedResultLine(for: .ao3Order, works: works, settings: settings, now: now)
                == nil
        )
        #expect(
            SearchSortByView.topLoadedResultLine(
                for: .kudosPerHitAdjusted, works: [], settings: settings, now: now
            ) == nil
        )
        #expect(
            SearchSortByView.topLoadedResultLine(
                for: .kudosPerHitAdjusted, works: works, settings: settings, now: now
            ) == "Top loaded result: 2.4× typical"
        )
        #expect(
            SearchSortByView.topLoadedResultLine(
                for: .savesPerKudos, works: works, settings: settings, now: now
            ) == "Top loaded result: 25% saved"
        )
        #expect(
            SearchSortByView.topLoadedResultLine(
                for: .momentum,
                works: works,
                settings: settings,
                previousKudos: [3: 200],
                now: now
            ) == "Top loaded result: +40 kudos"
        )
    }

    // MARK: - Search-Save (`Search-Save.dc.html`)

    @Test func saveSearchContextAndChipsMatchBoardCopy() {
        #expect(SaveSearchPresentation.contextKicker(totalWorks: nil) == "AO3 search")
        #expect(SaveSearchPresentation.contextKicker(totalWorks: 1) == "AO3 search · 1 work")
        #expect(
            SaveSearchPresentation.contextKicker(totalWorks: 1_284)
                == "AO3 search · \(1_284.formatted()) works"
        )
        #expect(SaveSearchPresentation.emptyFiltersText == "No filters selected")

        var filters = AO3SearchFilters()
        filters.fandom = "Persuasion"
        filters.relationships = "Anne/Wentworth"
        filters.excludedWarnings = [.death]
        filters.completion = .complete
        filters.sort = .kudos
        filters.sortDirection = .descending

        #expect(SaveSearchPresentation.contextTitle(for: filters) == "Persuasion · Anne/Wentworth")
        #expect(SaveSearchPresentation.contextMeta(for: filters) == "Complete only · sorted by kudos")
        #expect(SaveSearchPresentation.sortChipText(for: filters) == "Kudos ↓")

        let chips = SaveSearchPresentation.chips(for: filters)
        #expect(chips.contains(where: { $0.text == "Persuasion" && $0.kind == .included }))
        #expect(chips.contains(where: { $0.text == "Anne/Wentworth" && $0.kind == .included }))
        #expect(chips.contains(where: { $0.text == "Major Character Death" && $0.kind == .excluded }))
        #expect(chips.contains(where: { $0.text == "Complete" && $0.kind == .facet }))
        #expect(chips.contains(where: { $0.text == "Kudos ↓" && $0.kind == .facet }))

        var ascending = AO3SearchFilters()
        ascending.sort = .workTitle
        ascending.sortDirection = .ascending
        #expect(SaveSearchPresentation.sortChipText(for: ascending) == "Title ↑")

        #expect(SaveSearchPresentation.contextTitle(for: AO3SearchFilters()) == "AO3 Search")
        #expect(SaveSearchPresentation.contextMeta(for: AO3SearchFilters()) == nil)
        #expect(SaveSearchPresentation.chips(for: AO3SearchFilters()).isEmpty)
    }

    // MARK: - Search-Saved (`Search-Saved.dc.html`)

    @Test func savedSearchRowPresentationMatchesBoardMetaAndIcons() {
        #expect(SavedSearchRowPresentation.countSubtitle(1) == "1 search")
        #expect(SavedSearchRowPresentation.countSubtitle(4) == "4 searches")

        var holmes = AO3SearchFilters()
        holmes.fandom = "Sherlock Holmes"
        holmes.categories = [.gen]
        holmes.wordsTo = "20000"
        #expect(SavedSearchRowPresentation.symbol(for: holmes) == "tag")
        #expect(
            SavedSearchRowPresentation.subtitle(for: holmes)
                == "Sherlock Holmes · Gen · under \(20_000.formatted()) words"
        )

        var textSearch = AO3SearchFilters(query: "epistolary")
        textSearch.rating = .teen
        textSearch.ratingMatch = .orLower
        #expect(SavedSearchRowPresentation.symbol(for: textSearch) == "magnifyingglass")
        #expect(
            SavedSearchRowPresentation.subtitle(for: textSearch)
                == "“epistolary” · Teen And Up and below"
        )

        #expect(SavedSearchRowPresentation.subtitle(for: AO3SearchFilters()) == nil)
    }

    // MARK: - Filter-Tags (`Filter-Tags.dc.html`)

    @Test func tagPickerCopyMatchesBoardHeadersAndPrompts() {
        #expect(TagPickerCopy.resultsSectionHeader(query: "fluff") == "Matching “fluff”")
        #expect(TagPickerCopy.resultsSectionHeader(query: "  ") == "Results")
        #expect(TagPickerCopy.popularSectionHeader(fandom: "Sherlock Holmes") == "Popular in Sherlock Holmes")
        #expect(TagPickerCopy.noResultsText(query: "fluff") == "No tags found for “fluff”.")
        #expect(
            TagPickerCopy.searchPromptText(title: "Additional Tags")
                == "Type above to search AO3 additional tags."
        )
        #expect(
            TagPickerCopy.fandomSuggestionHint(title: "Characters")
                == "Choose a fandom to see its most-used characters here."
        )
        #expect(TagPickerCopy.rowSymbol(for: .fandom) == "books.vertical")
        #expect(TagPickerCopy.rowSymbol(for: .character) == "person")
        #expect(TagPickerCopy.rowSymbol(for: .relationship) == "heart")
        #expect(TagPickerCopy.rowSymbol(for: .freeform) == "tag")
        #expect(TagPickerCopy.rowSymbol(for: .tag) == "tag")
    }

    // MARK: - Helpers

    private func sampleWork(id: Int, kudos: Int, hits: Int, bookmarks: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Work \(id)",
            authors: ["Author"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "Teen And Up Audiences",
            warnings: [],
            categories: [],
            isComplete: true,
            dateUpdated: "01 Oct 2026",
            tags: [],
            summary: "",
            language: "English",
            words: 5_000,
            chapters: "1/1",
            comments: 0,
            kudos: kudos,
            bookmarks: bookmarks,
            hits: hits,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }
}
