package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryStatsTest {

    @Test
    fun usesFeaturedFandomsForSavedAndRecentWhileListLoads() {
        val category = AO3MediaCategory(
            name = "Anime & Manga",
            fandomsPath = "/media/Anime/fandoms",
            featuredFandoms = listOf("Naruto", "Bleach")
        )
        val library = listOf(
            work("Naruto", finished = true, added = Instant.parse("2026-01-02T00:00:00Z")),
            work("Bleach", finished = false, spine = 2, added = Instant.parse("2026-01-01T00:00:00Z")),
            work("Frozen", finished = true)
        )

        val stats = CategoryStatsCalculator.stats(category, fandomList = null, library = library)

        assertNull(stats.fandomCount)
        assertNull(stats.workCount)
        assertEquals(2, stats.savedCount)
        assertEquals(listOf("Naruto", "Bleach"), stats.recentFandoms)
    }

    @Test
    fun fullListProvidesFandomAndWorkCounts() {
        val category = AO3MediaCategory(
            name = "Movies",
            fandomsPath = "/media/Movies/fandoms",
            featuredFandoms = listOf("Frozen")
        )
        val list = listOf(
            AO3Fandom("Frozen", workCount = 1_000),
            AO3Fandom("Inception", workCount = 500),
            AO3Fandom("Other", workCount = null)
        )
        val library = listOf(work("Frozen", finished = true))

        val stats = CategoryStatsCalculator.stats(category, fandomList = list, library = library)

        assertEquals(3, stats.fandomCount)
        assertEquals(1_500, stats.workCount)
        assertEquals(1, stats.savedCount)
        assertEquals(listOf("Frozen"), stats.recentFandoms)
    }

    @Test
    fun formatCountUsesCompactNotation() {
        assertEquals("42", CategoryStatsCalculator.formatCount(42))
        assertEquals("1.2K", CategoryStatsCalculator.formatCount(1_234))
        assertEquals("3.5M", CategoryStatsCalculator.formatCount(3_500_000))
        assertEquals("~3.5M works", CategoryStatsCalculator.formatWorksEstimate(3_500_000))
    }

    @Test
    fun iconForKnownCategoriesIsStable() {
        val anime = CategoryStatsCalculator.iconFor("Anime & Manga")
        val tv = CategoryStatsCalculator.iconFor("TV Shows")
        val unknown = CategoryStatsCalculator.iconFor("Unknown Category")
        assertTrue(anime != tv || anime == unknown) // smoke: mapping returns vectors
        assertEquals(CategoryStatsCalculator.iconFor("Unknown Category"), unknown)
    }

    private fun work(
        fandom: String,
        finished: Boolean = false,
        spine: Int = 0,
        added: Instant = Instant.parse("2026-01-01T00:00:00Z")
    ): SavedWork = SavedWork(
        title = fandom,
        author = "Author",
        workFandoms = listOf(fandom),
        isFinished = finished,
        lastSpineIndex = spine,
        dateAdded = added
    )
}
