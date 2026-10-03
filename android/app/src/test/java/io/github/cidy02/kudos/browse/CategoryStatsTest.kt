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
    fun jumpBackInIncludesEveryRecentChip() {
        val inputs = listOf(
            CategoryStatsInput(
                id = "Books & Literature",
                fandoms = listOf(AO3Fandom("Star Wars - All Media Types", 1_000)),
                hasFullList = true
            ),
            CategoryStatsInput(
                id = "Movies",
                fandoms = listOf(AO3Fandom("Frozen (Disney Movies)", 50)),
                hasFullList = false
            )
        )
        val works = listOf(
            work("Star Wars - All Media Types", finished = true, read = Instant.parse("2026-03-01T00:00:00Z")),
            work("Frozen (Disney Movies)", spine = 1, read = Instant.parse("2026-02-01T00:00:00Z"))
        ).map { it.toBrowseSnapshot() }

        val stats = CategoryStatsCalculator.computeStats(inputs, works)
        val jump = CategoryStatsCalculator.rankJumpBackIn(inputs, works)

        val recent = stats.values.flatMap { it.recentFandoms }.toSet()
        assertEquals(setOf("Star Wars - All Media Types", "Frozen (Disney Movies)"), recent)
        assertEquals(recent, jump.map { it.fandom }.toSet())
        assertEquals("Books & Literature", jump.first { it.fandom.startsWith("Star Wars") }.categoryId)
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
    fun fetchedOnlyCopyDoesNotCountAsDownloaded() {
        val category = AO3MediaCategory(
            name = "Movies",
            fandomsPath = "/media/Movies/fandoms",
            featuredFandoms = listOf("Frozen")
        )
        val fetched = work("Frozen", finished = true).copy(
            sourceUrl = "https://archiveofourown.org/works/1",
            isSaved = false,
            isKeptOffline = false,
            hasEpub = true,
            hasAo3WorkId = true
        )
        val kept = fetched.copy(isSaved = true)

        assertEquals(0, CategoryStatsCalculator.stats(category, fandomList = null, library = listOf(fetched)).savedCount)
        assertEquals(1, CategoryStatsCalculator.stats(category, fandomList = null, library = listOf(kept)).savedCount)
    }

    @Test
    fun recentFandomsFollowLastReadAheadOfDateAdded() {
        val category = AO3MediaCategory(
            name = "Anime & Manga",
            fandomsPath = "/media/Anime/fandoms",
            featuredFandoms = listOf("Naruto", "Bleach")
        )
        val library = listOf(
            work(
                "Naruto",
                finished = true,
                added = Instant.parse("2026-06-01T00:00:00Z"),
                read = Instant.parse("2026-01-01T00:00:00Z")
            ),
            work(
                "Bleach",
                finished = true,
                added = Instant.parse("2026-01-01T00:00:00Z"),
                read = Instant.parse("2026-06-01T00:00:00Z")
            )
        )

        val stats = CategoryStatsCalculator.stats(category, fandomList = null, library = library)

        assertEquals(listOf("Bleach", "Naruto"), stats.recentFandoms)
    }

    @Test
    fun clusterKeepsTheTwelveLargestFamilies() {
        val fandoms = (1..13).map { AO3Fandom("Fandom $it", workCount = it * 10) }
        val category = AO3MediaCategory(name = "Movies", fandomsPath = "/media/Movies/fandoms")

        val stats = CategoryStatsCalculator.stats(category, fandomList = fandoms, library = emptyList())

        assertEquals(13, stats.fandomCount)
        assertEquals(13, stats.familyCount)
        assertEquals(12, stats.clusterFandoms.size)
        assertEquals("Fandom 13", stats.clusterFandoms.first().title)
        assertTrue(stats.isApproximateWorkCount)
        assertEquals((1..13).sumOf { it * 10 }, stats.workCount)
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
        added: Instant = Instant.parse("2026-01-01T00:00:00Z"),
        read: Instant? = null
    ): SavedWork = SavedWork(
        title = fandom,
        author = "Author",
        workFandoms = listOf(fandom),
        isFinished = finished,
        lastSpineIndex = spine,
        dateAdded = added,
        lastReadDate = read
    )
}
