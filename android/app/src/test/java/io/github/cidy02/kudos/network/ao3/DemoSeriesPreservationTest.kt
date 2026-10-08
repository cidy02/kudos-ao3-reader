package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import java.io.File
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoSeriesPreservationTest {
    private val source = FixtureSource { name ->
        listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes()
    }
    private fun client() = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(
        isActive = { true }, fixtures = { source })).addInterceptor { throw AssertionError("Demo attempted a socket") }.build()

    @Test fun everySeriesAddressHasOneAnswerAcrossBrowserAndNativeReads() {
        val client = client()
        val parser = AO3SearchParser()
        for ((path, pages) in listOf("/series/999" to 1, "/series/1000" to 2, "/series/1000?page=2" to 2)) {
            val url = "https://archiveofourown.org$path".toHttpUrl()
            client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                assertEquals(200, response.code)
                val html = response.body.string()
                assertEquals(DemoNetwork.webFixture(url, source)!!.decodeToString(), html)
                assertEquals(pages, parser.parseSearchPage(html, if (path.contains("page=2")) 2 else 1).totalPages)
            }
        }
        val failed = "https://archiveofourown.org/series/1001".toHttpUrl()
        assertNull(DemoNetwork.webFixture(failed, source))
        client.newCall(Request.Builder().url(failed).build()).execute().use { assertEquals(404, it.code) }
    }

    @Test fun seriesEpubIsRealAndBookmarkValidationIsTerminalLocal() {
        val client = client()
        client.newCall(Request.Builder().url("https://archiveofourown.org/downloads/995111/work.epub").build()).execute().use {
            assertEquals(200, it.code)
            assertEquals("application/epub+zip", it.header("Content-Type"))
            val bytes = it.body.bytes()
            assertEquals(listOf(0x50.toByte(), 0x4b.toByte(), 0x03.toByte(), 0x04.toByte()), bytes.take(4))
        }
        val body = FormBody.Builder().add("bookmark[bookmarker_notes]", "n".repeat(5001)).build()
        client.newCall(Request.Builder().url("https://archiveofourown.org/bookmarks/2997787566").post(body).build())
            .execute().use {
                assertEquals(422, it.code)
                assertEquals("Notes must be less than 5000 characters long.", AO3WriteFormParser().writeErrorMessage(it.body.string()))
            }
    }
}
