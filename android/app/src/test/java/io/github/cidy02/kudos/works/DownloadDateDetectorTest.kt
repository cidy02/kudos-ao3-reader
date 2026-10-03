package io.github.cidy02.kudos.works

import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadDateDetectorTest {
    private val now = Instant.ofEpochSecond(2_000_000)

    @Test
    fun earliestFileDateWins() {
        val created = now.minusSeconds(3_600)
        val modified = now.minusSeconds(1_800)
        assertEquals(
            DownloadDateDetection(created, DownloadDateSource.File),
            DownloadDateDetector.detect(created, modified, now.minusSeconds(7_200), now)
        )
    }

    @Test
    fun freshCopyFallsBackToAo3Generation() {
        val generated = now.minusSeconds(86_400)
        assertEquals(
            DownloadDateDetection(generated, DownloadDateSource.Ao3Generated),
            DownloadDateDetector.detect(now.minusSeconds(60), null, generated, now)
        )
    }

    @Test
    fun fileDateBeforeGenerationIsDiscarded() {
        val generated = now.minusSeconds(3_600)
        assertEquals(
            DownloadDateDetection(generated, DownloadDateSource.Ao3Generated),
            DownloadDateDetector.detect(now.minusSeconds(7_200), null, generated, now)
        )
    }

    @Test
    fun noUsableFileDateOrTimestampUsesImportTime() {
        val expected = DownloadDateDetection(now, DownloadDateSource.ImportTime)
        assertEquals(expected, DownloadDateDetector.detect(now.minusSeconds(60), null, null, now))
        assertEquals(expected, DownloadDateDetector.detect(null, null, null, now))
    }

    @Test
    fun parsesCalibreTimestampWithMicrosecondsAndOffset() {
        val value = "2026-03-03T14:53:11.321543+00:00"
        assertEquals(Instant.parse("2026-03-03T14:53:11.321543Z"), DownloadDateDetector.parseEpubTimestamp(value))
        assertNull(DownloadDateDetector.parseEpubTimestamp(""))
    }

    @Test
    fun readsCalibreTimestampFromOpf() {
        val xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf">
              <metadata><meta name="calibre:timestamp" content="2026-03-03T14:53:11.321543+00:00"/></metadata>
            </package>
        """.trimIndent()
        val epub = ByteArrayOutputStream().use { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry("OEBPS/content.opf"))
                zip.write(xml.toByteArray())
                zip.closeEntry()
            }
            output.toByteArray()
        }

        assertEquals(
            Instant.parse("2026-03-03T14:53:11.321543Z"),
            DownloadDateDetector.epubGeneratedAt(epub)
        )
        assertTrue(epub.isNotEmpty())
    }
}
