package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.works.converters.AO3HtmlDownloadConverter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import java.util.concurrent.TimeUnit

/**
 * Hands back a work as an EPUB, whichever format AO3 is serving.
 *
 * AO3 normally offers EPUB. When it does not (after the November 2026 outage only
 * HTML came back), the work's own download menu says what it does offer, and the
 * HTML download is rebuilt into the EPUB AO3 would have made from it — so nothing
 * past this class learns there was a difference.
 */
class AO3EpubDownloader(
    private val client: AO3Client = OkHttpAO3Client(),
    private val urlBuilder: AO3DownloadUrlBuilder = AO3DownloadUrlBuilder(),
    private val fetchImage: suspend (String) -> ByteArray? = ::fetchRemoteImage,
    private val now: () -> Long = System::currentTimeMillis
) {
    /** While this is in the future, AO3 has said EPUB is off the menu: go straight to HTML. */
    @Volatile
    private var htmlOnlyUntil = 0L

    suspend fun download(workId: Long, onProgress: (Double) -> Unit = {}): AO3Result<ByteArray> {
        if (now() < htmlOnlyUntil) return downloadUrl(urlBuilder.htmlDownloadUrl(workId), onProgress)
        val epub = downloadUrl(urlBuilder.epubDownloadUrl(workId), onProgress)
        if (epub !is AO3Result.Failure || !epub.error.mayMeanEpubIsNotOffered()) return epub

        // EPUB first costs nothing while AO3 is whole; only a refusal is worth a
        // second request, to read what the work's download menu offers instead.
        val page = client.get(urlBuilder.workMetadataUrl(workId)) as? AO3Result.Success ?: return epub
        val offered = offeredFormats(page.value.body)
        return when {
            // No menu on this page (a work restricted to signed-in readers shows a
            // guest none): HTML may still be there, and if not the first answer stands.
            offered == null ->
                downloadUrl(urlBuilder.htmlDownloadUrl(workId), onProgress) as? AO3Result.Success ?: epub
            "epub" in offered -> epub
            "html" in offered -> {
                // The list is the site's, not the work's, so it holds for the next download too.
                htmlOnlyUntil = now() + HTML_ONLY_MEMORY_MILLIS
                downloadUrl(urlBuilder.htmlDownloadUrl(workId), onProgress)
            }
            else -> AO3Result.Failure(AO3Error.Validation("AO3 isn't offering EPUB or HTML downloads right now."))
        }
    }

    /** One AO3 download link, EPUB or HTML; either way the result is an EPUB. */
    suspend fun downloadUrl(url: String, onProgress: (Double) -> Unit = {}): AO3Result<ByteArray> {
        if (!isEpubDownload(url)) return AO3Result.Failure(AO3Error.Validation("Not an AO3 EPUB download."))
        return when (val result = client.getBytesWithProgress(url, onProgress)) {
            is AO3Result.Failure -> result
            is AO3Result.Success ->
                if (isHtmlPath(url)) {
                    withContext(Dispatchers.Default) { AO3HtmlDownloadConverter.toEpub(result.value.body, fetchImage) }
                        ?.let { AO3Result.Success(it) }
                        ?: AO3Result.Failure(AO3Error.Parse("AO3 returned a page instead of the work's HTML download."))
                } else {
                    validate(result.value.body, result.value.header("Content-Type"))
                }
        }
    }

    companion object {
        /** Long enough to spare a series the doomed request per work, short enough to notice EPUB's return. */
        private const val HTML_ONLY_MEMORY_MILLIS = 15 * 60 * 1000L

        /**
         * A download this class can turn into a book: AO3's EPUB, or its HTML. The
         * name predates HTML; the result is an EPUB either way.
         */
        fun isEpubDownload(url: String): Boolean {
            val parsed = url.toHttpUrlOrNull() ?: return false
            val file = parsed.pathSegments.lastOrNull().orEmpty()
            return AO3BrowseUrls.isAo3Url(url) && parsed.encodedPath.startsWith("/downloads/") &&
                (file.endsWith(".epub", ignoreCase = true) || file.endsWith(".html", ignoreCase = true))
        }

        private fun isHtmlPath(url: String): Boolean =
            url.toHttpUrlOrNull()?.pathSegments?.lastOrNull()?.endsWith(".html", ignoreCase = true) == true

        /**
         * The formats a work page's download menu offers, lower-case ("epub", "html"…),
         * or null when the page has no menu.
         *
         * otwarchive 452391b648f2, `app/views/works/_work_header_navigation.html.erb`:
         * `li.download` holds one link per `ArchiveConfig.DOWNLOAD_FORMATS` entry, each
         * to `/downloads/<id>/<name>.<format>?updated_at=…` (`download_url_for_work`).
         */
        fun offeredFormats(workPageHtml: String): Set<String>? =
            Jsoup.parse(workPageHtml).select("li.download a[href*=/downloads/]")
                .map { it.attr("href").substringBefore('?').substringAfterLast('.', "").lowercase() }
                .filter(String::isNotEmpty)
                .toSet()
                .takeIf { it.isNotEmpty() }
    }

    private fun validate(bytes: ByteArray, contentType: String?): AO3Result<ByteArray> {
        if (bytes.isEmpty()) {
            return AO3Result.Failure(AO3Error.Validation("AO3 returned an empty EPUB download."))
        }
        if (contentType?.contains("html", ignoreCase = true) == true || bytes.looksLikeHtml()) {
            return AO3Result.Failure(AO3Error.Parse("AO3 returned an HTML page instead of an EPUB."))
        }
        if (!bytes.hasZipSignature()) {
            return AO3Result.Failure(AO3Error.Validation("AO3 EPUB download did not look like a ZIP/EPUB file."))
        }
        return AO3Result.Success(bytes)
    }
}

/**
 * AO3 answered, and the answer was not an EPUB: a page in its place (what otwarchive's
 * `DownloadsController#show` sends when a format cannot be made), or the route
 * itself refused. Being unreachable, blocked (403), overloaded (5xx) or told to slow
 * down is not that — asking again in another format would only add load.
 */
private fun AO3Error.mayMeanEpubIsNotOffered(): Boolean = when (this) {
    AO3Error.NotFound, AO3Error.BadRequest, is AO3Error.Http, is AO3Error.Parse, is AO3Error.Validation -> true
    else -> false
}

private const val MAX_IMAGE_BYTES = 8L * 1024 * 1024

/** Its own client: an image host is not AO3, and gets none of AO3's cookies. */
private val imageClient by lazy { OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build() }

private suspend fun fetchRemoteImage(url: String): ByteArray? = withContext(Dispatchers.IO) {
    runCatching {
        imageClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
            val source = response.body.source()
            // Reads at most one byte past the limit, so an endless response cannot fill memory.
            if (!response.isSuccessful || source.request(MAX_IMAGE_BYTES + 1)) null else source.readByteArray()
        }
    }.getOrNull()
}

private fun ByteArray.hasZipSignature(): Boolean {
    return size >= 4 &&
        this[0] == 0x50.toByte() &&
        this[1] == 0x4B.toByte() &&
        (this[2] == 0x03.toByte() || this[2] == 0x05.toByte() || this[2] == 0x07.toByte()) &&
        (this[3] == 0x04.toByte() || this[3] == 0x06.toByte() || this[3] == 0x08.toByte())
}

private fun ByteArray.looksLikeHtml(): Boolean {
    val preview = decodeToString(endIndex = minOf(size, 512)).trimStart()
    return preview.startsWith("<!doctype", ignoreCase = true) ||
        preview.startsWith("<html", ignoreCase = true)
}
