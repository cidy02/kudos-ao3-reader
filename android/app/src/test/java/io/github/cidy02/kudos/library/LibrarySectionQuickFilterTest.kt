package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LibrarySectionQuickFilterTest {
    @Test
    fun readingNowOffersCountedAllAndWipChips() {
        val allItems = listOf(
            item("complete", complete = true),
            item("wip-1", complete = false),
            item("wip-2", complete = false)
        )

        assertEquals(
            listOf(LibrarySectionQuickFilter.All, LibrarySectionQuickFilter.Wip),
            LibrarySectionKind.ReadingNow.quickFilters()
        )
        assertEquals(
            listOf("All 3", "WIP 2"),
            LibrarySectionKind.ReadingNow.quickFilters().map {
                librarySectionQuickFilterLabel(LibrarySectionKind.ReadingNow, it, allItems)
            }
        )
        assertEquals(
            listOf("wip-2"),
            filterLibrarySectionItems(
                LibrarySectionKind.ReadingNow,
                LibrarySectionQuickFilter.Wip,
                items = listOf(allItems.last())
            ).ids()
        )
    }

    @Test
    fun savedForLaterOffersNoQuickChips() {
        assertTrue(LibrarySectionKind.SavedForLater.quickFilters().isEmpty())
    }

    @Test
    fun finishedOffersNoQuickChips() {
        assertTrue(LibrarySectionKind.Finished.quickFilters().isEmpty())
    }

    @Test
    fun collectionsOffersNoQuickChips() {
        assertTrue(LibrarySectionKind.Collections.quickFilters().isEmpty())
    }

    @Test
    fun downloadedOffersNoQuickChips() {
        assertTrue(LibrarySectionKind.Downloaded.quickFilters().isEmpty())
    }

    @Test
    fun historyOffersNoQuickChips() {
        assertTrue(LibrarySectionKind.History.quickFilters().isEmpty())
    }

    @Test
    fun favoritesOffersIosFilters() {
        val rereadOfflineWip = item("reread", complete = false, downloaded = true)
        val onceReadWip = item("once", complete = false)
        val complete = item("complete", complete = true)
        val items = listOf(rereadOfflineWip, onceReadWip, complete)

        assertEquals(
            listOf("All", "Rereads", "Offline", "WIP"),
            LibrarySectionKind.Favorites.quickFilters().map { it.title }
        )
        assertEquals(
            listOf("reread"),
            filterLibrarySectionItems(
                LibrarySectionKind.Favorites,
                LibrarySectionQuickFilter.Rereads,
                items,
                finishCounts = mapOf("reread" to 2, "once" to 1)
            ).ids()
        )
        assertEquals(
            listOf("reread"),
            filterLibrarySectionItems(
                LibrarySectionKind.Favorites,
                LibrarySectionQuickFilter.Offline,
                items
            ).ids()
        )
        assertEquals(
            listOf("reread", "once"),
            filterLibrarySectionItems(
                LibrarySectionKind.Favorites,
                LibrarySectionQuickFilter.Wip,
                items
            ).ids()
        )
    }

    private fun item(
        id: String,
        complete: Boolean,
        downloaded: Boolean = false
    ): LibraryDisplayItem = LibraryDisplayItem(
        LibraryWorkListItem(
            SavedWork(
                id = id,
                title = id,
                author = "Author",
                hasEpub = downloaded,
                isSaved = downloaded,
                isComplete = complete
            )
        )
    )

    private fun List<LibraryDisplayItem>.ids(): List<String> = map { it.item.work.id }
}
