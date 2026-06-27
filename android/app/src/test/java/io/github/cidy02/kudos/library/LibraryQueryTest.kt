package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryRepositoryFavoritesFilterTest {
    @Test
    fun favoriteFilterKeepsFavoritesOnly() {
        val result = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(favoriteOnly = true)
        )

        assertEquals(listOf("alpha"), result.ids())
    }
}

class LibraryRepositoryFinishedFilterTest {
    @Test
    fun finishedAndUnfinishedAreUserStateFilters() {
        val finished = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(finished = LibraryFinishedFilter.Finished)
        )
        val unfinished = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(finished = LibraryFinishedFilter.Unfinished)
        )

        assertEquals(listOf("gamma"), finished.ids())
        assertEquals(listOf("alpha", "beta", "delta"), unfinished.ids())
    }

    @Test
    fun finishedAndCompleteAreNotConfused() {
        val completeButNotFinished = sampleItems().first { it.item.work.id == "alpha" }
        assertTrue(completeButNotFinished.item.work.isComplete)
        assertFalse(completeButNotFinished.item.work.isFinished)

        val finished = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(finished = LibraryFinishedFilter.Finished)
        )

        assertFalse("alpha" in finished.ids())
    }
}

class LibraryRepositoryDownloadedFilterTest {
    @Test
    fun downloadedFilterUsesHasEpub() {
        val downloaded = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(download = LibraryDownloadFilter.Downloaded)
        )
        val notDownloaded = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(download = LibraryDownloadFilter.NotDownloaded)
        )

        assertEquals(listOf("alpha", "gamma", "delta"), downloaded.ids())
        assertEquals(listOf("beta"), notDownloaded.ids())
    }
}

class LibraryRepositoryUserTagFilterTest {
    @Test
    fun userTagFilterRequiresSelectedTag() {
        val result = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(userTagIds = setOf("tag-comfort"))
        )

        assertEquals(listOf("alpha", "gamma"), result.ids())
    }
}

class LibraryRepositoryCollectionFilterTest {
    @Test
    fun collectionFilterRequiresMembership() {
        val result = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(collectionIds = setOf("collection-weekend"))
        )

        assertEquals(listOf("alpha", "beta"), result.ids())
    }
}

class LibraryRepositoryCombinedFiltersTest {
    @Test
    fun filtersCombineWithAndSemantics() {
        val result = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(
                favoriteOnly = true,
                download = LibraryDownloadFilter.Downloaded,
                userTagIds = setOf("tag-comfort"),
                collectionIds = setOf("collection-weekend")
            )
        )

        assertEquals(listOf("alpha"), result.ids())
    }
}

class LibraryRepositorySortByDateAddedTest {
    @Test
    fun recentlyAddedSortsDescendingWithStableTieBreakers() {
        val result = LibraryQuery.apply(sampleItems(), sort = LibrarySort.RecentlyAdded)

        assertEquals(listOf("alpha", "beta", "gamma", "delta"), result.ids())
    }
}

class LibraryRepositorySortByLastReadTest {
    @Test
    fun lastReadSortsNullDatesLast() {
        val result = LibraryQuery.apply(sampleItems(), sort = LibrarySort.LastRead)

        assertEquals(listOf("alpha", "gamma", "delta", "beta"), result.ids())
    }
}

class LibraryRepositorySortByTitleAuthorTest {
    @Test
    fun titleAndAuthorSortCaseInsensitively() {
        val byTitle = LibraryQuery.apply(sampleItems(), sort = LibrarySort.Title)
        val byAuthor = LibraryQuery.apply(sampleItems(), sort = LibrarySort.Author)

        assertEquals(listOf("alpha", "beta", "delta", "gamma"), byTitle.ids())
        assertEquals(listOf("alpha", "beta", "gamma", "delta"), byAuthor.ids())
    }
}

class LibraryRepositoryLocalSearchTest {
    @Test
    fun searchUsesLocalWorkTagsUserTagsAndCollections() {
        assertEquals(listOf("alpha", "beta"), LibraryQuery.apply(sampleItems(), searchQuery = "weekend").ids())
        assertEquals(listOf("alpha", "gamma"), LibraryQuery.apply(sampleItems(), searchQuery = "comfort").ids())
        assertEquals(listOf("delta"), LibraryQuery.apply(sampleItems(), searchQuery = "space opera").ids())
        assertEquals(listOf("beta"), LibraryQuery.apply(sampleItems(), searchQuery = "mystery summary").ids())
    }
}

class ContinueReadingQueryTest {
    @Test
    fun continueReadingIncludesInProgressDownloadedWorksOnly() {
        val result = LibraryQuery.continueReading(sampleItems())

        assertEquals(listOf("alpha", "delta"), result.ids())
        assertFalse("gamma" in result.ids()) // finished
        assertFalse("beta" in result.ids()) // no EPUB
    }
}

class ReadingHistoryQueryTest {
    @Test
    fun readingHistoryUsesLastReadDateDescending() {
        val result = LibraryQuery.readingHistory(sampleItems())

        assertEquals(listOf("alpha", "gamma", "delta"), result.ids())
    }
}

class RecentlyAddedQueryTest {
    @Test
    fun buildStateCarriesRecentlyAddedSection() {
        val state = LibraryQuery.buildState(
            snapshot = LibrarySnapshot(
                items = sampleItems().map { it.item },
                userTags = listOf(comfortTag, intenseTag),
                collections = listOf(weekendCollection),
                privacy = PrivacySettings(hideMatureContent = false)
            ),
            searchQuery = "",
            filters = LibraryFilterState(),
            sort = LibrarySort.RecentlyAdded
        )

        assertEquals(listOf("alpha", "beta", "gamma", "delta"), state.recentlyAdded.ids())
        assertEquals(4, state.totalSaved)
    }
}

class LibraryUiStateTest {
    @Test
    fun noResultsKeepsSavedWorkCountAndActiveFilterFlag() {
        val state = LibraryQuery.buildState(
            snapshot = LibrarySnapshot(
                items = sampleItems().map { it.item },
                userTags = emptyList(),
                collections = emptyList(),
                privacy = PrivacySettings(hideMatureContent = false)
            ),
            searchQuery = "no such work",
            filters = LibraryFilterState(favoriteOnly = true),
            sort = LibrarySort.RecentlyAdded
        )

        assertEquals(4, state.totalSaved)
        assertTrue(state.hasActiveQueryOrFilters)
        assertTrue(state.items.isEmpty())
    }
}

class LibraryDoesNotMutateWorksWhenFilteringTest {
    @Test
    fun filteringDoesNotMutateInputItems() {
        val items = sampleItems()
        val before = items.map { it.item.work }

        LibraryQuery.apply(items, filters = LibraryFilterState(favoriteOnly = true))

        assertEquals(before, items.map { it.item.work })
    }
}

class LibraryMissingEpubStateTest {
    @Test
    fun notDownloadedMeansHasEpubFalse() {
        val result = LibraryQuery.apply(
            sampleItems(),
            filters = LibraryFilterState(download = LibraryDownloadFilter.NotDownloaded)
        )

        assertEquals(listOf("beta"), result.ids())
        assertFalse(result.single().item.work.hasEpub)
    }
}

class LibraryPrivacyFilterTest {
    @Test
    fun hideModeRemovesAdultRatedWorks() {
        val state = LibraryQuery.buildState(
            snapshot = LibrarySnapshot(
                items = sampleItems().map { it.item },
                userTags = emptyList(),
                collections = emptyList(),
                privacy = PrivacySettings(
                    hideMatureContent = true,
                    matureContentMode = MatureContentMode.Hide
                )
            ),
            searchQuery = "",
            filters = LibraryFilterState(),
            sort = LibrarySort.RecentlyAdded
        )

        assertEquals(1, state.hiddenByPrivacyCount)
        assertFalse("gamma" in state.items.ids())
    }

    @Test
    fun obscureModeKeepsAdultRatedWorksButMarksThemObscured() {
        val state = LibraryQuery.buildState(
            snapshot = LibrarySnapshot(
                items = sampleItems().map { it.item },
                userTags = emptyList(),
                collections = emptyList(),
                privacy = PrivacySettings(
                    hideMatureContent = true,
                    matureContentMode = MatureContentMode.Obscure
                )
            ),
            searchQuery = "",
            filters = LibraryFilterState(),
            sort = LibrarySort.RecentlyAdded
        )

        val mature = state.items.first { it.item.work.id == "gamma" }
        assertEquals(LibraryPrivacyVisibility.Obscured, mature.privacyVisibility)
    }
}

private val baseTime: Instant = Instant.parse("2026-06-26T12:00:00Z")
private val comfortTag = Tag(id = "tag-comfort", name = " Comfort ")
private val intenseTag = Tag(id = "tag-intense", name = "Intense")
private val weekendCollection = WorkCollection(id = "collection-weekend", name = "Weekend")
private val classicsCollection = WorkCollection(id = "collection-classics", name = "Classics")

private fun sampleItems(): List<LibraryDisplayItem> {
    return listOf(
        display(
            work(
                id = "alpha",
                title = "Alpha Story",
                author = "A Writer",
                dateAddedOffset = 300,
                isFavorite = true,
                hasEpub = true,
                isComplete = true,
                rating = "Teen",
                wordCount = 40_000,
                kudos = 20,
                lastReadOffset = 60,
                lastScrollFraction = 0.4,
                fandoms = listOf("Fandom One"),
                freeforms = listOf("Found Family")
            ),
            userTags = listOf(comfortTag),
            collections = listOf(weekendCollection)
        ),
        display(
            work(
                id = "beta",
                title = "beta Case",
                author = "B Writer",
                summary = "Mystery summary",
                dateAddedOffset = 200,
                hasEpub = false,
                rating = "General",
                wordCount = 10_000,
                kudos = 4,
                fandoms = listOf("Fandom Two")
            ),
            collections = listOf(weekendCollection)
        ),
        display(
            work(
                id = "gamma",
                title = "Gamma Ending",
                author = "C Writer",
                dateAddedOffset = 100,
                isFinished = true,
                hasEpub = true,
                rating = "Mature",
                wordCount = 70_000,
                kudos = 50,
                lastReadOffset = 40,
                fandoms = listOf("Fandom Three")
            ),
            userTags = listOf(comfortTag),
            collections = listOf(classicsCollection)
        ),
        display(
            work(
                id = "delta",
                title = "Delta Voyage",
                author = "D Writer",
                dateAddedOffset = 0,
                hasEpub = true,
                rating = "Teen",
                wordCount = 25_000,
                kudos = 7,
                lastReadOffset = 10,
                lastSpineIndex = 2,
                fandoms = listOf("Space Opera")
            ),
            userTags = listOf(intenseTag)
        )
    )
}

private fun display(
    work: SavedWork,
    userTags: List<Tag> = emptyList(),
    collections: List<WorkCollection> = emptyList()
): LibraryDisplayItem {
    return LibraryDisplayItem(LibraryWorkListItem(work, userTags, collections))
}

private fun work(
    id: String,
    title: String,
    author: String,
    summary: String = "",
    dateAddedOffset: Long,
    isFavorite: Boolean = false,
    isFinished: Boolean = false,
    hasEpub: Boolean = true,
    isComplete: Boolean = false,
    rating: String = "",
    wordCount: Int = 0,
    kudos: Int = 0,
    lastReadOffset: Long? = null,
    lastSpineIndex: Int = 0,
    lastScrollFraction: Double = 0.0,
    fandoms: List<String> = emptyList(),
    freeforms: List<String> = emptyList()
): SavedWork {
    return SavedWork(
        id = id,
        title = title,
        author = author,
        summary = summary,
        dateAdded = baseTime.plusSeconds(dateAddedOffset),
        isFavorite = isFavorite,
        isSaved = true,
        isFinished = isFinished,
        hasEpub = hasEpub,
        isComplete = isComplete,
        rating = rating,
        wordCount = wordCount,
        chapters = "3/5",
        kudos = kudos,
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = lastReadOffset?.let { baseTime.plusSeconds(it) },
        workFandoms = fandoms,
        workFreeforms = freeforms,
        workTags = fandoms + freeforms
    )
}

private fun List<LibraryDisplayItem>.ids(): List<String> = map { it.item.work.id }
