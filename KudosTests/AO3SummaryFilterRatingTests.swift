import Foundation
import Testing
@testable import Kudos

/// The three refine facets artboard 1au draws that the matcher used to ignore:
/// the rating match mode ("Rating+"), Include Not Rated, and single-chapter.
///
/// Each was visible and inert — "Rating+" narrowed exactly as much as "Exact",
/// and the Not Rated toggle did nothing whatever it was set to. These pin the
/// behaviour so they cannot quietly go dead again.
struct AO3SummaryFilterRatingTests {
    private func work(_ rating: String, chapters: String = "1/1") -> AO3WorkSummary {
        AO3WorkSummary(
            id: 1, title: "W", authors: [], authorIdentities: [],
            fandoms: [], rating: rating,
            warnings: [], categories: [], isComplete: nil, dateUpdated: "",
            tags: [], summary: "", language: "", words: nil, chapters: chapters,
            comments: nil, kudos: nil, hits: nil,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }

    private func filters(
        rating: AO3SearchFilters.Rating,
        match: AO3SearchFilters.RatingMatch = .exact,
        includeNotRated: Bool = true,
        chapters: AO3SearchFilters.ChapterCount = .any
    ) -> AO3SearchFilters {
        var f = AO3SearchFilters()
        f.rating = rating
        f.ratingMatch = match
        f.includeNotRated = includeNotRated
        f.chapterCount = chapters
        return f
    }

    @Test func exactKeepsOnlyThatRung() {
        let f = filters(rating: .teen, match: .exact, includeNotRated: false)
        #expect(f.matchesSummary(work("Teen And Up Audiences")))
        #expect(!f.matchesSummary(work("Mature")))
        #expect(!f.matchesSummary(work("General Audiences")))
    }

    @Test func ratingPlusClimbsTheLadder() {
        // The whole point of "Rating+": Teen or anything stronger.
        let f = filters(rating: .teen, match: .orHigher, includeNotRated: false)
        #expect(f.matchesSummary(work("Teen And Up Audiences")))
        #expect(f.matchesSummary(work("Mature")))
        #expect(f.matchesSummary(work("Explicit")))
        #expect(!f.matchesSummary(work("General Audiences")))
    }

    @Test func ratingMinusDescendsIt() {
        let f = filters(rating: .teen, match: .orLower, includeNotRated: false)
        #expect(f.matchesSummary(work("General Audiences")))
        #expect(f.matchesSummary(work("Teen And Up Audiences")))
        #expect(!f.matchesSummary(work("Explicit")))
    }

    @Test func notRatedIsItsOwnChoiceNotTheBottomRung() {
        // Not Rated is the absence of a rating, so it answers to its own toggle
        // and never to the ladder — "Rating−" from Teen must not sweep it in.
        let kept = filters(rating: .teen, match: .orLower, includeNotRated: true)
        let dropped = filters(rating: .teen, match: .orLower, includeNotRated: false)
        #expect(kept.matchesSummary(work("Not Rated")))
        #expect(!dropped.matchesSummary(work("Not Rated")))
    }

    @Test func notRatedToggleIsInertUntilARatingIsChosen() {
        // With no rating selected there is nothing to include Not Rated *beside*,
        // so the toggle must not start hiding works on its own.
        var f = AO3SearchFilters()
        f.includeNotRated = false
        #expect(f.matchesSummary(work("Not Rated")))
        #expect(f.matchesSummary(work("Explicit")))
    }

    @Test func singleChapterMeansFinishedAtOne() {
        let f = filters(rating: .any, chapters: .singleChapter)
        #expect(f.matchesSummary(work("General Audiences", chapters: "1/1")))
        // One chapter posted of an unknown total is a WIP, not a one-shot.
        #expect(!f.matchesSummary(work("General Audiences", chapters: "1/?")))
        #expect(!f.matchesSummary(work("General Audiences", chapters: "3/3")))
    }

    @Test func unreadableChapterTextDoesNotHideAWork() {
        // Dropping a row because the parser could not read it would be the
        // silent-omission failure; an unknown count stays visible.
        let f = filters(rating: .any, chapters: .singleChapter)
        #expect(f.matchesSummary(work("General Audiences", chapters: "")))
    }

    @Test func anUnfilteredSetKeepsEverything() {
        let f = AO3SearchFilters()
        #expect(f.matchesSummary(work("Not Rated", chapters: "12/?")))
        #expect(f.matchesSummary(work("Explicit", chapters: "1/1")))
    }
}
