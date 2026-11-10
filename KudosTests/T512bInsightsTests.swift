import Foundation
import SwiftSoup
import Testing
@testable import Kudos

/// T-512b: the Insights facet parser, the "New since your last visit" split, and
/// the chip → include-filter mapping.
@MainActor
struct T512bInsightsTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Facet parser

    @Test func parsesIncludeFacetsInPageOrder() throws {
        let page = try AO3Client.parseSearchPage(fixture("ao3_tag_works_facets"), page: 1)
        let facets = page.facets
        #expect(facets.relationships.map(\.name) == [
            "Leia Organa/Han Solo", "Doctor Who (2005)", "Obi-Wan Kenobi/Anakin Skywalker"
        ])
        #expect(facets.relationships.map(\.count) == [14210, 1234, 86])
        #expect(facets.relationships.map(\.id) == [3001, 3002, 3003])
        #expect(facets.characters.map(\.name) == ["Leia Organa", "Han Solo"])
        #expect(facets.characters.first?.count == 14200)
        #expect(facets.freeforms.map(\.name) == ["Slow Burn", "Found Family"])
        #expect(facets.freeforms.first?.count == 48210)
        // The works list still parses alongside the sidebar.
        #expect(page.works.count == 3)
    }

    @Test func pageWithoutSidebarHasNoFacets() throws {
        let page = try AO3Client.parseSearchPage(fixture("ao3_tag_works"), page: 1)
        #expect(page.facets.isEmpty)
    }

    @Test func labelKeepsBracketedNameAndTakesOnlyTheFinalCount() {
        let bracketed = AO3Client.parseFacetLabel("Doctor Who (2005) (1234)")
        #expect(bracketed?.name == "Doctor Who (2005)")
        #expect(bracketed?.count == 1234)
        let big = AO3Client.parseFacetLabel("  Slow Burn (48210) ")
        #expect(big?.name == "Slow Burn")
        #expect(big?.count == 48210)
        #expect(AO3Client.parseFacetLabel("Doctor Who (2005)")?.name == "Doctor Who")
        #expect(AO3Client.parseFacetLabel("No count here") == nil)
        #expect(AO3Client.parseFacetLabel(" (12)") == nil)
    }

    @Test func chipCountsAreShortened() {
        #expect(InsightsCountFormat.short(86) == "86")
        #expect(InsightsCountFormat.short(1234) == "1.2k")
        #expect(InsightsCountFormat.short(14210) == "14.2k")
        #expect(InsightsCountFormat.short(48000) == "48k")
        #expect(InsightsCountFormat.short(1_250_000) == "1.2M")
    }

    // MARK: Chip → include filter

    @Test func chipSetsTheMatchingIncludeFilter() {
        let entry = AO3FacetEntry(name: "Leia Organa/Han Solo", count: 14210, id: 3001)
        let base = AO3SearchFilters()
        #expect(base.including(entry, as: .relationships).relationships == "Leia Organa/Han Solo")
        #expect(base.including(entry, as: .characters).characters == "Leia Organa/Han Solo")
        #expect(base.including(entry, as: .freeforms).additionalTags == "Leia Organa/Han Solo")
        // Only the one field changes.
        var expected = base
        expected.relationships = entry.name
        #expect(base.including(entry, as: .relationships) == expected)
    }

    @Test func chipAppendsWithoutDuplicating() {
        let slow = AO3FacetEntry(name: "Slow Burn", count: 5, id: 1)
        var filters = AO3SearchFilters()
        filters.additionalTags = "Fluff"
        filters = filters.including(slow, as: .freeforms)
        #expect(filters.additionalTags == "Fluff, Slow Burn")
        #expect(filters.including(AO3FacetEntry(name: "slow burn", count: 5, id: 1), as: .freeforms) == filters)
    }

    // MARK: Divider split

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func visit(_ month: Int, _ day: Int, hour: Int = 15) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func split(_ dates: [String], visit: Date?, page: Int = 1, newestFirst: Bool = true) -> Int? {
        NewSinceLastVisit.dividerIndex(
            updatedDates: dates, previousVisit: visit, page: page,
            newestFirstByUpdated: newestFirst, calendar: calendar
        )
    }

    @Test func dividerFollowsTheLastWorkNewerThanTheVisitDay() throws {
        let dates = ["09 Jul 2026", "08 Jul 2026", "07 Jul 2026", "05 Jul 2026"]
        #expect(split(dates, visit: try visit(7, 7)) == 1)
    }

    @Test func sameDayIsNotNew() throws {
        // Updated on the visit's own day, even hours after the visit, is not newer.
        #expect(split(["07 Jul 2026", "07 Jul 2026"], visit: try visit(7, 7, hour: 1)) == nil)
        #expect(split(["08 Jul 2026", "07 Jul 2026"], visit: try visit(7, 7, hour: 23)) == 0)
    }

    @Test func noDividerWhenEveryWorkOrNoWorkIsNewer() throws {
        #expect(split(["09 Jul 2026", "08 Jul 2026"], visit: try visit(7, 7)) == nil)
        #expect(split(["06 Jul 2026", "05 Jul 2026"], visit: try visit(7, 7)) == nil)
        #expect(split([], visit: try visit(7, 7)) == nil)
    }

    @Test func unparseableDatesCountAsNotNewer() throws {
        #expect(split(["", "soon", "not a date"], visit: try visit(7, 7)) == nil)
        #expect(split(["09 Jul 2026", "garbage", "05 Jul 2026"], visit: try visit(7, 7)) == 0)
    }

    @Test func dividerOnlyOnFirstPageNewestFirstWithAPreviousVisit() throws {
        let dates = ["09 Jul 2026", "05 Jul 2026"]
        #expect(split(dates, visit: try visit(7, 7)) == 0)
        #expect(split(dates, visit: try visit(7, 7), page: 2) == nil)
        #expect(split(dates, visit: try visit(7, 7), newestFirst: false) == nil)
        #expect(split(dates, visit: nil) == nil)
    }

    @Test func labelDropsTheYearOnlyWhenItIsThisYear() throws {
        let now = try visit(11, 10)
        let us = Locale(identifier: "en_US")
        #expect(NewSinceLastVisit.label(previousVisit: try visit(7, 7), now: now, calendar: calendar, locale: us)
            == "↑ New since your last visit · Jul 7")
        let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 30)))
        #expect(NewSinceLastVisit.label(previousVisit: lastYear, now: now, calendar: calendar, locale: us)
            == "↑ New since your last visit · Dec 30, 2025")
        #expect(NewSinceLastVisit.accessibilityLabel(
            previousVisit: try visit(7, 7), now: now, calendar: calendar, locale: us
        ) == "New since your last visit on Jul 7 above, older works below")
    }
}
