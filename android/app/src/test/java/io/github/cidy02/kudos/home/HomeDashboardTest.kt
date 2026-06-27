package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibrarySnapshot
import io.github.cidy02.kudos.library.LibraryWorkListItem
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class HomeDashboardTest {
    @Test
    fun dashboardUsesLibrarySectionsWithoutNetworkState() {
        val reading = work(
            id = "reading",
            title = "Reading Now",
            dateAddedOffset = 0,
            hasEpub = true,
            lastReadOffset = 60,
            lastScrollFraction = 0.35
        )
        val favorite = work(
            id = "favorite",
            title = "Favorite Work",
            dateAddedOffset = 100,
            isFavorite = true
        )
        val finished = work(
            id = "finished",
            title = "Finished Work",
            dateAddedOffset = 200,
            hasEpub = true,
            isFinished = true,
            lastReadOffset = 180
        )

        val state = HomeDashboard.buildState(snapshot(reading, favorite, finished))

        assertFalse(state.loading)
        assertEquals(3, state.totalSaved)
        assertEquals(listOf("reading"), state.continueReading.ids())
        assertEquals(listOf("favorite"), state.favorites.ids())
        assertEquals(listOf("reading", "finished"), state.recentlyOpened.ids())
        assertEquals(listOf("reading", "favorite", "finished"), state.recentlyAdded.ids())
    }

    @Test
    fun dashboardCarriesPrivacyHiddenCountAndOmitsHiddenWorks() {
        val state = HomeDashboard.buildState(
            snapshot(
                work(id = "visible", title = "Visible Work", rating = "Teen"),
                work(id = "hidden", title = "Hidden Work", rating = "Explicit"),
                privacy = PrivacySettings(
                    hideMatureContent = true,
                    matureContentMode = MatureContentMode.Hide
                )
            )
        )

        assertEquals(2, state.totalSaved)
        assertEquals(1, state.hiddenByPrivacyCount)
        assertEquals(listOf("visible"), state.recentlyAdded.ids())
    }
}

private val baseTime: Instant = Instant.parse("2026-06-27T12:00:00Z")

private fun snapshot(
    vararg works: SavedWork,
    privacy: PrivacySettings = PrivacySettings(hideMatureContent = false)
): LibrarySnapshot {
    return LibrarySnapshot(
        items = works.map { LibraryWorkListItem(work = it) },
        userTags = emptyList(),
        collections = emptyList(),
        privacy = privacy
    )
}

private fun work(
    id: String,
    title: String,
    dateAddedOffset: Long = 0,
    hasEpub: Boolean = false,
    isFavorite: Boolean = false,
    isFinished: Boolean = false,
    lastReadOffset: Long? = null,
    lastScrollFraction: Double = 0.0,
    rating: String = "Teen"
): SavedWork {
    return SavedWork(
        id = id,
        title = title,
        author = "Author $id",
        dateAdded = baseTime.minusSeconds(dateAddedOffset),
        isSaved = true,
        hasEpub = hasEpub,
        isFavorite = isFavorite,
        isFinished = isFinished,
        rating = rating,
        wordCount = 12_000,
        chapters = "1/1",
        lastReadDate = lastReadOffset?.let { baseTime.minusSeconds(it) },
        lastScrollFraction = lastScrollFraction
    )
}

private fun List<io.github.cidy02.kudos.library.LibraryDisplayItem>.ids(): List<String> {
    return map { it.item.work.id }
}
