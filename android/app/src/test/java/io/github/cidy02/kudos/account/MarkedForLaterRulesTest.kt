package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.settings.LocalStorageFootprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `AO3MarkedForLaterScreenTests` (A59). */
class MarkedForLaterRulesTest {
    private data class Row(val name: String, val updated: Boolean = false, val downloaded: Boolean = false)
    private val rows = listOf(Row("updated-downloaded", true, true), Row("downloaded", downloaded = true),
        Row("plain"), Row("updated", updated = true))
    private fun sections(filter: String, source: List<Row> = rows) =
        markedForLaterSections(source, filter, { it.updated }, { it.downloaded })

    @Test fun allSplitsUpdatedAheadOfEverythingElse() {
        val split = sections("all")
        assertEquals(listOf("Updated since you looked", "Everything else"), split.map { it.title })
        assertEquals(listOf(true, false), split.map { it.covers })
        assertEquals(listOf("updated-downloaded", "updated"), split[0].items.map { it.name })
        assertEquals(listOf("downloaded", "plain"), split[1].items.map { it.name })
        assertEquals(listOf(true), sections("all", rows.filter { it.updated }).map { it.covers })
        assertEquals(emptyList<MarkedForLaterSection<Row>>(), sections("all", emptyList()))
    }

    @Test fun narrowedPillsAreOneList() {
        val updated = sections("updated").single()
        assertNull(updated.title)
        assertEquals(true, updated.covers)
        assertEquals(listOf("updated-downloaded", "updated"), updated.items.map { it.name })
        val downloaded = sections("downloaded").single()
        assertNull(downloaded.title)
        assertEquals(false, downloaded.covers)
        assertEquals(listOf("updated-downloaded", "downloaded"), downloaded.items.map { it.name })
    }

    @Test fun anEmptiedPageReloadsOneThatHasRows() {
        assertEquals(1, pageAfterEmptying(currentPage = 2, totalPages = 2))
        assertEquals(3, pageAfterEmptying(currentPage = 4, totalPages = 4))
        assertEquals(1, pageAfterEmptying(currentPage = 1, totalPages = 3))
        assertEquals(2, pageAfterEmptying(currentPage = 2, totalPages = 3))
        assertNull(pageAfterEmptying(currentPage = 1, totalPages = 1))
    }

    @Test fun downloadLineRequiresARealSizeAndUsesTheSharedFileSizeLabel() {
        val label = LocalStorageFootprint.formatted(1_400_000)
        assertEquals("Downloaded · $label", markedForLaterDownloadLine(hasEpub = true, byteLabel = label))
        assertNull(markedForLaterDownloadLine(hasEpub = false, byteLabel = label))
        assertNull(markedForLaterDownloadLine(hasEpub = true, byteLabel = null))
        assertNull(markedForLaterDownloadLine(hasEpub = true, byteLabel = ""))
    }
}
