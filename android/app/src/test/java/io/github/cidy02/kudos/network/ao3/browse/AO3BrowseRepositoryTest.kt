package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import java.nio.file.Files
import java.time.Duration
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private fun browseFixture(path: String): String {
    val stream = AO3BrowseRepositoryTest::class.java.classLoader!!.getResourceAsStream(path)
        ?: error("Missing fixture: $path")
    return stream.bufferedReader().use { it.readText() }
}

private class FakeAO3Client(
    private val responder: (String) -> AO3Result<AO3HttpResponse>
) : AO3Client {
    val requestedUrls = mutableListOf<String>()

    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        requestedUrls += url
        return responder(url)
    }
}

private fun ok(body: String): AO3Result<AO3HttpResponse> = AO3Result.Success(
    AO3HttpResponse(
        url = "https://archiveofourown.org/x",
        statusCode = 200,
        headers = emptyMap(),
        body = body
    )
)

private fun repoWith(client: FakeAO3Client) =
    AO3BrowseRepository(client = client, searchRepository = AO3SearchRepository(client))

private fun repoWithCache(client: FakeAO3Client, cache: FandomCatalogCache, nowMillis: Long) =
    AO3BrowseRepository(
        client = client,
        searchRepository = AO3SearchRepository(client),
        cache = cache,
        clock = AO3Clock { nowMillis }
    )

class AO3BrowseRepositoryTest {
    @Test
    fun categoriesParseFromMediaIndex() = runTest {
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/categories.html")) }
        val result = repoWith(client).categories()

        assertTrue(result is AO3Result.Success)
        assertEquals(listOf("Anime & Manga", "TV Shows"), (result as AO3Result.Success).value.map { it.name })
        assertEquals("https://archiveofourown.org/media", client.requestedUrls.single())
    }

    @Test
    fun categoriesOverloadBecomesTypedError() = runTest {
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/overload.html")) }
        val result = repoWith(client).categories()
        assertTrue((result as AO3Result.Failure).error is AO3Error.Overloaded)
    }

    @Test
    fun categoriesChangedMarkupBecomesParseError() = runTest {
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/parser_changed.html")) }
        val result = repoWith(client).categories()
        assertTrue((result as AO3Result.Failure).error is AO3Error.Parse)
    }

    @Test
    fun fandomsResolveCategoryPathAndParse() = runTest {
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/fandom_list.html")) }
        val category = AO3MediaCategory(name = "Anime & Manga", fandomsPath = "/media/Anime/fandoms")

        val result = repoWith(client).fandoms(category)

        assertTrue(result is AO3Result.Success)
        assertEquals(listOf("Naruto", "Bleach", "Example Fandom"), (result as AO3Result.Success).value.map { it.name })
        assertEquals("https://archiveofourown.org/media/Anime/fandoms", client.requestedUrls.single())
    }

    @Test
    fun fandomsWithNoPathFailsWithoutNetwork() = runTest {
        val client = FakeAO3Client { ok("") }
        val category = AO3MediaCategory(name = "Broken", fandomsPath = "")

        val result = repoWith(client).fandoms(category)

        assertTrue((result as AO3Result.Failure).error is AO3Error.Validation)
        assertTrue("must not hit the network", client.requestedUrls.isEmpty())
    }

    @Test
    fun worksForFandomGoesThroughSearchAndParsesBlurbs() = runTest {
        val searchHtml = """
            <ol class="work index group">
              <li id="work_123" class="work blurb group">
                <h4 class="heading">
                  <a href="/works/123">Test Work</a>
                  <a rel="author" href="/users/alice">Alice</a>
                </h4>
              </li>
            </ol>
        """.trimIndent()
        val client = FakeAO3Client { ok(searchHtml) }

        val result = repoWith(client).worksForFandom("Naruto")

        assertTrue(result is AO3Result.Success)
        val page: AO3SearchPage = (result as AO3Result.Success).value
        assertEquals(1, page.works.size)
        assertEquals(123L, page.works.first().id)
        // The search URL carries the fandom filter.
        assertTrue(client.requestedUrls.single().contains("work_search%5Bfandom_names%5D=Naruto"))
    }

    @Test
    fun worksForBlankFandomFailsWithoutNetwork() = runTest {
        val client = FakeAO3Client { ok("") }
        val result = repoWith(client).worksForFandom("   ")
        assertTrue((result as AO3Result.Failure).error is AO3Error.Validation)
        assertTrue(client.requestedUrls.isEmpty())
    }

    @Test
    fun fandomsFreshCacheHitSkipsNetwork() = runTest {
        val cache = FandomCatalogCache(Files.createTempDirectory("kudos-fandom-cache"))
        val category = AO3MediaCategory(name = "Anime & Manga", fandomsPath = "/media/Anime/fandoms")
        cache.save(mapOf(category.name to FandomCatalogCache.Entry(listOf(AO3Fandom("Naruto")), 0L)))
        val client = FakeAO3Client { ok("") }

        val result = repoWithCache(client, cache, nowMillis = 0L).fandoms(category)

        assertTrue(result is AO3Result.Success)
        assertEquals(listOf("Naruto"), (result as AO3Result.Success).value.map { it.name })
        assertTrue(client.requestedUrls.isEmpty())
    }

    @Test
    fun fandomsStaleCacheRefetchesAndPersistsTheNewResult() = runTest {
        val cache = FandomCatalogCache(Files.createTempDirectory("kudos-fandom-cache"))
        val category = AO3MediaCategory(name = "Anime & Manga", fandomsPath = "/media/Anime/fandoms")
        cache.save(mapOf(category.name to FandomCatalogCache.Entry(listOf(AO3Fandom("Stale")), 0L)))
        val eightDaysMillis = Duration.ofDays(8).toMillis()
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/fandom_list.html")) }

        val result = repoWithCache(client, cache, nowMillis = eightDaysMillis).fandoms(category)

        assertTrue(result is AO3Result.Success)
        assertEquals(
            listOf("Naruto", "Bleach", "Example Fandom"),
            (result as AO3Result.Success).value.map { it.name }
        )
        assertEquals(1, client.requestedUrls.size)
        val persisted = cache.load()[category.name]
        assertEquals(eightDaysMillis, persisted?.fetchedAtEpochMillis)
        assertEquals(listOf("Naruto", "Bleach", "Example Fandom"), persisted?.fandoms?.map { it.name })
    }

    @Test
    fun fandomsCacheMissPersistsAlongsideExistingCategories() = runTest {
        val cache = FandomCatalogCache(Files.createTempDirectory("kudos-fandom-cache"))
        val existingCategory = "TV Shows"
        cache.save(mapOf(existingCategory to FandomCatalogCache.Entry(listOf(AO3Fandom("Existing")), 0L)))
        val category = AO3MediaCategory(name = "Anime & Manga", fandomsPath = "/media/Anime/fandoms")
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/fandom_list.html")) }

        repoWithCache(client, cache, nowMillis = 1L).fandoms(category)

        assertEquals(setOf(existingCategory, category.name), cache.load().keys)
    }
}
