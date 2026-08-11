package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkIdentityIndexTest {
    @Test
    fun findsByCanonicalAo3UrlWhenStoredWithWww() = runBlocking {
        val existing = SavedWork(
            id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            title = "Local",
            author = "A",
            sourceUrl = "https://www.archiveofourown.org/works/4242"
        )
        val found = WorkIdentityIndex.findExisting(
            candidateSourceUrl = "https://archiveofourown.org/works/4242",
            byId = { null },
            bySourceUrl = { url -> if (url == existing.sourceUrl || url.contains("4242")) existing else null }
        )
        assertEquals(existing.id, found?.id)
    }

    @Test
    fun returnsNullWhenNoMatch() = runBlocking {
        val found = WorkIdentityIndex.findExisting(
            candidateSourceUrl = "https://archiveofourown.org/works/1",
            byId = { null },
            bySourceUrl = { null }
        )
        assertNull(found)
    }

    @Test
    fun canonicalUrlHelper() {
        assertEquals(
            "https://archiveofourown.org/works/99",
            WorkTags.canonicalAO3WorkURL("https://www.archiveofourown.org/works/99/chapters/1")
        )
    }
}
