package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.work.AO3DownloadUrlBuilder
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataParser
import java.io.File
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoNetworkBlockTest {
    @Test
    fun routesMatchTheIosTable() {
        assertEquals("ao3_media", name("https://archiveofourown.org/media"))
        assertEquals("ao3_media", name("https://archiveofourown.org/media/"))
        assertEquals(
            "ao3_media_fandoms",
            name("https://archiveofourown.org/media/TV%20Shows/fandoms")
        )
        assertEquals(
            "ao3_tag_works",
            name("https://archiveofourown.org/tags/Doctor%20Who/works")
        )
        assertEquals("ao3_work_edit", name("https://archiveofourown.org/works/123/edit"))
        assertEquals(
            "ao3_work_bookmarked_subscribed",
            name("https://archiveofourown.org/works/123")
        )
        assertEquals(
            "ao3_comments_page",
            name("https://archiveofourown.org/works/123/chapters/2/comments")
        )
        assertEquals("ao3_logged_in", name("https://archiveofourown.org/"))
        assertNull(name("https://archiveofourown.org/admin/posts"))
    }

    @Test
    fun hostCheckIsTheApexAndItsSubdomainsOnly() {
        assertTrue(DemoNetworkRoutes.isAo3Host("archiveofourown.org"))
        assertTrue(DemoNetworkRoutes.isAo3Host("download.archiveofourown.org"))
        assertFalse(DemoNetworkRoutes.isAo3Host("archiveofourown.org.evil.com"))
        assertFalse(DemoNetworkRoutes.isAo3Host("notarchiveofourown.org"))
    }

    @Test
    fun activeBlockServesAFixtureAndRefusesEveryOtherAo3UrlLocally() {
        var proceeded = false
        val fixtures = FixtureSource { fixture ->
            if (fixture == "ao3_media") "<html>media</html>".toByteArray() else null
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
            .addInterceptor { chain ->
                proceeded = true
                sentinel(chain.request())
            }
            .build()

        client.newCall(get("https://archiveofourown.org/media")).execute().use { response ->
            assertEquals(200, response.code)
            assertEquals("<html>media</html>", response.body.string())
        }
        assertFalse(proceeded)

        client.newCall(get("https://archiveofourown.org/admin/posts")).execute().use { response ->
            assertEquals(404, response.code)
            assertEquals("", response.body.string())
        }
        assertFalse(proceeded)

        client.newCall(get("https://download.archiveofourown.org/no-such")).execute().use { response ->
            assertEquals(404, response.code)
        }
        assertFalse(proceeded)

        client.newCall(get("https://example.com/media")).execute().use { response ->
            assertEquals(200, response.code)
            assertEquals("sentinel", response.body.string())
        }
        assertTrue(proceeded)
    }

    @Test
    fun inactiveBlockLetsTheRequestThrough() {
        var proceeded = false
        val client = OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { false }, fixtures = { FixtureSource { null } }))
            .addInterceptor { chain ->
                proceeded = true
                sentinel(chain.request())
            }
            .build()

        client.newCall(get("https://archiveofourown.org/media")).execute().use { response ->
            assertEquals("sentinel", response.body.string())
        }
        assertTrue(proceeded)
    }

    @Test
    fun defaultAo3ClientInstallsTheBlockAheadOfTheRedirectRelay() {
        val client = OkHttpAO3Client.defaultOkHttpClient()
        assertTrue(client.interceptors.first() is DemoNetworkInterceptor)
        assertTrue(client.interceptors[1] is AO3RedirectCookieRelayInterceptor)
    }

    @Test
    fun subscriptionPageAndItsMetadataLookupsAreAnsweredByBundledDemoFixtures() {
        val fixtures = FixtureSource { fixture ->
            val candidates = listOf(
                File("src/debug/assets/fixtures/$fixture.html"),
                File("app/src/debug/assets/fixtures/$fixture.html"),
                File("android/app/src/debug/assets/fixtures/$fixture.html")
            )
            candidates.firstOrNull(File::isFile)?.readBytes()
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
            .addInterceptor { error("Demo fixture lookup must never reach the network") }
            .build()
        fun html(url: String): String = client.newCall(get(url)).execute().use { response ->
            assertEquals(200, response.code)
            response.body.string()
        }
        val page = AO3AccountParser().parseSubscriptionsPage(
            html("https://archiveofourown.org/users/AO3_Reader/subscriptions?type=works&page=1"), 1
        )
        assertEquals(listOf(45678901L, 12345L, 999000002L), page.works.map { it.id })
        assertEquals(listOf("A Study in Pink", "Another Fic", "Paper Cranes"), page.works.map { it.title })
        assertTrue(page.works.all { it.chapters.isEmpty() }) // Enrichment still takes the real lookup path.
        val urls = AO3DownloadUrlBuilder()
        val metadata = page.works.map { work ->
            val url = urls.workMetadataUrl(work.id)
            assertEquals("true", url.toHttpUrl().queryParameter("view_adult"))
            AO3WorkMetadataParser().parse(html(url))
        }
        assertEquals(listOf("5/?", "8/12", "1/1"), metadata.map { it.chapters })
        assertTrue(metadata.all { !it.isEmpty && it.rating.isNotEmpty() })
        assertEquals(2210, metadata.last().words)
        // Specific metadata routes must not swallow the established action fixtures.
        assertEquals("ao3_work_edit", name("https://archiveofourown.org/works/12345/edit"))
        assertEquals("ao3_chapter_navigate", name("https://archiveofourown.org/works/45678901/navigate"))
        assertEquals("ao3_comments_page", name("https://archiveofourown.org/works/999000002/comments"))
    }

    private fun name(url: String): String? =
        DemoNetworkRoutes.fixtureName(DemoNetworkRoutes.decodedPath(url.toHttpUrl()))

    private fun get(url: String): Request = Request.Builder().url(url).build()

    private fun sentinel(request: Request): Response = Response.Builder()
        .request(request)
        .protocol(Protocol.HTTP_1_1)
        .code(200)
        .message("OK")
        .body("sentinel".toResponseBody("text/plain".toMediaType()))
        .build()
}
