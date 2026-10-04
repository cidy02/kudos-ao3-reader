package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionsIndexPage
import org.junit.Assert.*
import org.junit.Test

/** Same cases, input rows and expected values as AO3CollectionsFilterTests.swift. */
class AO3CollectionsFilterTest {
    private fun collection(
        name: String,
        title: String = name,
        works: Int? = null,
        bookmarks: Int? = null,
        updated: String = "",
        closed: Boolean = false,
        moderated: Boolean = false,
        unrevealed: Boolean = false
    ) = AO3Collection(
        name = name, title = title, worksCount = works, bookmarksCount = bookmarks,
        updatedAtText = updated, isClosed = closed, isModerated = moderated, isUnrevealed = unrevealed
    )

    private fun names(filter: AO3CollectionsFilter, input: List<AO3Collection>) =
        filter.apply(input).map { it.name }

    @Test fun theDefaultLeavesAO3sOwnOrderAlone() {
        val input = listOf(collection("c"), collection("a"), collection("b"))
        assertEquals(listOf("c", "a", "b"), names(AO3CollectionsFilter(), input))
    }

    @Test fun titleSortsAsAStringRatherThanSilentlyDoingNothing() {
        var filter = AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.Title, order = AO3CollectionsFilter.Order.Ascending)
        val input = listOf(collection("c"), collection("a"), collection("b"))
        assertEquals(listOf("a", "b", "c"), names(filter, input))
        filter = filter.copy(order = AO3CollectionsFilter.Order.Descending)
        assertEquals(listOf("c", "b", "a"), names(filter, input))
    }

    @Test fun rowsWithNoCountKeepAO3sPositionInsteadOfCountingAsZero() {
        val filter = AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.Works, order = AO3CollectionsFilter.Order.Descending)
        val input = listOf(
            collection("unknown-first"), collection("ten", works = 10),
            collection("unknown-second"), collection("two", works = 2)
        )
        assertEquals(listOf("ten", "two", "unknown-first", "unknown-second"), names(filter, input))
    }

    @Test fun anUnparseableDateDoesNotGetSortedSomewhereWrong() {
        val filter = AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.RecentlyUpdated, order = AO3CollectionsFilter.Order.Descending)
        val input = listOf(
            collection("garbled", updated = "last Tuesday-ish"),
            collection("older", updated = "01 Jan 2020"), collection("newer", updated = "01 Jan 2026")
        )
        assertEquals(listOf("newer", "older", "garbled"), names(filter, input))
    }

    @Test fun theDateParserAcceptsAO3sShapesAndRejectsOthers() {
        assertNotNull(AO3CollectionsFilter.updatedDate("26 Aug 2026"))
        assertNotNull(AO3CollectionsFilter.updatedDate("2026-08-26"))
        assertNull(AO3CollectionsFilter.updatedDate(""))
        assertNull(AO3CollectionsFilter.updatedDate("sometime"))
    }

    @Test fun showOnlyFiltersNarrowTogetherRatherThanReplacingEachOther() {
        val filter = AO3CollectionsFilter(showsOpenOnly = true, showsModeratedOnly = true)
        val input = listOf(
            collection("open-moderated", moderated = true), collection("open-unmoderated"),
            collection("closed-moderated", closed = true, moderated = true)
        )
        assertEquals(listOf("open-moderated"), names(filter, input))
    }

    @Test fun hasWorksExcludesBothZeroAndUnknown() {
        val filter = AO3CollectionsFilter(showsWithWorksOnly = true)
        val input = listOf(collection("some", works = 3), collection("none", works = 0), collection("unknown"))
        assertEquals(listOf("some"), names(filter, input))
    }

    @Test fun everyClientSideSortAndFilterNeedsTheWholeIndex() {
        assertFalse(AO3CollectionsFilter().needsWholeIndex)
        assertFalse(AO3CollectionsFilter(order = AO3CollectionsFilter.Order.Ascending).needsWholeIndex)
        for (sort in AO3CollectionsFilter.Sort.entries.filter { it != AO3CollectionsFilter.Sort.AsReturned }) {
            assertTrue(AO3CollectionsFilter(sort = sort).needsWholeIndex)
        }
        listOf(
            AO3CollectionsFilter(showsOpenOnly = true), AO3CollectionsFilter(showsUnrevealedOnly = true),
            AO3CollectionsFilter(showsModeratedOnly = true), AO3CollectionsFilter(showsWithWorksOnly = true)
        ).forEach { assertTrue(it.needsWholeIndex) }
    }

    @Test fun onlyNonDefaultSettingsProduceAChip() {
        assertTrue(AO3CollectionsFilter().summaryLabels.isEmpty())
        assertFalse(AO3CollectionsFilter().hasActiveFilters)
        val filter = AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.Title, order = AO3CollectionsFilter.Order.Ascending)
        assertEquals(listOf("Title · A–Z"), filter.summaryLabels)
        assertTrue(filter.hasActiveFilters)
    }

    @Test fun filterDraftCancelApplyAndResetResolveIndependently() {
        val initial = AO3CollectionsFilter(showsOpenOnly = true)
        val editor = AO3CollectionsFilterDraft(initial)
        editor.draft = editor.draft.copy(sort = AO3CollectionsFilter.Sort.Title, showsModeratedOnly = true)
        assertEquals(initial, editor.resolved(AO3CollectionsFilterDraft.Resolution.Cancel))
        assertEquals(editor.draft, editor.resolved(AO3CollectionsFilterDraft.Resolution.Apply))
        editor.reset()
        assertEquals(AO3CollectionsFilter(), editor.draft)
        assertEquals(initial, editor.resolved(AO3CollectionsFilterDraft.Resolution.Cancel))
        assertEquals(AO3CollectionsFilter(), editor.resolved(AO3CollectionsFilterDraft.Resolution.Apply))
    }

    @Test fun collectionStatusLabelsAlwaysNameVisibilityAndOptionallyAnonymity() {
        assertEquals(listOf("Revealed"), AO3CollectionCardCopy.statusLabels(false, false))
        assertEquals(listOf("Unrevealed"), AO3CollectionCardCopy.statusLabels(true, false))
        assertEquals(listOf("Revealed", "Anonymous"), AO3CollectionCardCopy.statusLabels(false, true))
        assertEquals(listOf("Unrevealed", "Anonymous"), AO3CollectionCardCopy.statusLabels(true, true))
    }

    // Whole-index cases from AO3CollectionSessionReloadTests.swift.
    @Test fun theWholeIndexPreservesServerOrderAndRejectsStalePages() {
        val collections = mutableListOf(collection("page-one-a", "Page one A"), collection("page-one-b", "Page one B"))
        val pageTwo = AO3CollectionsIndexPage(
            listOf(collection("page-two-a", "Page two A"), collection("page-two-b", "Page two B")), 2, 3
        )
        assertTrue(AO3CollectionsWholeIndex.append(pageTwo, collections, 7, 7, 4, 4))
        val expected = listOf("page-one-a", "page-one-b", "page-two-a", "page-two-b")
        assertEquals(expected, collections.map { it.name })
        val stalePage = AO3CollectionsIndexPage(listOf(collection("stale", "Stale")), 3, 3)
        assertFalse(AO3CollectionsWholeIndex.append(stalePage, collections, 7, 8, 4, 4))
        assertFalse(AO3CollectionsWholeIndex.append(stalePage, collections, 8, 8, 4, 5))
        assertEquals(expected, collections.map { it.name })
    }

    @Test fun theWholeIndexStopsAtItsCapAndOnAnEmptyPage() {
        assertNull(AO3CollectionsWholeIndex.nextPage(AO3CollectionsWholeIndex.maximumPages, AO3CollectionsWholeIndex.maximumPages + 100, false))
        assertNull(AO3CollectionsWholeIndex.nextPage(2, 10, true))
        assertEquals(3, AO3CollectionsWholeIndex.nextPage(2, 10, false))
    }

    @Test fun aCappedCrawlSaysItIsPartial() {
        val cap = AO3CollectionsWholeIndex.maximumPages
        assertEquals("first $cap of ${cap + 6} pages", AO3CollectionsWholeIndex.partialNote(cap + 6, false))
        assertNull(AO3CollectionsWholeIndex.partialNote(cap, false))
        assertNull(AO3CollectionsWholeIndex.partialNote(cap + 6, true))
    }

    @Test fun filteredRefreshRestartsAtPageOneAndTheCrawlReusesIt() {
        assertEquals(1, AO3CollectionsWholeIndex.refreshPage(4, true))
        assertEquals(4, AO3CollectionsWholeIndex.refreshPage(4, false))
        assertTrue(AO3CollectionsWholeIndex.canReusePageOne(1, true, true))
        assertFalse(AO3CollectionsWholeIndex.canReusePageOne(2, true, true))
    }

    @Test fun unknownBookmarkCountsAndTiesKeepIncomingOrderInBothDirections() {
        val input = listOf(collection("unknown-a"), collection("two-a", bookmarks = 2),
            collection("zero", bookmarks = 0), collection("unknown-b"), collection("two-b", bookmarks = 2))
        val filter = AO3CollectionsFilter(sort = AO3CollectionsFilter.Sort.Bookmarks)
        assertEquals(listOf("two-a", "two-b", "zero", "unknown-a", "unknown-b"), names(filter, input))
        assertEquals(listOf("zero", "two-a", "two-b", "unknown-a", "unknown-b"),
            names(filter.copy(order = AO3CollectionsFilter.Order.Ascending), input))
    }

    @Test fun chipsKeepIOSOrderAndDirectionLabelsFollowTheSort() {
        val filter = AO3CollectionsFilter(showsOpenOnly = true, showsWithWorksOnly = true,
            showsModeratedOnly = true, showsUnrevealedOnly = true)
        assertEquals(listOf("Open to new works", "Moderated", "Unrevealed", "Has works"), filter.summaryLabels)
        assertEquals("Newest", AO3CollectionsFilter.Order.Descending.title(AO3CollectionsFilter.Sort.RecentlyUpdated))
        assertEquals("Fewest", AO3CollectionsFilter.Order.Ascending.title(AO3CollectionsFilter.Sort.Works))
        assertEquals("Z–A", AO3CollectionsFilter.Order.Descending.title(AO3CollectionsFilter.Sort.Title))
    }
}
