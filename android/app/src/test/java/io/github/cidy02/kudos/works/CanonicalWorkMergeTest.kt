package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class CanonicalWorkMergeTest {
    @Test
    fun remoteLedPairsSavedWorkWithMatchingAo3Id() {
        val local = SavedWork(
            id = "local-uuid-1",
            title = "Local Work",
            author = "Author",
            sourceUrl = "https://archiveofourown.org/works/12345"
        )
        val remote = AO3WorkSummary(
            id = 12345L,
            title = "Remote Work Title",
            authors = listOf("Author"),
            fandoms = emptyList(),
            rating = "",
            warnings = emptyList(),
            categories = emptyList()
        )

        val result = CanonicalWorkMerge.remoteLed(listOf(remote), listOf(local))
        assertEquals(1, result.size)
        assertNotNull(result.single().local)
        assertEquals("local-uuid-1", result.single().local?.id)
    }

    @Test
    fun remoteLedOnlyPairsFirstMentionOfDuplicates() {
        val local = SavedWork(
            id = "local-uuid-1",
            title = "Local Work",
            author = "Author",
            sourceUrl = "https://archiveofourown.org/works/12345"
        )
        val remote1 = AO3WorkSummary(id = 12345L, title = "Title", authors = listOf("Author"), fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList())
        val remote2 = AO3WorkSummary(id = 12345L, title = "Title", authors = listOf("Author"), fandoms = emptyList(), rating = "", warnings = emptyList(), categories = emptyList())

        val result = CanonicalWorkMerge.remoteLed(listOf(remote1, remote2), listOf(local))
        assertEquals(2, result.size)
        assertNotNull(result[0].local)
        assertNull(result[1].local)
    }
}
