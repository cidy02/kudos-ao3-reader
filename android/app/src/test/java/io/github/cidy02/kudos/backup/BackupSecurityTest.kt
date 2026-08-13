package io.github.cidy02.kudos.backup

import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class BackupSecurityTest {
    private fun rawZip(entries: List<Pair<String, ByteArray>>): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (name, bytes) ->
                val entry = ZipEntry(name).apply { time = 0L }
                zip.putNextEntry(entry)
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return output.toByteArray()
    }

    private val VALID_MANIFEST = """
        {
            "version": 8,
            "exportedAt": "2026-06-26T12:00:00Z",
            "exportedBy": { "platform": "android", "version": "1.0.0" },
            "works": [],
            "collections": [],
            "savedSearches": [],
            "tombstones": [],
            "readingQueues": [],
            "readingQueueMemberships": [],
            "readingAnnotations": [],
            "fonts": []
        }
    """.trimIndent().toByteArray()

    @Test
    fun testM21_InvalidFontIsRejected() {
        val zipBytes = rawZip(listOf(
            "manifest.json" to VALID_MANIFEST,
            "Fonts/malicious.ttf" to "This is not a font".toByteArray()
        ))
        assertThrows(BackupError.InvalidPackage::class.java) {
            BackupImporter.importV2Zip(zipBytes)
        }
    }

    @Test
    fun testM21_HugeFontIsRejected() {
        val hugeBytes = ByteArray((BackupLimits.MAX_FONT_ENTRY_BYTES + 1024).toInt()) { 0x00.toByte() }
        val zipBytes = rawZip(listOf(
            "manifest.json" to VALID_MANIFEST,
            "Fonts/huge.ttf" to hugeBytes
        ))
        assertThrows(BackupError.EntryTooLarge::class.java) {
            BackupImporter.importV2Zip(zipBytes)
        }
    }
    
    @Test
    fun testM21_UnsupportedFontExtensionRejected() {
        val validFontMagic = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        val zipBytes = rawZip(listOf(
            "manifest.json" to VALID_MANIFEST,
            "Fonts/malicious.html" to validFontMagic
        ))
        assertThrows(BackupError.InvalidPackage::class.java) {
            BackupImporter.importV2Zip(zipBytes)
        }
    }
}
