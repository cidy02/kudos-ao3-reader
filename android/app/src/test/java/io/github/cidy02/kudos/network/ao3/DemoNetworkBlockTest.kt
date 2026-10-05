package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParser
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesUrls
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
import org.jsoup.Jsoup

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
        val client = bundledDemoClient()
        val page = AO3AccountParser().parseSubscriptionsPage(
            html(client, "https://archiveofourown.org/users/AO3_Reader/subscriptions?type=works&page=1"), 1
        )
        assertEquals(listOf(45678901L, 12345L, 999000002L), page.works.map { it.id })
        assertEquals(listOf("A Study in Pink", "Another Fic", "Paper Cranes"), page.works.map { it.title })
        assertTrue(page.works.all { it.chapters.isEmpty() }) // Enrichment still takes the real lookup path.
        val urls = AO3DownloadUrlBuilder()
        val metadata = page.works.map { work ->
            val url = urls.workMetadataUrl(work.id)
            assertEquals("true", url.toHttpUrl().queryParameter("view_adult"))
            AO3WorkMetadataParser().parse(html(client, url))
        }
        assertEquals(listOf("5/?", "8/12", "1/1"), metadata.map { it.chapters })
        assertTrue(metadata.all { !it.isEmpty && it.rating.isNotEmpty() })
        assertEquals(2210, metadata.last().words)
        // Specific metadata routes must not swallow the established action fixtures.
        assertEquals("ao3_work_edit", name("https://archiveofourown.org/works/12345/edit"))
        assertEquals("ao3_chapter_navigate", name("https://archiveofourown.org/works/45678901/navigate"))
        assertEquals("ao3_comments_page", name("https://archiveofourown.org/works/999000002/comments"))
    }

    @Test
    fun demoSeriesPageHasFourOrderedWorksAndKeepsEditRouting() {
        val client = bundledDemoClient()
        val url = AO3SeriesUrls.seriesPageUrl("https://archiveofourown.org/series/999", 1)!!
        val body = html(client, url)
        val page = AO3SearchParser().parseSearchPage(body, 1)
        assertEquals(listOf(999000005L, 999000003L, 999000002L, 999000004L), page.works.map { it.id })
        assertEquals(listOf("Sodium Lights", "Ashfall", "Paper Cranes", "The Long Way Down"), page.works.map { it.title })
        assertEquals(listOf(1, 2, 3, 4), page.works.map { it.seriesPosition })
        assertTrue(page.works.all { it.seriesTitle == "My Series" && it.seriesUrl == url })
        assertEquals(listOf(true, false, true, false), page.works.map { it.isComplete })
        assertEquals(listOf(false, false, true, false), page.works.map { it.isRestricted })
        assertEquals(listOf("1/1", "9/?", "1/1", "7/18"), page.works.map { it.chapters })
        assertEquals(1, page.totalPages)
        val doc = Jsoup.parse(body)
        assertFalse(doc.select("dl.series.meta blockquote.userstuff").text().isBlank())
        assertEquals("190,114", doc.selectFirst("dl.series.meta dd.words")!!.text())
        assertEquals(190114, page.works.sumOf { it.wordCount ?: 0 })
        assertEquals("4", doc.selectFirst("dl.series.meta dd.works")!!.text())
        assertEquals("No", doc.selectFirst("dl.series.meta dd.complete")!!.text())
        assertEquals("7", doc.selectFirst("dl.series.meta dd.bookmarks")!!.text())
        assertEquals("ao3_series_edit", name("https://archiveofourown.org/series/999/edit"))
        assertEquals(body, html(client, "$url/?page=1"))
    }

    @Test
    fun winterCollectionTabsAreAnsweredWithBookmarksAndPeople() {
        val client = bundledDemoClient()
        val base = "https://archiveofourown.org/collections/winter_exchange"
        val parser = AO3CollectionParser()
        val show = parser.parseCollectionShow(html(client, "$base/profile"), "winter_exchange")
        assertEquals("Winter Exchange 2026", show.collection.title)
        assertEquals(18, show.collection.bookmarksCount)
        val search = AO3SearchParser()
        assertFalse(search.parseSearchPage(html(client, "$base/works?page=1"), 1).works.isEmpty())
        val bookmarks = search.parseWorksListPage(html(client, "$base/bookmarks?page=1"), 1, "li.bookmark.blurb")
        assertEquals(show.collection.bookmarksCount, bookmarks.works.size)
        assertEquals((999001001L..999001018L).toList(), bookmarks.works.map { it.id })
        assertTrue(bookmarks.works.all { it.summary.isNotBlank() && it.chapters == "1/1" })
        assertEquals(1, bookmarks.totalPages)
        val peopleHtml = html(client, "$base/people?page=1")
        val people = parser.parseCollectionPeoplePage(peopleHtml, 1)
        assertEquals(listOf("AO3_Reader", "comod", "saltandsilver", "meridian", "tidewrack"),
            people.people.map { it.identity.displayName })
        assertEquals(listOf(2, 1, 3, 1, 0), people.people.map { it.workCount })
        assertTrue(people.people.map { it.identity.displayName }.containsAll(show.collection.maintainerNames))
        assertEquals(listOf("Owner", "Maintainer", "Owner", "Moderator", "Member"),
            Jsoup.parse(peopleHtml).select("li.pseud.blurb p.role").map { it.text() })
        assertEquals(1, people.totalPages)
        assertEquals("ao3_collection_participants", name("$base/participants"))
    }

    @Test
    fun demoAccountBookmarksAndAshfallMetadataHaveTheSameIdentity() {
        val client = bundledDemoClient()
        val body = html(client, "https://archiveofourown.org/users/AO3_Reader/bookmarks")
        // Ashfall joins the page's two older demo bookmarks; their paging and chips stay to be seen.
        val works = AO3SearchParser().parseWorksListPage(body, 1, "li.bookmark.blurb").works
        assertEquals(3, works.size)
        val work = works.single { it.id == 999000003L }
        assertEquals("Ashfall", work.title)
        assertEquals(listOf("TempusFugit"), work.authors)
        assertEquals("Mature", work.rating)
        assertEquals(41780, work.wordCount)
        assertEquals("9/?", work.chapters)
        val metadata = AO3WorkMetadataParser().parse(html(client, AO3DownloadUrlBuilder().workMetadataUrl(work.id)))
        assertEquals(work.rating, metadata.rating)
        assertEquals(work.wordCount, metadata.words)
        assertEquals(work.chapters, metadata.chapters)
        assertEquals(work.fandoms, metadata.fandoms)
        assertEquals(work.categories, metadata.categories)
        assertEquals("ao3_work_edit", name("${work.workUrl}/edit"))
        assertEquals("ao3_comments_page", name("${work.workUrl}/comments"))
        assertEquals("ao3_author_bookmarks", name("https://archiveofourown.org/users/OtherReader/bookmarks"))
    }

    @Test
    fun subscriptionIndexRetainsIosSeriesAndAuthorLinksWithoutTreatingThemAsWorks() {
        val body = html(bundledDemoClient(), "https://archiveofourown.org/users/AO3_Reader/subscriptions?type=works")
        val doc = Jsoup.parse(body)
        val series = doc.selectFirst("dl.subscription dt a[href=/series/999]")!!
        assertEquals("My Series", series.text())
        assertEquals("seriesauthor", series.parent()!!.select("a[rel=author]").text())
        assertEquals("someuser", doc.selectFirst("dl.subscription dt a[href=/users/someuser]")!!.text())
        assertEquals(listOf(45678901L, 12345L, 999000002L),
            AO3AccountParser().parseSubscriptionsPage(body, 1).works.map { it.id })
    }

    @Test
    fun namedSubscriptionsRoutesServeTheirOwnFixturesAndKeepWorkAndDetailRoutes() {
        val client = bundledDemoClient()
        val base = "https://archiveofourown.org/users/AO3_Reader/subscriptions"
        val parser = AO3AccountParser()
        val seriesHtml = html(client, "$base?type=series")
        val usersHtml = html(client, "$base/?type=users&page=2")
        val series = parser.parseNamedSubscriptions(seriesHtml,
            io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope.Series)
        assertEquals(listOf("My Series"), series.rows.map { it.name })
        assertEquals(listOf("/series/999"), series.rows.map { it.path })
        assertEquals(listOf("seriesauthor"), series.rows.single().creators.map { it.displayName })
        val users = parser.parseNamedSubscriptions(usersHtml,
            io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope.Users)
        assertEquals(listOf("someuser", "seriesauthor"), users.rows.map { it.name })
        assertTrue(users.rows.all { it.creators.isEmpty() })
        assertTrue(parser.parseSubscriptionsPage(seriesHtml, 1).works.isEmpty())
        assertTrue(parser.parseSubscriptionsPage(usersHtml, 1).works.isEmpty())
        assertEquals("ao3_subscriptions", name("$base?type=works&page=2"))
        assertEquals("ao3_demo_subscriptions_series", name("$base?page=3&type=series"))
        assertEquals("ao3_demo_subscriptions_users", name("$base?type=users"))
        assertEquals("ao3_demo_series", name("https://archiveofourown.org/series/999"))
        assertEquals("ao3_author_dashboard_demo", name("https://archiveofourown.org/users/someuser"))
        assertEquals("ao3_author_dashboard_demo", name("https://archiveofourown.org/users/seriesauthor"))
        html(client, "https://archiveofourown.org/series/999")
        html(client, "https://archiveofourown.org/users/someuser")
        html(client, "https://archiveofourown.org/users/seriesauthor")
    }

    private fun bundledDemoClient(): OkHttpClient {
        val fixtures = FixtureSource { fixture ->
            val candidates = listOf(
                File("src/debug/assets/fixtures/$fixture.html"),
                File("app/src/debug/assets/fixtures/$fixture.html"),
                File("android/app/src/debug/assets/fixtures/$fixture.html")
            )
            candidates.firstOrNull(File::isFile)?.readBytes()
        }
        return OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { fixtures }))
            .addInterceptor { error("Demo fixture lookup must never reach the network") }
            .build()
    }

    private fun html(client: OkHttpClient, url: String): String =
        client.newCall(get(url)).execute().use { response ->
            assertEquals(200, response.code)
            response.body.string()
        }

    private fun name(url: String): String? =
        DemoNetworkRoutes.fixtureName(url.toHttpUrl())

    private fun get(url: String): Request = Request.Builder().url(url).build()

    private fun sentinel(request: Request): Response = Response.Builder()
        .request(request)
        .protocol(Protocol.HTTP_1_1)
        .code(200)
        .message("OK")
        .body("sentinel".toResponseBody("text/plain".toMediaType()))
        .build()
}
