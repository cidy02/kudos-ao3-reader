package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.author.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DemoAuthorWorksSortTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }
    private val client = OkHttpClient.Builder()
        .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }))
        .addInterceptor { error("Demo author sorting must never reach a socket") }.build()

    @Test fun allNineOrdersBothDirectionsAndCompletionUseTheSameAnswerAsTheBrowser() {
        val ascending = listOf(
            listOf(1002L, 1001L, 1003L), // Creator: Anonymous, Avery Writes, orphan_account
            listOf(1002L, 1003L, 1001L), // Title
            listOf(1001L, 1003L, 1002L), // Posted: Jan, Feb, Mar
            listOf(1003L, 1002L, 1001L), // Updated: Jul 7, 8, 9
            listOf(1002L, 1001L, 1003L), // Words: 2k, 12,345, 30k
            listOf(1002L, 1001L, 1003L), // Hits: 300, 900, 1,200
            listOf(1003L, 1001L, 1002L), // Kudos: 40, 80, 120
            listOf(1002L, 1001L, 1003L), // Comments: 2, 8, 16
            listOf(1002L, 1003L, 1001L)  // Bookmarks: 10, 20, 30
        )
        for ((index, column) in AO3AuthorWorksSortColumn.entries.withIndex()) {
            for (direction in AO3AuthorWorksSortDirection.entries) for (completion in AO3AuthorWorksCompletion.entries) {
                val sort = AO3AuthorWorksSort(column, direction, completion)
                val url = AO3AuthorUrls.userWorksUrl("Avery_Archive", sort = sort)!!
                val body = client.newCall(Request.Builder().url(url).build()).execute().use {
                    assertEquals(200, it.code); it.body!!.string()
                }
                assertEquals(body, DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString())
                val expected = (if (direction == AO3AuthorWorksSortDirection.Ascending) ascending[index]
                    else ascending[index].reversed()).filter { id -> when (completion) {
                    AO3AuthorWorksCompletion.Any -> true
                    AO3AuthorWorksCompletion.Complete -> id != 1002L
                    AO3AuthorWorksCompletion.InProgress -> id == 1002L
                } }
                val works = AO3AuthorParser().parseWorksPage(body, 1).works
                assertEquals(expected, works.map { it.id })
                if (completion == AO3AuthorWorksCompletion.InProgress) assertEquals(false, works.single().isComplete)
            }
        }
    }

    @Test fun scopesPseudsLaterPagesAndOtherRoutesRemainLocalAndMissingAssetIsTerminal() {
        for (scope in AO3AuthorWorksScope.entries) {
            val url = AO3AuthorUrls.userWorksUrl("Avery_Archive", 2, "Avery Writes", scope,
                AO3AuthorWorksSort(AO3AuthorWorksSortColumn.Title, AO3AuthorWorksSortDirection.Ascending))!!
            val html = DemoNetwork.webFixture(url.toHttpUrl(), source)!!.decodeToString()
            assertEquals(2, AO3AuthorParser().parseWorksPage(html, 2).currentPage)
            assertEquals(if (scope == AO3AuthorWorksScope.Gifts) listOf(1001L, 1002L, 1003L) else listOf(1002L, 1003L, 1001L),
                AO3AuthorParser().parseWorksPage(html, 2).works.map { it.id })
        }
        assertEquals("ao3_demo_drafts_1", DemoNetworkRoutes.fixtureName("https://archiveofourown.org/users/AO3_Reader/works/drafts".toHttpUrl()))
        assertEquals("ao3_author_series", DemoNetworkRoutes.fixtureName("https://archiveofourown.org/users/Avery_Archive/series".toHttpUrl()))
        val empty = FixtureSource { null }
        val isolated = OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { empty }))
            .addInterceptor { error("Missing assets cannot escape demo isolation") }.build()
        val url = AO3AuthorUrls.userWorksUrl("Avery_Archive")!!
        isolated.newCall(Request.Builder().url(url).build()).execute().use { assertEquals(404, it.code) }
        assertNull(DemoNetwork.webFixture(url.toHttpUrl(), empty))
    }
}
