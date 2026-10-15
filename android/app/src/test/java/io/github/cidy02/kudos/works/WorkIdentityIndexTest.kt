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
            loadWorks = { listOf(existing) }
        )
        assertEquals(existing.id, found?.id)
    }

    @Test
    fun returnsNullWhenNoMatch() = runBlocking {
        val found = WorkIdentityIndex.findExisting(
            candidateSourceUrl = "https://archiveofourown.org/works/1",
            loadWorks = { emptyList() }
        )
        assertNull(found)
    }

    /** ReadingQueueTests.existingWorkMatchesCanonicalAO3URLVariants. */
    @Test
    fun existingWorkMatchesCanonicalAO3URLVariants() = runBlocking {
        val existing = SavedWork(title = "Local", author = "A", sourceUrl = "https://archiveofourown.org/downloads/2468/work.epub")
        val found = WorkIdentityIndex.findExisting(
            candidateSourceUrl = "https://archiveofourown.org/works/2468?view_full_work=true#main",
            loadWorks = { listOf(existing) }
        )
        assertEquals(existing.id, found?.id)
        val reverse = WorkIdentityIndex.findExisting(
            candidateSourceUrl = existing.sourceUrl,
            loadWorks = { listOf(existing.copy(sourceUrl = "https://archiveofourown.org/works/2468")) }
        )
        assertEquals(existing.id, reverse?.id)
    }

    @Test
    fun acquisitionUsesStoredAO3IdBeforeCanonicalUrlAndRecordUuid() = runBlocking {
        val strongest = SavedWork(title = "ID", author = "A", ao3WorkID = 2468)
        val canonical = SavedWork(title = "URL", author = "A", sourceUrl = "https://archiveofourown.org/downloads/2468/work.epub")
        val fallback = SavedWork(title = "UUID", author = "A")
        val found = WorkIdentityIndex.findExisting(
            candidateSourceUrl = "https://archiveofourown.org/works/2468",
            candidateLocalId = fallback.id,
            loadWorks = { listOf(strongest, canonical, fallback) }
        )
        assertEquals(strongest.id, found?.id)
        assertNull(WorkIdentityIndex.findExisting(
            candidateSourceUrl = "",
            loadWorks = { listOf(strongest, canonical, fallback) }
        ))
    }

    @Test
    fun canonicalUrlHelper() {
        assertEquals(
            "https://archiveofourown.org/works/99",
            WorkTags.canonicalAO3WorkURL("https://www.archiveofourown.org/works/99/chapters/1")
        )
        assertEquals(
            "https://archiveofourown.org/works/98765",
            WorkTags.canonicalAO3WorkURL("https://archiveofourown.org/downloads/98765/work.epub")
        )
    }
}
