package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkSearchIndexTest {
    @Test
    fun normalizeFoldsCaseAndDiacritics() {
        val raw = "Héroïne & Fluff"
        val terms = WorkSearchIndex.terms(raw)
        assertTrue(terms.contains("heroine"))
        assertTrue(terms.contains("fluff"))
    }

    @Test
    fun matchesRequiresAllQueryTerms() {
        val work = SavedWork(
            title = "The Heroine's Journey",
            author = "AwesomeWriter",
            workFandoms = listOf("Harry Potter"),
            workFreeforms = listOf("Fluff", "Alternate Universe")
        )

        assertTrue(WorkSearchIndex.matches(work, listOf("heroine", "fluff")))
        assertTrue(WorkSearchIndex.matches(work, listOf("potter", "journey")))
        assertFalse(WorkSearchIndex.matches(work, listOf("heroine", "angst")))
    }

    @Test
    fun reindexStampsCurrentVersionAndIncludesUserTags() {
        val work = SavedWork(title = "Story", author = "Author")
        val indexed = WorkSearchIndex.reindex(work, userTags = listOf("Comfort"))
        assertEquals(WorkSearchIndex.CURRENT_VERSION, indexed.searchIndexVersion)
        assertTrue(indexed.searchText.contains("comfort"))
        assertTrue(WorkSearchIndex.matches(indexed, listOf("comfort")))
    }
}
