package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SparseWorkEnricherTest {
    private fun sparse(id: Long = 1L) = AO3WorkSummary(
        id = id,
        title = "Subscribed Work",
        authors = listOf("someone"),
        fandoms = emptyList(),
        rating = "",
        warnings = emptyList(),
        categories = emptyList()
    )

    private fun full(id: Long = 2L) = sparse(id).copy(
        fandoms = listOf("Naruto"),
        rating = "Teen And Up Audiences",
        chapters = "3/3"
    )

    private class FakeRepository(
        private val result: AO3Result<AO3WorkMetadata>
    ) : AO3WorkMetadataRepository(io.github.cidy02.kudos.network.ao3.OkHttpAO3Client()) {
        var calls = 0
        override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
            calls++
            return result
        }
    }

    private val metadata = AO3WorkMetadata(
        rating = "Explicit",
        fandoms = listOf("Naruto (Anime & Manga)"),
        warnings = listOf("Graphic Depictions Of Violence"),
        categories = listOf("M/M"),
        language = "English",
        words = 1234,
        chapters = "2/2",
        kudos = 99
    )

    @Test
    fun onlySparseWorksAreFetched() = runTest {
        // Every other list in the app must cost nothing: a complete card never asks.
        val repo = FakeRepository(AO3Result.Success(metadata))
        val enricher = AO3SparseWorkEnricher(repo, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        assertNull(enricher.enrich(full()))
        assertEquals(0, repo.calls)

        assertTrue(AO3SparseWorkEnricher.isSparse(sparse()))
        assertFalse(AO3SparseWorkEnricher.isSparse(full()))
    }

    @Test
    fun aSparseWorkGetsItsMetadataAndKeepsItsListingTitle() = runTest {
        val repo = FakeRepository(AO3Result.Success(metadata))
        val enricher = AO3SparseWorkEnricher(repo, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        val enriched = enricher.enrich(sparse())!!
        assertEquals("Explicit", enriched.rating)
        assertEquals(listOf("Naruto (Anime & Manga)"), enriched.fandoms)
        assertEquals(99, enriched.kudos)
        // The listing's title and author stay — the card must not visibly re-title
        // itself as it fills in.
        assertEquals("Subscribed Work", enriched.title)
        assertEquals(listOf("someone"), enriched.authors)
    }

    @Test
    fun aSecondLookOfTheSameWorkIsServedFromMemory() = runTest {
        val repo = FakeRepository(AO3Result.Success(metadata))
        val enricher = AO3SparseWorkEnricher(repo, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        enricher.enrich(sparse())
        enricher.enrich(sparse())
        // Paging back to a list must not re-fetch what it already has.
        assertEquals(1, repo.calls)
    }

    @Test
    fun aFailedWorkIsNotRetriedOnEveryScroll() = runTest {
        // A deleted or registered-users-only work 404s forever; the sparse card
        // stands rather than the list hammering AO3 as the user scrolls past it.
        val repo = FakeRepository(AO3Result.Failure(AO3Error.NotFound))
        val enricher = AO3SparseWorkEnricher(repo, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        assertNull(enricher.enrich(sparse()))
        assertNull(enricher.enrich(sparse()))
        assertEquals(1, repo.calls)
    }

    @Test
    fun anEmptyMetadataResponseCountsAsAFailure() = runTest {
        // A work page that parses to nothing would otherwise blank the card's few
        // real fields and be retried forever.
        val repo = FakeRepository(AO3Result.Success(AO3WorkMetadata()))
        val enricher = AO3SparseWorkEnricher(repo, CoroutineScope(UnconfinedTestDispatcher(testScheduler)))
        assertNull(enricher.enrich(sparse()))
        assertNull(enricher.enrich(sparse()))
        assertEquals(1, repo.calls)
    }
}
