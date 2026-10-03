package io.github.cidy02.kudos.works

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.util.zip.ZipInputStream
import org.jsoup.Jsoup
import org.jsoup.parser.Parser

enum class DownloadDateSource {
    File,
    Ao3Generated,
    ImportTime
}

data class DownloadDateDetection(
    val date: Instant,
    val source: DownloadDateSource
)

/** Chooses the best available download date without touching app or file state. */
object DownloadDateDetector {
    val FreshCopyWindow: Duration = Duration.ofMinutes(5)

    fun detect(
        fileCreated: Instant?,
        fileModified: Instant?,
        epubGeneratedAt: Instant?,
        now: Instant
    ): DownloadDateDetection {
        val fileDate = listOfNotNull(fileCreated, fileModified).minOrNull()
        if (fileDate != null &&
            fileDate < now.minus(FreshCopyWindow) &&
            (epubGeneratedAt == null || fileDate >= epubGeneratedAt)
        ) {
            return DownloadDateDetection(fileDate, DownloadDateSource.File)
        }
        if (epubGeneratedAt != null) {
            return DownloadDateDetection(epubGeneratedAt, DownloadDateSource.Ao3Generated)
        }
        return DownloadDateDetection(now, DownloadDateSource.ImportTime)
    }

    fun parseEpubTimestamp(value: String): Instant? = runCatching {
        OffsetDateTime.parse(value.trim()).toInstant()
    }.getOrNull()

    /** Reads only a bounded OPF entry from an untrusted EPUB. */
    fun epubGeneratedAt(bytes: ByteArray): Instant? = runCatching {
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (!entry.isDirectory && entry.name.endsWith(".opf", ignoreCase = true)) {
                    val opf = zip.readBounded(MAX_OPF_BYTES) ?: return@use null
                    val document = Jsoup.parse(opf.decodeToString(), "", Parser.xmlParser())
                    val value = document.getElementsByTag("meta")
                        .firstOrNull { it.attr("name").equals("calibre:timestamp", ignoreCase = true) }
                        ?.attr("content")
                        .orEmpty()
                    parseEpubTimestamp(value)?.let { return@use it }
                }
            }
            null
        }
    }.getOrNull()

    private fun ZipInputStream.readBounded(limit: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > limit) return null
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private const val MAX_OPF_BYTES = 2 * 1024 * 1024
}
