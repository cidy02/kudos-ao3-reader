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
    fun `the privacy predicate removes hidden works from every section`() {
        val hidden = work("hidden", read = base)
        val shown = work("shown", read = base)
        val ordered = HomeSectionKind.ReadingNow.works(listOf(hidden, shown)) { it.title != "hidden" }
        assertEquals(listOf("shown"), ordered.map { it.title })
    }

    @Test
    fun `every section has distinct id and copy`() {
        val ids = HomeSectionKind.entries.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertTrue(HomeSectionKind.entries.all { it.emptyMessage.isNotBlank() })
        assertEquals(HomeSectionKind.ReadingNow, HomeSectionKind.fromId("readingNow"))
    }
}
