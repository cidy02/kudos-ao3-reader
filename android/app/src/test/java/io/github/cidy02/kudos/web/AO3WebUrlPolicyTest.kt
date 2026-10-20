package io.github.cidy02.kudos.web

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import kotlinx.coroutines.runBlocking

class AO3WebUrlPolicyTest {
    @Test fun onlyMainFrameWebLinksLeaveTheAppAndDemoNeverLaunchesABrowser() {
        val ao3 = "https://archiveofourown.org/works/123"
        val outside = "https://example.com/video"
        assertEquals(WebNavDecision.External(outside), AO3WebUrlPolicy.navigationVerdict(outside, true, false))
        assertEquals(WebNavDecision.Allow, AO3WebUrlPolicy.navigationVerdict(outside, false, false))
        assertEquals(WebNavDecision.Allow, AO3WebUrlPolicy.navigationVerdict("about:blank", false, false))
        for (main in listOf(false, true)) {
            assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.navigationVerdict(outside, main, true))
            // Android's demo loads AO3 fixtures locally through shouldInterceptRequest.
            assertEquals(WebNavDecision.Allow, AO3WebUrlPolicy.navigationVerdict(ao3, main, true))
            assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.navigationVerdict("intent://app", main, false))
        }
        for (url in listOf(ao3, outside, "http://archiveofourown.org/")) {
            assertFalse(AO3WebUrlPolicy.mayOpenExternal(url, isDemo = true))
            assertTrue(AO3WebUrlPolicy.mayOpenExternal(url, isDemo = false))
        }
        assertFalse(AO3WebUrlPolicy.mayOpenExternal("javascript:alert(1)", false))
    }

    @Test fun addressAcceptsUrlsAndEncodesSearchTerms() {
        assertEquals(null, AO3WebUrlPolicy.addressUrl("  "))
        assertEquals("https://archiveofourown.org/media", AO3WebUrlPolicy.addressUrl(" https://archiveofourown.org/media "))
        val parsed = AO3WebUrlPolicy.addressUrl("cats & dogs + space")!!.toHttpUrl()
        assertEquals("/works/search", parsed.encodedPath)
        assertEquals("cats & dogs + space", parsed.queryParameter("work_search[query]"))
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify(AO3WebUrlPolicy.addressUrl("javascript:alert(1)")!!))
    }

    @Test fun downloadAllowsOnlyAo3EpubLinks() {
        val downloader = io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
        assertTrue(downloader.isEpubDownload("https://archiveofourown.org/downloads/123/My%20Book.epub?updated=1"))
        listOf("https://example.com/downloads/123/book.epub", "http://archiveofourown.org/downloads/123/book.epub",
            "https://archiveofourown.org.evil.com/downloads/123/book.epub", "https://archiveofourown.org/works/123",
            "https://archiveofourown.org/downloads/123/book.pdf").forEach {
            assertFalse(downloader.isEpubDownload(it))
        }
    }

    @Test fun websiteDownloadRejectsUntrustedBeforeClientAndFetchesChosenUrlOnce() = runBlocking {
        val urls = mutableListOf<String>()
        var html = false
        val downloader = AO3EpubDownloader(object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("No metadata or HTML read is needed")
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                urls += url
                return AO3Result.Success(AO3BinaryResponse(url, 200,
                    mapOf("Content-Type" to listOf(if (html) "text/html" else "application/epub+zip")),
                    if (html) "<html>Not an EPUB</html>".encodeToByteArray() else byteArrayOf(0x50, 0x4B, 0x03, 0x04)))
            }
        })
        org.junit.Assert.assertTrue(downloader.downloadUrl("https://evil.example/downloads/123/book.epub") is AO3Result.Failure)
        assertTrue(urls.isEmpty())
        val url = "https://archiveofourown.org/downloads/123/Chosen%20Book.epub?updated=42"
        assertTrue(downloader.downloadUrl(url) is AO3Result.Success)
        assertEquals(listOf(url), urls)
        html = true
        assertTrue(downloader.downloadUrl(url) is AO3Result.Failure)
        assertEquals(2, urls.size)
    }

    @Test
    fun ao3HttpsStaysInApp() {
        assertEquals(WebNavDecision.Allow, AO3WebUrlPolicy.classify("https://archiveofourown.org/media"))
        assertTrue(AO3WebUrlPolicy.isAllowedInApp("https://archiveofourown.org/tags/Naruto/works"))
    }

    @Test
    fun nonAo3WebUrlsAreExternalized() {
        val decision = AO3WebUrlPolicy.classify("https://example.com/page")
        assertTrue(decision is WebNavDecision.External)
        assertEquals("https://example.com/page", (decision as WebNavDecision.External).url)
        assertFalse(AO3WebUrlPolicy.isAllowedInApp("https://example.com/page"))
    }

    @Test
    fun nonWebSchemesAreBlocked() {
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("javascript:alert(1)"))
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("intent://evil#Intent;end"))
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("file:///etc/passwd"))
    }

    @Test
    fun plainHttpAo3IsExternalizedNotInApp() {
        // http (not https) AO3 is not treated as in-app-allowed; it is externalized.
        assertTrue(AO3WebUrlPolicy.classify("http://archiveofourown.org/media") is WebNavDecision.External)
    }
}
