import Foundation
import Testing
@testable import Kudos

/// The AO3 series header's strings (board 24): every fact the old card showed
/// stays in the facts line, and the preserve button carries the series' count.
@MainActor
struct AO3SeriesHeaderTests {
    private func series(
        fandoms: [String] = [], words: Int? = nil, workCount: Int? = nil, bookmarks: Int? = nil,
        complete: Bool? = nil, restricted: Bool = false, date: String = ""
    ) -> AO3SeriesSummary {
        AO3SeriesSummary(
            id: 1, title: "The Coast Road", creatorNames: ["inkwell_moth"], creatorIdentities: [],
            fandoms: fandoms, summary: "", words: words, workCount: workCount, bookmarkCount: bookmarks,
            dateUpdated: date, isComplete: complete, isRestricted: restricted,
            url: URL(string: "https://archiveofourown.org/series/1")!
        )
    }

    @Test func factsKeepEveryFigureInOrder() {
        let text = AO3SeriesDetailView.facts(for: series(
            words: 141_000, workCount: 3, bookmarks: 1, complete: false, restricted: true, date: "2026-10-23"
        ))
        #expect(text == "3 works · 141,000 words · 1 bookmark · restricted · in progress · 2026-10-23")
    }

    @Test func factsSkipWhatAO3DidNotPrint() {
        #expect(AO3SeriesDetailView.facts(for: series(workCount: 1, complete: true)) == "1 work · complete")
    }

    @Test func eyebrowFallsBackToSeries() {
        #expect(AO3SeriesDetailView.eyebrow(for: series()) == "SERIES")
    }

    @Test func preserveTitleCarriesTheCount() {
        #expect(AO3SeriesDetailView.preserveTitle(count: 3) == "Preserve all 3")
        #expect(AO3SeriesDetailView.preserveTitle(count: nil) == "Preserve all")
    }
}
