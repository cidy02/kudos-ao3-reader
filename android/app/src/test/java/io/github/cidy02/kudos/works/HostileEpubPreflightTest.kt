package io.github.cidy02.kudos.works

import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Ports MiniZipHostileTests through Android's EPUB preflight, including unreferenced entries. */
class HostileEpubPreflightTest {
    @Test
    fun validMinimalEpubStillOpens() {
        assertTrue(EpubImportMetadata.isReadablePackage(archive()))
        assertTrue(EpubImportMetadata.isReadablePackage(archive(Entry("OPS/"))))
    }

    @Test
    fun unsafeEntryNamesAreRejectedEvenWhenUnreferenced() {
        for (name in listOf("../../../outside.txt", "/etc/passwd", "..\\..\\outside.txt",
            "C:evil.txt", "../", "OPS//evil.txt", "", "bad\u0000name")) {
            assertFalse(name, EpubImportMetadata.isReadablePackage(archive(Entry(name))))
        }
    }

    @Test
    fun duplicateEntryNameIsRejected() {
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("dupe.txt", "first".toByteArray()), Entry("dupe.txt", "second".toByteArray())
        )))
        assertFalse(EpubImportMetadata.isReadablePackage(archive(Entry("OPS/package.opf"))))
    }

    @Test
    fun declaredOversizedUncompressedSizeIsRejectedBeforeAllocation() {
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("bomb.bin", method = 8, compressed = 4, expanded = 1_000_000_000)
        )))
    }

    @Test
    fun rejectDeflateWithZeroCompressedSize() {
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("bomb.bin", method = 8, compressed = 0, expanded = 2_000_000)
        )))
    }

    @Test
    fun implausibleCompressionRatioIsRejected() {
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("ratio.bin", method = 8, compressed = 4, expanded = 50_000)
        )))
    }

    @Test
    fun excessiveCumulativeUncompressedSizeIsRejected() {
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            *List(3) { Entry("chunk$it.bin", method = 8, compressed = 200_000, expanded = 180_000_000) }
                .toTypedArray()
        )))
    }

    @Test
    fun epubLimitsMatchIosAtTheirBoundaries() {
        // The extra payloads are never inflated; the declared central-directory sizes are the check.
        assertTrue(EpubImportMetadata.isReadablePackage(archive(
            Entry("large.bin", method = 8, compressed = 200_000, expanded = 200_000_000)
        )))
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("large.bin", method = 8, compressed = 200_000, expanded = 200_000_001)
        )))
        assertTrue(EpubImportMetadata.isReadablePackage(archive(
            Entry("ratio.bin", method = 8, compressed = 10, expanded = 11_000)
        )))
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            Entry("ratio.bin", method = 8, compressed = 10, expanded = 11_010)
        )))
        val baseSize = base.sumOf { it.expanded }
        val chunks = listOf(
            Entry("a", method = 8, compressed = 200_000, expanded = 200_000_000),
            Entry("b", method = 8, compressed = 200_000, expanded = 200_000_000),
            Entry("c", method = 8, compressed = 100_000, expanded = 100_000_000 - baseSize)
        )
        assertTrue(EpubImportMetadata.isReadablePackage(archive(*chunks.toTypedArray())))
        assertFalse(EpubImportMetadata.isReadablePackage(archive(
            *(chunks.dropLast(1) + chunks.last().copy(expanded = chunks.last().expanded + 1)).toTypedArray()
        )))
        val emptyEntries = List(10_000 - base.size) { Entry("empty$it") }
        assertTrue(EpubImportMetadata.isReadablePackage(archive(*emptyEntries.toTypedArray())))
        assertFalse(EpubImportMetadata.isReadablePackage(archive(*(emptyEntries + Entry("one-too-many")).toTypedArray())))
    }

    private data class Entry(
        val name: String,
        val payload: ByteArray = byteArrayOf(),
        val method: Int = 0,
        val compressed: Int = payload.size,
        val expanded: Int = payload.size
    )

    private val base = listOf(
        Entry("META-INF/container.xml", """<container><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>""".toByteArray()),
        Entry("OPS/package.opf", ("""<package><manifest><item id="c" href="c.xhtml"/></manifest>""" +
            """<spine><itemref idref="c"/></spine></package>""").toByteArray()),
        Entry("OPS/c.xhtml", "<html><body>Text</body></html>".toByteArray())
    )

    // Hand-assembled like iOS HostileZipFixture: patch declared sizes without allocating a bomb.
    private fun archive(vararg extra: Entry): ByteArray {
        val bytes = ByteArrayOutputStream()
        fun u16(value: Int) { repeat(2) { bytes.write(value ushr (it * 8) and 0xff) } }
        fun u32(value: Int) { repeat(4) { bytes.write(value ushr (it * 8) and 0xff) } }
        val entries = base + extra
        val offsets = entries.map { entry ->
            val offset = bytes.size()
            val name = entry.name.toByteArray()
            val crc = CRC32().apply { update(entry.payload) }.value.toInt()
            u32(0x04034b50); u16(20); u16(0); u16(entry.method); u16(0); u16(0)
            u32(crc); u32(entry.compressed); u32(entry.expanded); u16(name.size); u16(0)
            bytes.write(name); bytes.write(entry.payload)
            offset
        }
        val directory = bytes.size()
        entries.forEachIndexed { index, entry ->
            val name = entry.name.toByteArray()
            val crc = CRC32().apply { update(entry.payload) }.value.toInt()
            u32(0x02014b50); u16(20); u16(20); u16(0); u16(entry.method); u16(0); u16(0)
            u32(crc); u32(entry.compressed); u32(entry.expanded); u16(name.size)
            u16(0); u16(0); u16(0); u16(0); u32(0); u32(offsets[index]); bytes.write(name)
        }
        val directorySize = bytes.size() - directory
        u32(0x06054b50); u16(0); u16(0); u16(entries.size); u16(entries.size)
        u32(directorySize); u32(directory); u16(0)
        return bytes.toByteArray()
    }
}
