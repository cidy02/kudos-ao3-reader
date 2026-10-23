package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.nio.file.Files
import java.time.Duration
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertNull
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

private fun repoWithCache(
    client: FakeAO3Client,
    cache: FandomCatalogCache,
    nowMillis: Long,
    demoActive: () -> Boolean = { false }
) = AO3BrowseRepository(
    client = client,
    searchRepository = AO3SearchRepository(client),
    cache = cache,
    clock = AO3Clock { nowMillis },
    demoActive = demoActive
)

class AO3BrowseRepositoryTest {
    @Test fun explicitRefreshBypassesAFreshCatalogAndReplacesItOnlyAfterSuccess() = runTest {
        val directory = Files.createTempDirectory("fandom-refresh")
        try {
            val cache = FandomCatalogCache(directory)
            val category = AO3MediaCategory("Anime & Manga", "/media/Anime/fandoms")
            cache.save(mapOf(category.name to FandomCatalogCache.Entry(listOf(AO3Fandom("Old")), 0)))
            val client = FakeAO3Client { ok(browseFixture("ao3/browse/fandom_list.html")) }
            val repository = repoWithCache(client, cache, 0)
            repository.fandoms(category, bypassCache = true)
            assertEquals(1, client.requestedUrls.size)
            assertTrue(cache.load()[category.name]!!.fandoms.none { it.name == "Old" })
            val failed = repoWithCache(FakeAO3Client { AO3Result.Failure(AO3Error.Forbidden) }, cache, 0)
            val prior = cache.load()
            failed.fandoms(category, bypassCache = true)
            assertEquals(prior, cache.load())
        } finally { directory.toFile().deleteRecursively() }
    }


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
    fun worksForTagSendsViewAdultTrue() = runTest {
        val searchHtml = """
            <ol class="work index group">
              <li id="work_456" class="work blurb group">
                <h4 class="heading">
                  <a href="/works/456">Tag Work</a>
                  <a rel="author" href="/users/bob">Bob</a>
                </h4>
              </li>
            </ol>
        """.trimIndent()
        val client = FakeAO3Client { ok(searchHtml) }

        val result = repoWith(client).worksForTag("Fluff")

        assertTrue(result is AO3Result.Success)
        val requestedUrl = client.requestedUrls.single().toHttpUrl()
        assertEquals("/tags/Fluff/works", requestedUrl.encodedPath)
        assertEquals("true", requestedUrl.queryParameter("view_adult"))
        assertEquals(null, requestedUrl.queryParameter("work_search[fandom_names]"))

        // In contrast, worksForFandom does not send view_adult.
        val fandomClient = FakeAO3Client { ok(searchHtml) }
        repoWith(fandomClient).worksForFandom("Naruto")
        val fandomUrl = fandomClient.requestedUrls.single().toHttpUrl()
        assertEquals(null, fandomUrl.queryParameter("view_adult"))
    }

    @Test fun siblingUnionResolvesSequentiallyThenRunsOneSearchAndReusesIDs() = runTest {
        val client = FakeAO3Client { url ->
            when {
                "/tags/First/works" in url -> ok("<head><link rel='alternate' type='application/atom+xml' href='/tags/27785/feed.atom'></head>")
                "/tags/Second/works" in url -> ok("<head><link rel='alternate' type='application/atom+xml' href='/tags/99117/feed.atom'></head>")
                else -> ok("<ol class='work index group'></ol>")
            }
        }
        val repository = repoWith(client)
        val filters = io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters(query = "fluff", wordsFrom = "100")
        assertTrue(repository.worksForFandoms(listOf("First", "Second"), filters = filters) is AO3Result.Success)
        assertEquals(3, client.requestedUrls.size)
        val url = client.requestedUrls.last().toHttpUrl()
        assertEquals("/works/search", url.encodedPath)
        assertEquals("fluff filter_ids:(27785 OR 99117)", url.queryParameter("work_search[query]"))
        assertEquals(null, url.queryParameter("work_search[fandom_names]"))
        assertEquals("> 100", url.queryParameter("work_search[word_count]"))
        repository.worksForFandoms(listOf("First", "Second"), page = 2, filters = filters)
        assertEquals(4, client.requestedUrls.size)
    }

    @Test fun unresolvedSiblingFallsBackToAllNamesWithoutCachingAnExactFamilyCount() = runTest {
        val client = FakeAO3Client { url ->
            ok(if (url.contains("/works/search")) """<h2 class='heading'>1 - 1 of 12 Works</h2>
                <ol class='work index group'><li class='work blurb group' id='work_123'>
                <h4 class='heading'><a href='/works/123'>Found through all names</a></h4></li></ol>"""
                else "<p>No canonical filter ID</p>")
        }
        val repository = repoWith(client)
        assertTrue(repository.worksForFandoms(listOf("First", "Second")) is AO3Result.Success)
        assertEquals(2, client.requestedUrls.size)
        assertEquals("First, Second", client.requestedUrls.last().toHttpUrl().queryParameter("work_search[fandom_names]"))
        assertNull(repository.exactFamilyCounts.totals.value[io.github.cidy02.kudos.browse.FandomFamily.id(listOf("First", "Second"))])
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

    @Test
    fun fandomsInDemoSkipTheCacheAndDoNotWriteIt() = runTest {
        val cache = FandomCatalogCache(Files.createTempDirectory("kudos-fandom-cache"))
        val category = AO3MediaCategory(name = "Anime & Manga", fandomsPath = "/media/Anime/fandoms")
        cache.save(mapOf(category.name to FandomCatalogCache.Entry(listOf(AO3Fandom("Live Cache")), 0L)))
        val client = FakeAO3Client { ok(browseFixture("ao3/browse/fandom_list.html")) }

        val result = repoWithCache(client, cache, nowMillis = 0L, demoActive = { true }).fandoms(category)

        assertTrue(result is AO3Result.Success)
        assertEquals(
            listOf("Naruto", "Bleach", "Example Fandom"),
            (result as AO3Result.Success).value.map { it.name }
        )
        assertEquals(1, client.requestedUrls.size)
        assertEquals(listOf("Live Cache"), cache.load()[category.name]?.fandoms?.map { it.name })
    }
}
