package io.github.cidy02.kudos.backup

import org.junit.Assert.assertThrows
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.nio.file.Path
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

    private fun rawDirectory(entries: List<Pair<String, ByteArray>>): Path {
        val root = Files.createTempDirectory("backup")
        entries.forEach { (name, bytes) ->
            val path = root.resolve(name)
            Files.createDirectories(path.parent)
            Files.write(path, bytes)
        }
        return root
    }

    private val VALID_MANIFEST = """
        {
            "version": 8,
            "exportedAt": "2026-06-26T12:00:00Z",
            "exportedBy": { "platform": "android", "appVersion": "1.0.0" },
            "works": [],
            "collections": [],
            "savedSearches": [],
            "tombstones": [],
            "readingQueues": [],
            "readingQueueMemberships": [],
            "annotations": [],
            "fonts": []
        }
    """.trimIndent().toByteArray()

    private fun manifestWithFonts(vararg fileNames: String): ByteArray {
        val fontsJson = fileNames.joinToString(", ") { fileName ->
            """{ "name": "Test Font", "fileName": "$fileName", "dateAdded": "2026-06-26T12:00:00Z" }"""
        }
        return """
            {
                "version": 8,
                "exportedAt": "2026-06-26T12:00:00Z",
                "exportedBy": { "platform": "android", "appVersion": "1.0.0" },
                "works": [],
                "collections": [],
                "savedSearches": [],
                "tombstones": [],
                "readingQueues": [],
                "readingQueueMemberships": [],
                "annotations": [],
                "fonts": [$fontsJson]
            }
        """.trimIndent().toByteArray()
    }

    @Test
    fun testFixture_ManifestAloneImportsCleanly() {
        val zipBytes = rawZip(listOf("manifest.json" to VALID_MANIFEST))
        BackupImporter.importV2Zip(zipBytes)
        
        val dir = rawDirectory(listOf("manifest.json" to VALID_MANIFEST))
        BackupImporter.importV1Directory(dir)
    }

    @Test
    fun testM21_ValidFontIsAccepted() {
        val validFontMagic = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        
        val zipBytes = rawZip(listOf(
            "manifest.json" to VALID_MANIFEST,
            "Fonts/good.ttf" to validFontMagic
        ))
        val packageZip = BackupImporter.importV2Zip(zipBytes)
        assertTrue(packageZip.fontFilesByFileName.containsKey("good.ttf"))
        assertEquals(validFontMagic.toList(), packageZip.fontFilesByFileName["good.ttf"]?.toList())

        val dir = rawDirectory(listOf(
            "manifest.json" to manifestWithFonts("good.ttf"),
            "Fonts/good.ttf" to validFontMagic
        ))
        val packageDir = BackupImporter.importV1Directory(dir)
        assertTrue(packageDir.fontFilesByFileName.containsKey("good.ttf"))
        assertEquals(validFontMagic.toList(), packageDir.fontFilesByFileName["good.ttf"]?.toList())
    }

    @Test
    fun testM21_InvalidFontIsRejected() {
        val badBytes = "This is not a font".toByteArray()
        
        val exZip = assertThrows(BackupError.InvalidPackage::class.java) {
            val zipBytes = rawZip(listOf(
                "manifest.json" to VALID_MANIFEST,
                "Fonts/malicious.ttf" to badBytes
            ))
            BackupImporter.importV2Zip(zipBytes)
        }
        assertEquals("Invalid font file", exZip.message)

        val exDir = assertThrows(BackupError.InvalidPackage::class.java) {
            val dir = rawDirectory(listOf(
                "manifest.json" to manifestWithFonts("malicious.ttf"),
                "Fonts/malicious.ttf" to badBytes
            ))
            BackupImporter.importV1Directory(dir)
        }
        assertEquals("Invalid font file", exDir.message)
    }

    @Test
    fun testM21_HugeFontIsRejected() {
        val hugeBytes = ByteArray((BackupLimits.MAX_FONT_ENTRY_BYTES + 1024).toInt()) { 0x00.toByte() }
        
        val exZip = assertThrows(BackupError.EntryTooLarge::class.java) {
            val zipBytes = rawZip(listOf(
                "manifest.json" to VALID_MANIFEST,
                "Fonts/huge.ttf" to hugeBytes
            ))
            BackupImporter.importV2Zip(zipBytes)
        }
        assertEquals("Fonts/huge.ttf", exZip.path)

        val exDir = assertThrows(BackupError.EntryTooLarge::class.java) {
            val dir = rawDirectory(listOf(
                "manifest.json" to manifestWithFonts("huge.ttf"),
                "Fonts/huge.ttf" to hugeBytes
            ))
            BackupImporter.importV1Directory(dir)
        }
        assertEquals("Fonts/huge.ttf", exDir.path)
    }
    
    @Test
    fun testM21_UnsupportedFontExtensionRejected() {
        val validFontMagic = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        
        val exZip = assertThrows(BackupError.InvalidPackage::class.java) {
            val zipBytes = rawZip(listOf(
                "manifest.json" to VALID_MANIFEST,
                "Fonts/malicious.html" to validFontMagic
            ))
            BackupImporter.importV2Zip(zipBytes)
        }
        assertEquals("Unsupported font extension", exZip.message)

        val exDir = assertThrows(BackupError.InvalidPackage::class.java) {
            val dir = rawDirectory(listOf(
                "manifest.json" to manifestWithFonts("malicious.html"),
                "Fonts/malicious.html" to validFontMagic
            ))
            BackupImporter.importV1Directory(dir)
        }
        assertEquals("Unsupported font extension", exDir.message)
    }

    @Test
    fun testM21_TotalFontLimitRejected() {
        val validFontMagic = byteArrayOf(0x00, 0x01, 0x00, 0x00)
        val chunk = ByteArray((BackupLimits.MAX_FONT_ENTRY_BYTES).toInt()) { 0x00.toByte() }
        System.arraycopy(validFontMagic, 0, chunk, 0, 4)
        
        // We need >32MB total. 9 fonts of 4MB = 36MB.
        val fonts = (1..9).map { "Fonts/font${it}.ttf" to chunk }
        val manifestFonts = (1..9).map { "font${it}.ttf" }.toTypedArray()
        
        val exZip = assertThrows(BackupError.InvalidPackage::class.java) {
            val entries = mutableListOf("manifest.json" to VALID_MANIFEST)
            entries.addAll(fonts)
            BackupImporter.importV2Zip(rawZip(entries))
        }
        assertEquals("Total font size exceeds limit", exZip.message)

        val exDir = assertThrows(BackupError.InvalidPackage::class.java) {
            val entries = mutableListOf("manifest.json" to manifestWithFonts(*manifestFonts))
            entries.addAll(fonts)
            BackupImporter.importV1Directory(rawDirectory(entries))
        }
        assertEquals("Total font size exceeds limit", exDir.message)
    }
}
