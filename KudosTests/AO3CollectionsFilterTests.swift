import Foundation
import Testing
@testable import Kudos

/// Artboard 1bm's sort and filter. Client-side by necessity — AO3 sorts collections
/// by title and date only — so these rules are the whole feature.
struct AO3CollectionsFilterTests {
    private func collection(
        _ name: String,
        title: String? = nil,
        works: Int? = nil,
        bookmarks: Int? = nil,
        updated: String = "",
        closed: Bool = false,
        moderated: Bool = false,
        unrevealed: Bool = false
    ) -> AO3Collection {
        AO3Collection(
            name: name,
            title: title ?? name,
            isClosed: closed,
            isModerated: moderated,
            isUnrevealed: unrevealed,
            worksCount: works,
            bookmarksCount: bookmarks,
            updatedAtText: updated
        )
    }

    private func names(_ filter: AO3CollectionsFilter, _ input: [AO3Collection]) -> [String] {
        filter.apply(to: input).map(\.name)
    }

    // MARK: Sorting

    @Test func theDefaultLeavesAO3sOwnOrderAlone() {
        let input = [collection("c"), collection("a"), collection("b")]
        // Re-sorting by something the reader did not ask for is how a list stops
        // matching the website.
        #expect(names(AO3CollectionsFilter(), input) == ["c", "a", "b"])
    }

    @Test func titleSortsAsAStringRatherThanSilentlyDoingNothing() {
        var filter = AO3CollectionsFilter()
        filter.sort = .title
        filter.order = .ascending
        let input = [collection("c"), collection("a"), collection("b")]

        // An earlier draft folded Title into the numeric path by returning nil,
        // which turned it into a no-op that looked like a working control.
        #expect(names(filter, input) == ["a", "b", "c"])
        filter.order = .descending
        #expect(names(filter, input) == ["c", "b", "a"])
    }

    @Test func rowsWithNoCountKeepAO3sPositionInsteadOfCountingAsZero() {
        var filter = AO3CollectionsFilter()
        filter.sort = .works
        filter.order = .descending
        let input = [
            collection("unknown-first"),
            collection("ten", works: 10),
            collection("unknown-second"),
            collection("two", works: 2)
        ]

        // A collection whose works count failed to parse is not a collection with
        // zero works. Ranked rows come first; the unknowns hold their relative order.
        #expect(names(filter, input) == ["ten", "two", "unknown-first", "unknown-second"])
    }

    @Test func anUnparseableDateDoesNotGetSortedSomewhereWrong() {
        var filter = AO3CollectionsFilter()
        filter.sort = .recentlyUpdated
        filter.order = .descending
        let input = [
            collection("garbled", updated: "last Tuesday-ish"),
            collection("older", updated: "01 Jan 2020"),
            collection("newer", updated: "01 Jan 2026")
        ]
        #expect(names(filter, input) == ["newer", "older", "garbled"])
    }

    @Test func theDateParserAcceptsAO3sShapesAndRejectsOthers() {
        #expect(AO3CollectionsFilter.updatedDate(from: "26 Aug 2026") != nil)
        #expect(AO3CollectionsFilter.updatedDate(from: "2026-08-26") != nil)
        #expect(AO3CollectionsFilter.updatedDate(from: "") == nil)
        #expect(AO3CollectionsFilter.updatedDate(from: "sometime") == nil)
    }

    // MARK: Filtering

    @Test func showOnlyFiltersNarrowTogetherRatherThanReplacingEachOther() {
        var filter = AO3CollectionsFilter()
        filter.showsOpenOnly = true
        filter.showsModeratedOnly = true
        let input = [
            collection("open-moderated", moderated: true),
            collection("open-unmoderated"),
            collection("closed-moderated", closed: true, moderated: true)
        ]
        // The four flags are independent on AO3, so two set means both must hold.
        #expect(names(filter, input) == ["open-moderated"])
    }

    @Test func hasWorksExcludesBothZeroAndUnknown() {
        var filter = AO3CollectionsFilter()
        filter.showsWithWorksOnly = true
        let input = [collection("some", works: 3), collection("none", works: 0), collection("unknown")]
        #expect(names(filter, input) == ["some"])
    }

    // MARK: Chips

    @Test func onlyNonDefaultSettingsProduceAChip() {
        #expect(AO3CollectionsFilter().summaryLabels.isEmpty)
        #expect(AO3CollectionsFilter().hasActiveFilters == false)

        var filter = AO3CollectionsFilter()
        filter.sort = .title
        filter.order = .ascending
        // The direction label follows the sort — Title must not offer "Newest".
        #expect(filter.summaryLabels == ["Title · A–Z"])
        #expect(filter.hasActiveFilters)
    }
}
