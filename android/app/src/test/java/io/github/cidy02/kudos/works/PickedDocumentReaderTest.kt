package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.files.ImportedFileFormat
import io.github.cidy02.kudos.works.converters.ArchiveWorkConverter
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PickedDocumentReaderTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun unsupportedBinaryReadsOnlyPrefixAndKnownOversizeReadsNothing() {
        val binary = CountingStream(ByteArray(4096), PickedDocumentReader.MAX_BYTES * 8)
        assertThrows(IllegalArgumentException::class.java) {
            PickedDocumentReader.inspect(binary, null, "movie.mp4", temporary.root)
        }
        assertEquals(4096L, binary.consumed)
        val oversized = CountingStream("hello".toByteArray(), PickedDocumentReader.MAX_BYTES + 1)
        assertThrows(IllegalArgumentException::class.java) {
            PickedDocumentReader.inspect(oversized, oversized.length, "story.txt", temporary.root)
        }
        assertEquals(0L, oversized.consumed)
        assertTrue(temporary.root.listFiles()!!.isEmpty())
    }

    @Test fun unknownOrUnderreportedSizesAreBoundedDuringInspectionAndConfirmation() {
        for (declaredSize in listOf(null, 1L)) {
            val input = CountingStream("<html>story".toByteArray(), PickedDocumentReader.MAX_BYTES * 2)
            assertThrows(IllegalArgumentException::class.java) {
                PickedDocumentReader.inspect(input, declaredSize, "story.html", temporary.root)
            }
            assertEquals(PickedDocumentReader.MAX_BYTES + 1, input.consumed)
            val confirmed = CountingStream("text".toByteArray(), PickedDocumentReader.MAX_BYTES + 1)
            assertThrows(IllegalArgumentException::class.java) {
                PickedDocumentReader.readBytes(confirmed, declaredSize)
            }
            assertEquals(PickedDocumentReader.MAX_BYTES + 1, confirmed.consumed)
        }
    }

    @Test fun rtfIsRefusedBeforeReadingTheRestAndOfficeZipsGiveSpecificGuidance() {
        val rtf = CountingStream("{\\rtf1 control words".toByteArray(), PickedDocumentReader.MAX_BYTES)
        val rejection = assertThrows(IllegalArgumentException::class.java) {
            PickedDocumentReader.inspect(rtf, null, "story.rtf", temporary.root)
        }
        assertTrue(rejection.message!!.startsWith("RTF import is coming"))
        assertEquals(4096L, rtf.consumed)
        val docx = zip("word/document.xml" to "<document/>".toByteArray())
        val office = assertThrows(IllegalArgumentException::class.java) {
            PickedDocumentReader.inspect(docx.inputStream(), docx.size.toLong(), "renamed.zip", temporary.root)
        }
        assertTrue(office.message!!.startsWith("Word document import is coming"))
        assertTrue(temporary.root.listFiles()!!.isEmpty())
    }

    @Test fun backupManifestWinsOverNestedEpubsAndNamesAndVersions() {
        val epub = EpubBuilder.buildEpub("Story", listOf(EpubBuilder.Chapter("One", "<p>Text</p>")))
        for (version in listOf(8, 9)) {
            val backup = zip("Works/00000000-0000-0000-0000-000000000001.epub" to epub,
                "manifest.json" to "{\"version\":$version,\"works\":[]}".toByteArray())
            for (name in listOf("library.kudosbackup", "renamed.zip", "renamed.epub")) {
                val result = PickedDocumentReader.inspect(backup.inputStream(), backup.size.toLong(), name, temporary.root)
                assertTrue(result.isBackup)
                assertNull(ArchiveWorkConverter.convert("Library", backup))
            }
        }
        val ordinary = zip("chapter.txt" to "A readable chapter.".toByteArray())
        assertFalse(PickedDocumentReader.inspect(ordinary.inputStream(), null, "not-a-backup.kudosbackup", temporary.root).isBackup)
        assertNotNull(ArchiveWorkConverter.convert("Story", ordinary))
        assertTrue(temporary.root.listFiles()!!.isEmpty())
    }

    @Test fun renamedEpubRetainsGeneratedDateWithoutReadingChapterPayloads() {
        val epub = zip("META-INF/container.xml" to "container".toByteArray(),
            "content.opf" to "<package><metadata><meta name=\"calibre:timestamp\" content=\"2024-01-02T03:04:05Z\"/></metadata></package>".toByteArray())
        val inspected = PickedDocumentReader.inspect(epub.inputStream(), null, "renamed.zip", temporary.root)
        assertEquals(ImportedFileFormat.EPUB, inspected.format)
        assertEquals(java.time.Instant.parse("2024-01-02T03:04:05Z"), inspected.generatedAt)
        assertFalse(inspected.isBackup)
        assertTrue(temporary.root.listFiles()!!.isEmpty())
    }

    private fun zip(vararg members: Pair<String, ByteArray>): ByteArray = ByteArrayOutputStream().also { out ->
        ZipOutputStream(out).use { zip ->
            members.forEach { (name, body) ->
                zip.putNextEntry(ZipEntry(name))
                zip.write(body)
                zip.closeEntry()
            }
        }
    }.toByteArray()

    /** Generates large input without allocating it; fails if the reader over-consumes. */
    private class CountingStream(private val prefix: ByteArray, val length: Long) : InputStream() {
        var consumed = 0L
        override fun read(): Int {
            if (consumed == length) return -1
            val value = if (consumed < prefix.size) prefix[consumed.toInt()].toInt() and 255 else 'a'.code
            consumed++
            return value
        }
        override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
            if (consumed == length) return -1
            val read = minOf(count.toLong(), length - consumed).toInt()
            java.util.Arrays.fill(buffer, offset, offset + read, 'a'.code.toByte())
            if (consumed < prefix.size) {
                val copied = minOf(read, prefix.size - consumed.toInt())
                prefix.copyInto(buffer, offset, consumed.toInt(), consumed.toInt() + copied)
            }
            consumed += read
            return read
        }
    }
}
