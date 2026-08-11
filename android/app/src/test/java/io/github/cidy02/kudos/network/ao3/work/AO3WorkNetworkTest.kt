package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3BinaryResponse
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3DownloadUrlBuilderTest {
    @Test
    fun buildsAppleCompatibleDownloadAndMetadataUrls() {
        val builder = AO3DownloadUrlBuilder()

        assertEquals(
            "https://archiveofourown.org/downloads/12345/work.epub",
            builder.epubDownloadUrl(12345)
        )
        assertEquals(
            "https://archiveofourown.org/works/12345?view_adult=true",
            builder.workMetadataUrl(12345)
        )
    }
}

class AO3EpubDownloaderTest {
    @Test
    fun acceptsNonEmptyZipEpubBytes() = runTest {
        val bytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2)
        val downloader = AO3EpubDownloader(
            client = FakeAO3Client(
                bytes = AO3Result.Success(
                    AO3BinaryResponse(
                        url = "https://archiveofourown.org/downloads/1/work.epub",
                        statusCode = 200,
                        headers = mapOf("Content-Type" to listOf("application/epub+zip")),
                        body = bytes
                    )
                )
            )
        )

        val result = downloader.download(1)

        assertEquals(bytes.toList(), (result as AO3Result.Success).value.toList())
    }

    @Test
    fun rejectsHtmlErrorPageAsEpub() = runTest {
        val downloader = AO3EpubDownloader(
            client = FakeAO3Client(
                bytes = AO3Result.Success(
                    AO3BinaryResponse(
                        url = "https://archiveofourown.org/downloads/1/work.epub",
                        statusCode = 200,
                        headers = mapOf("Content-Type" to listOf("text/html")),
                        body = "<html>not an epub</html>".toByteArray()
                    )
                )
            )
        )

        val result = downloader.download(1)

        assertTrue((result as AO3Result.Failure).error is AO3Error.Parse)
    }
}

class AO3WorkMetadataParserTest {
    @Test
    fun parsesCanonicalWorkTagsAndStats() {
        val metadata = AO3WorkMetadataParser().parse(workHtml)

        assertEquals(listOf("Naruto"), metadata.fandoms)
        assertEquals(listOf("Naruto/Hinata"), metadata.relationships)
        assertEquals(listOf("Hinata Hyuuga", "Naruto Uzumaki"), metadata.characters)
        assertEquals(listOf("Fluff"), metadata.freeforms)
        assertEquals(listOf("No Archive Warnings Apply"), metadata.warnings)
        assertEquals(listOf("Gen"), metadata.categories)
        assertEquals("English", metadata.language)
        assertEquals(12345, metadata.words)
        assertEquals("5/10", metadata.chapters)
        assertEquals(890, metadata.kudos)
        assertEquals(76, metadata.comments)
        assertEquals(54321, metadata.hits)
        assertFalse(metadata.isEmpty)
    }
}

class AO3WorkMetadataFetchPartialFailureTest {
    @Test
    fun repositorySurfacesFetchFailureForCallerFallback() = runTest {
        val repository = AO3WorkMetadataRepository(
            client = FakeAO3Client(text = AO3Result.Failure(AO3Error.NotFound))
        )

        val result = repository.fetch(123)

        assertEquals(AO3Error.NotFound, (result as AO3Result.Failure).error)
    }
}

private class FakeAO3Client(
    private val text: AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.NotFound),
    private val bytes: AO3Result<AO3BinaryResponse> = AO3Result.Failure(AO3Error.NotFound)
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = text

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> = bytes
}

private val workHtml = """
    <html><body>
    <dl class="work meta group">
      <dd class="fandom tags"><ul><li><a class="tag">Naruto</a></li></ul></dd>
      <dd class="relationship tags"><ul><li><a class="tag">Naruto/Hinata</a></li></ul></dd>
      <dd class="character tags"><ul>
        <li><a class="tag">Hinata Hyuuga</a></li>
        <li><a class="tag">Naruto Uzumaki</a></li>
      </ul></dd>
      <dd class="freeform tags"><ul><li><a class="tag">Fluff</a></li></ul></dd>
      <dd class="warning tags"><ul><li><a class="tag">No Archive Warnings Apply</a></li></ul></dd>
      <dd class="category tags"><ul><li><a class="tag">Gen</a></li></ul></dd>
      <dd class="language">English</dd>
      <dl class="stats">
        <dd class="words">12,345</dd>
        <dd class="chapters">5/10</dd>
        <dd class="kudos">890</dd>
        <dd class="comments">76</dd>
        <dd class="hits">54,321</dd>
      </dl>
    </dl>
    </body></html>
""".trimIndent()
