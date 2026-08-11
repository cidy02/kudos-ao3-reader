package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private fun summary(id: Long, complete: Boolean = false) = AO3WorkSummary(
    id = id,
    title = "Work $id",
    authors = listOf("Alice"),
    fandoms = listOf("Naruto"),
    rating = "Teen",
    warnings = emptyList(),
    categories = emptyList(),
    isComplete = complete
)

private fun saved(
    id: Long,
    isSaved: Boolean = true,
    hasEpub: Boolean = false,
    favorite: Boolean = false,
    finished: Boolean = false
) = SavedWork(
    id = "uuid-$id",
    title = "Work $id",
    author = "Alice",
    sourceUrl = "https://archiveofourown.org/works/$id",
    isSaved = isSaved,
    hasEpub = hasEpub,
    isFavorite = favorite,
    isFinished = finished
)

class BrowseLocalIndicatorsTest {
    @Test
    fun mapsLocalFlagsForMatchingWork() {
        val index = BrowseLocalIndicators.index(
            listOf(saved(123, hasEpub = true, favorite = true, finished = true))
        )
        val indicator = BrowseLocalIndicators.forWork(summary(123), index)

        assertTrue(indicator.isSaved)
        assertTrue(indicator.hasEpub)
        assertTrue(indicator.isFavorite)
        assertTrue(indicator.isFinished)
        assertTrue(indicator.any)
    }

    @Test
    fun unmatchedWorkHasNoIndicators() {
        val index = BrowseLocalIndicators.index(listOf(saved(123)))
        val indicator = BrowseLocalIndicators.forWork(summary(999), index)
        assertEquals(BrowseLocalIndicator.NONE, indicator)
        assertFalse(indicator.any)
    }

    @Test
    fun completeWorkIsNotTreatedAsFinished() {
        // A browsed work that is AO3-complete but NOT in the local library must not
        // report isFinished (local reading state != AO3 completion status).
        val index = BrowseLocalIndicators.index(emptyList())
        val indicator = BrowseLocalIndicators.forWork(summary(123, complete = true), index)
        assertFalse(indicator.isFinished)
        assertFalse(indicator.any)
    }

    @Test
    fun blankSourceUrlsAreNotIndexed() {
        val index = BrowseLocalIndicators.index(listOf(saved(123).copy(sourceUrl = "")))
        assertTrue(index.isEmpty())
    }
}
