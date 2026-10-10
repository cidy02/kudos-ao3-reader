package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class AuthorWorksSortTest {
    @org.junit.Before fun clearPageCache() { io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear() }
    @Test fun everySortDirectionAndCompletionMatchesSwiftQueryAndMakesOnePageRead() = runBlocking<Unit> {
        val expected = listOf("authors_to_sort_on", "title_to_sort_on", "created_at", "revised_at", "word_count",
            "hits", "kudos_count", "comments_count", "bookmarks_count")
        val client = object : AO3Client {
            val reads = mutableListOf<String>()
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                reads += url
                return AO3Result.Failure(AO3Error.Network("offline test"))
            }
        }
        val repository = AO3AuthorRepository(publicClient = client, parseDispatcher = Dispatchers.Unconfined)
        for ((index, column) in AO3AuthorWorksSortColumn.entries.withIndex()) {
            assertEquals(expected[index], column.ao3Value)
            assertEquals(if (index < 2) AO3AuthorWorksSortDirection.Ascending else AO3AuthorWorksSortDirection.Descending,
                column.defaultDirection)
            for (direction in AO3AuthorWorksSortDirection.entries) for (completion in AO3AuthorWorksCompletion.entries) {
                val sort = AO3AuthorWorksSort(column, direction, completion)
                val before = client.reads.size
                repository.loadWorks(AO3AuthorRoute("A Writer", "A Pseud"), 3, AO3AuthorWorksScope.Collected, sort)
                assertEquals(before + 1, client.reads.size)
                val url = client.reads.last().toHttpUrl()
                assertEquals(listOf("users", "A Writer", "pseuds", "A Pseud", "works", "collected"), url.pathSegments)
                assertEquals("3", url.queryParameter("page"))
                assertEquals(column.ao3Value.takeUnless { column == AO3AuthorWorksSortColumn.DateUpdated },
                    url.queryParameter("work_search[sort_column]"))
                assertEquals(direction.ao3Value.takeUnless { direction == column.defaultDirection },
                    url.queryParameter("work_search[sort_direction]"))
                assertEquals(when (completion) { AO3AuthorWorksCompletion.Any -> null
                    AO3AuthorWorksCompletion.Complete -> "T"; AO3AuthorWorksCompletion.InProgress -> "F" },
                    url.queryParameter("work_search[complete]"))
                assertTrue(url.queryParameterNames.all { it in setOf("page", "work_search[sort_column]",
                    "work_search[sort_direction]", "work_search[complete]") })
            }
        }
        assertEquals("https://archiveofourown.org/users/Writer/works", AO3AuthorUrls.userWorksUrl("Writer"))
        val nonDefault = AO3AuthorWorksSort(AO3AuthorWorksSortColumn.Title, AO3AuthorWorksSortDirection.Descending,
            AO3AuthorWorksCompletion.Complete)
        assertEquals("https://archiveofourown.org/users/Writer/gifts",
            AO3AuthorUrls.userWorksUrl("Writer", scope = AO3AuthorWorksScope.Gifts, sort = nonDefault))
        assertEquals(3, nonDefault.activeCount)
        assertEquals(0, AO3AuthorWorksSort().activeCount)
        val title = nonDefault.select(AO3AuthorWorksSortColumn.Title)
        assertEquals(nonDefault, title) // A re-tap preserves the explicit direction.
        assertEquals(AO3AuthorWorksSortDirection.Ascending, title.select(AO3AuthorWorksSortColumn.Creator).direction)
    }

    @Test fun authenticatedRefusalIsNotRetriedAnonymouslyAndSignedOutReadsOnlyPublic() = runBlocking<Unit> {
        var publicReads = 0
        var authenticatedReads = 0
        var username: String? = "Reader"
        val public = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                publicReads++
                return AO3Result.Failure(AO3Error.Network("offline test"))
            }
        }
        val auth = object : AO3AuthenticatedClient {
            override fun username() = username
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
                authenticatedReads++
                return AO3Result.Failure(AO3Error.Forbidden)
            }
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
                headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("No writes")
        }
        val repo = AO3AuthorRepository(public, auth)
        assertEquals(AO3Error.Forbidden, (repo.loadWorks(AO3AuthorRoute("Writer")) as AO3Result.Failure).error)
        assertEquals(1, authenticatedReads); assertEquals(0, publicReads)
        username = null
        repo.loadWorks(AO3AuthorRoute("Writer"))
        assertEquals(1, authenticatedReads); assertEquals(1, publicReads)
    }
}
