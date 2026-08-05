package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Pins the per-section ordering rules ported from iOS `HomeSectionKind`. */
class HomeSectionKindTest {

    private val base = Instant.parse("2026-01-01T00:00:00Z")
    private fun work(
        title: String,
        favorite: Boolean = false,
        read: Instant? = null,
        added: Instant = base
    ) = SavedWork(
        title = title,
        author = "a",
        sourceUrl = "https://archiveofourown.org/works/1",
        isFavorite = favorite,
        lastReadDate = read,
        dateAdded = added,
        isSaved = true
    )

    @Test
    fun `favorites order by last read, falling back to date added`() {
        val older = work("older", favorite = true, added = base)
        val newer = work("newer", favorite = true, added = base.plusSeconds(60))
        val readRecently = work("read", favorite = true, added = base, read = base.plusSeconds(600))

        val ordered = HomeSectionKind.Favorites.works(listOf(older, newer, readRecently)) { true }
        assertEquals(listOf("read", "newer", "older"), ordered.map { it.title })
    }

    @Test
    fun `recently opened excludes works never opened`() {
        val opened = work("opened", read = base.plusSeconds(10))
        val never = work("never")
        val ordered = HomeSectionKind.RecentlyOpened.works(listOf(opened, never)) { true }
        assertEquals(listOf("opened"), ordered.map { it.title })
    }

    @Test
    fun `the privacy predicate removes hidden works from every section`() {
        val hidden = work("hidden", favorite = true)
        val shown = work("shown", favorite = true)
        val ordered = HomeSectionKind.Favorites.works(listOf(hidden, shown)) { it.title != "hidden" }
        assertEquals(listOf("shown"), ordered.map { it.title })
    }

    @Test
    fun `every section has distinct id and copy`() {
        val ids = HomeSectionKind.entries.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(HomeSectionKind.entries.all { it.emptyMessage.isNotBlank() })
        assertEquals(HomeSectionKind.Favorites, HomeSectionKind.fromId("favorites"))
    }
}
