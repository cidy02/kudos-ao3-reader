import Foundation
import Testing
@testable import Kudos

/// Pins the results card's filter chips. These are the only place the app says
/// what is narrowing a list once the panel is dismissed, so the rule that matters
/// is: everything active is named, and nothing inactive is.
struct FilterSummaryLabelTests {
    @Test func anUntouchedFilterSetNamesOnlyItsSort() {
        // The point of the card is to be quiet when nothing is set. "Any rating"
        // and "All" are the *absence* of a filter, and listing them would spend the
        // card's height saying nothing — loudest in the commonest state.
        #expect(AO3SearchFilters().summaryLabels().map(\.text) == ["Sort: Best Match"])
    }

    @Test func theSortIsAlwaysNamedEvenAtItsDefault() {
        // Unlike every other entry there is always an order in effect, so this is
        // the one label that is never noise — and it is the setting users most
        // often forget they changed.
        var filters = AO3SearchFilters()
        filters.sort = .kudos
        #expect(filters.summaryLabels().map(\.text).last == "Sort: Kudos")
        #expect(AO3SearchFilters().summaryLabels().map(\.text).last == "Sort: Best Match")
    }

    @Test func aTagChipCarriesItsCategoryGlyphInsteadOfAWordyPrefix() {
        // The category used to be spelled out ("Fandom: Naruto"). AO3 hands tags
        // over already grouped by category, so the glyph can carry it and the chip
        // gets its width back for the tag itself.
        var filters = AO3SearchFilters()
        filters.fandom = "Naruto"
        filters.characters = "Sasuke Uchiha"
        filters.excludedAdditionalTags = "Time Travel"
        filters.warnings = [.violence]
        let labels = filters.summaryLabels()
        #expect(labels.contains(where: { $0.text == "Naruto" && $0.symbol == "books.vertical" }))
        #expect(labels.contains(where: { $0.text == "Sasuke Uchiha" && $0.symbol == "person" }))
        #expect(labels.contains(where: { $0.text == "−Time Travel" && $0.symbol == "tag" }))
        #expect(labels.contains(where: {
            $0.text == "Graphic Depictions Of Violence" && $0.symbol == "exclamationmark.triangle"
        }))
        // Facets are not tag categories, so they get no glyph rather than a
        // misleading one.
        #expect(labels.first(where: { $0.text.hasPrefix("Sort:") })?.symbol == nil)
    }

    @Test func theCardsOwnSubjectIsNotRepeatedAsAChip() {
        // On a fandom's page the heading already says "Naruto (Anime & Manga)".
        // Repeating it as "Fandom: Naruto (Anime & Manga)" wastes the one line the
        // chips get. A *different* fandom still shows, because that one is news.
        var filters = AO3SearchFilters()
        filters.fandom = "Naruto (Anime & Manga), Bleach"
        let labels = filters.summaryLabels(excluding: "Naruto (Anime & Manga)").map(\.text)
        #expect(!labels.contains("Naruto (Anime & Manga)"))
        #expect(labels.contains("Bleach"))
        // With no subject to exclude — the Search tab — both show.
        #expect(filters.summaryLabels().map(\.text).contains("Naruto (Anime & Manga)"))
    }

    @Test func exclusionsAreMarkedAsExclusions() {
        var filters = AO3SearchFilters()
        filters.additionalTags = "Fluff"
        filters.excludedAdditionalTags = "Time Travel"
        filters.excludedWarnings = [.underage]
        let labels = filters.summaryLabels().map(\.text)
        #expect(labels.contains("Fluff"))
        #expect(labels.contains("−Time Travel"))
        #expect(labels.contains("−Underage Sex"))
    }

    @Test func aRatingCarriesItsMatchDirection() {
        var filters = AO3SearchFilters()
        filters.rating = .teen
        filters.ratingMatch = .exact
        #expect(filters.summaryLabels().map(\.text).contains("Teen And Up"))
        filters.ratingMatch = .orHigher
        #expect(filters.summaryLabels().map(\.text).contains("Teen And Up+"))
        filters.ratingMatch = .orLower
        #expect(filters.summaryLabels().map(\.text).contains("Teen And Up−"))
    }

    @Test func numericRangesReadAsRanges() {
        var filters = AO3SearchFilters()
        filters.wordsFrom = "1000"
        filters.wordsTo = "5000"
        filters.kudosFrom = "100"
        filters.hitsTo = "500"
        let labels = filters.summaryLabels().map(\.text)
        #expect(labels.contains("Words 1000–5000"))
        #expect(labels.contains("Kudos ≥ 100"))
        #expect(labels.contains("Hits ≤ 500"))
        // A field with neither bound contributes nothing.
        #expect(!labels.contains { $0.hasPrefix("Comments") })
    }

    @Test func everyRemainingFacetIsNamedWhenSet() {
        var filters = AO3SearchFilters()
        filters.title = "Chunin Exams"
        filters.creators = "someauthor"
        filters.includeNotRated = false
        filters.warnings = [.violence]
        filters.categories = [.gen]
        filters.crossover = .exclude
        filters.completion = .complete
        filters.chapterCount = .singleChapter
        filters.updated = .week
        filters.language = AO3SearchFilters.Language.allCases.first { $0.id == "en" } ?? .any
        let labels = filters.summaryLabels().map(\.text)
        for expected in [
            "Title: Chunin Exams", "By: someauthor", "No Not Rated",
            "Graphic Depictions Of Violence", "Gen", "Crossover: Exclude",
            "Complete", "Single Chapter Only", "Past week", "English"
        ] {
            #expect(labels.contains(expected), "missing \(expected)")
        }
    }

    @Test func absoluteDateBoundsAreNamedInTheUsersOwnCalendar() throws {
        // Same formatter the search URL uses, so the chip can never disagree with
        // the day actually sent.
        var filters = AO3SearchFilters()
        filters.dateFrom = try #require(Calendar.current.date(
            from: DateComponents(year: 2024, month: 1, day: 31, hour: 0, minute: 30)
        ))
        #expect(filters.summaryLabels().map(\.text).contains("After 2024-01-31"))
    }

    @Test func chipOrderPutsTagsFirstAndSortLast() {
        var filters = AO3SearchFilters()
        filters.characters = "Sasuke Uchiha"
        filters.completion = .complete
        filters.sort = .hits
        let labels = filters.summaryLabels().map(\.text)
        #expect(labels.first == "Sasuke Uchiha")
        #expect(labels.last == "Sort: Hits")
    }

    @Test func everyActiveFilterSetProducesMoreThanJustTheSort() {
        // Guards the card's contract from the other side: if `hasActiveFilters` is
        // true, the chips must say *something* about why — a filter that narrows
        // results invisibly is the exact problem this card exists to fix.
        var filters = AO3SearchFilters()
        filters.bookmarksFrom = "10"
        #expect(filters.hasActiveFilters)
        #expect(filters.summaryLabels().map(\.text).count > 1)
    }
}
