package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.BackupSettings as CoreBackupSettings
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.time.Instant
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupV1ManifestDecodeTest {
    @Test
    fun decodesCurrentAppleV1ManifestWithoutV2Fields() {
        val manifest = BackupImporter.decodeManifest(v1ManifestJson().toByteArray(Charsets.UTF_8))

        assertEquals(BackupVersion.APPLE_V1, manifest.version)
        assertEquals(WORK_ID, manifest.works.single().id)
        assertEquals("https://archiveofourown.org/works/123", manifest.works.single().sourceURL)
        assertNull(manifest.works.single().comments)
        assertNull(manifest.works.single().hits)
        assertNull(manifest.works.single().knownChapterCount)
        assertTrue(manifest.collections.isEmpty())
        assertTrue(manifest.savedSearches.isEmpty())
    }

    @Test
    fun importsAppleV1DirectoryPackageWhereAccessible() {
        val root = Files.createTempDirectory("kudos-v1").resolve("Library.kudosbackup")
        val works = root.resolve("Works")
        val fonts = root.resolve("Fonts")
        Files.createDirectories(works)
        Files.createDirectories(fonts)
        Files.write(root.resolve(BackupPaths.MANIFEST), v1ManifestJson().toByteArray(Charsets.UTF_8))
        Files.write(works.resolve("${WORK_ID.uppercase()}.epub"), EPUB_BYTES)
        Files.write(fonts.resolve("Reader.ttf"), FONT_BYTES)

        val backup = BackupImporter.importV1Directory(root)

        assertEquals(BackupVersion.APPLE_V1, backup.manifest.version)
        assertArrayEquals(EPUB_BYTES, backup.epubFilesByWorkId[WORK_ID])
        assertArrayEquals(FONT_BYTES, backup.fontFilesByFileName["Reader.ttf"])
    }
}

class BackupV2ZipDecodeTest {
    @Test
    fun importsV2ZipBackup() {
        val bytes = BackupExporter.exportV2(samplePackage())

        val backup = BackupImporter.importV2Zip(bytes)

        assertEquals(BackupVersion.ZIP_V2, backup.manifest.version)
        assertEquals("android", backup.manifest.exportedBy?.platform)
        assertArrayEquals(EPUB_BYTES, backup.epubFilesByWorkId[WORK_ID])
        assertArrayEquals(FONT_BYTES, backup.fontFilesByFileName["Reader.ttf"])
    }

    @Test
    fun preservesMixedCaseUuidAsCanonicalLowercase() {
        val manifest = sampleManifest(
            works = listOf(sampleBackupWork(id = WORK_ID.uppercase()))
        )
        val bytes = BackupExporter.exportV2(
            KudosBackupPackage(
                manifest = manifest,
                epubFilesByWorkId = mapOf(WORK_ID to EPUB_BYTES)
            )
        )

        val backup = BackupImporter.importV2Zip(bytes)

        assertEquals(WORK_ID, backup.manifest.works.single().id)
        assertArrayEquals(EPUB_BYTES, backup.epubFilesByWorkId[WORK_ID])
    }
}

class BackupV2ZipExportTest {
    @Test
    fun writesV2ZipWithManifestWorksFontsCollectionsAndSavedSearches() {
        val bytes = BackupExporter.exportV2(samplePackage())
        val entries = unzip(bytes)

        assertTrue(entries.containsKey(BackupPaths.MANIFEST))
        assertTrue(entries.containsKey("Works/$WORK_ID.epub"))
        assertTrue(entries.containsKey("Fonts/Reader.ttf"))

        val manifest = BackupImporter.decodeManifest(entries.getValue(BackupPaths.MANIFEST))
        assertEquals(BackupVersion.ZIP_V2, manifest.version)
        assertEquals("android", manifest.exportedBy?.platform)
        assertEquals(COLLECTION_ID, manifest.collections.single().id)
        assertEquals(SEARCH_ID, manifest.savedSearches.single().id)
    }
}

class BackupRoundTripBasicTest {
    @Test
    fun exportsImportsAndMergesBasicLibrary() {
        val exported = BackupExporter.exportV2(samplePackage())
        val imported = BackupImporter.importV2Zip(exported)

        val result = BackupMergeService.merge(BackupLibrarySnapshot(), imported)

        assertEquals(1, result.summary.worksCreated)
        assertEquals(1, result.summary.bookmarksCreated)
        assertEquals(1, result.summary.fontsCreated)
        assertEquals(1, result.snapshot.works.size)
        assertEquals("Example Work", result.snapshot.works.single().title)
        assertEquals("Reader.ttf", result.snapshot.fonts.single().fileName)
        assertEquals("custom:Reader.ttf", result.snapshot.settings.readerFontID)
    }
}

class BackupMergeDoesNotDeleteExistingWorkTest {
    @Test
    fun mergeKeepsWorksAbsentFromBackup() {
        val existing = sampleSavedWork(id = OTHER_WORK_ID, title = "Local Only")
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(existing)),
            backup = samplePackage()
        )

        assertEquals(2, result.snapshot.works.size)
        assertNotNull(result.snapshot.works.firstOrNull { it.id == OTHER_WORK_ID })
    }
}

class BackupMergeDoesNotDeleteExistingEpubTest {
    @Test
    fun mergeKeepsLocalEpubWhenBackupLacksFile() {
        val existing = sampleSavedWork(hasEpub = true)
        val backup = samplePackage(epubFiles = emptyMap())

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(existing), epubWorkIds = setOf(WORK_ID)),
            backup = backup
        )

        val restored = result.snapshot.works.single { it.id == WORK_ID }
        assertTrue(restored.hasEpub)
        assertTrue(result.epubFilesToWriteByWorkId.isEmpty())
    }
}

class BackupMissingEpubMarksHasEpubFalseTest {
    @Test
    fun newWorkMarkedHasEpubFalseWhenBackupFileIsMissing() {
        val backup = samplePackage(epubFiles = emptyMap())

        val result = BackupMergeService.merge(BackupLibrarySnapshot(), backup)

        assertFalse(result.snapshot.works.single().hasEpub)
    }
}

class BackupUserTagMergeTest {
    @Test
    fun mergeTrimsAndDeduplicatesUserTags() {
        val backup = samplePackage(
            manifest = sampleManifest(
                works = listOf(
                    sampleBackupWork(userTags = listOf(" Comfort ", "Comfort", "Favorite"))
                )
            )
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                works = listOf(sampleSavedWork()),
                userTagsByWorkId = mapOf(WORK_ID to listOf("Local", " Comfort"))
            ),
            backup = backup
        )

        assertEquals(listOf("Local", "Comfort", "Favorite"), result.snapshot.userTagsByWorkId[WORK_ID])
    }
}

class BackupCollectionMergeTest {
    @Test
    fun collectionWithNameCollisionKeepsSeparateSuffixedCollection() {
        val current = WorkCollection(
            id = OTHER_COLLECTION_ID,
            name = "Favorites",
            dateAdded = DATE,
            workIds = listOf(OTHER_WORK_ID)
        )
        val backup = samplePackage(
            manifest = sampleManifest(
                collections = listOf(
                    BackupCollection(
                        id = COLLECTION_ID,
                        name = "Favorites",
                        dateAdded = DATE_STRING,
                        workIDs = listOf(WORK_ID)
                    )
                )
            )
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(collections = listOf(current)),
            backup = backup
        )

        assertEquals(2, result.snapshot.collections.size)
        assertTrue(result.snapshot.collections.any { it.name == "Favorites" })
        assertTrue(result.snapshot.collections.any { it.name == "Favorites (Restored)" })
    }
}

class BackupBookmarkMergeByUrlTest {
    @Test
    fun bookmarkMergeByUrlDoesNotDuplicate() {
        val existing = Bookmark(
            title = "Old Title",
            urlString = "https://archiveofourown.org/works/123",
            dateAdded = Instant.parse("2026-01-01T00:00:00Z")
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(bookmarks = listOf(existing)),
            backup = samplePackage()
        )

        assertEquals(1, result.snapshot.bookmarks.size)
        assertEquals("Example Bookmark", result.snapshot.bookmarks.single().title)
        assertEquals(1, result.summary.bookmarksUpdated)
    }
}

class BackupFontMissingReaderFontFallbackTest {
    @Test
    fun missingCustomFontSelectionFallsBackToSystem() {
        val backup = samplePackage(
            manifest = sampleManifest(settings = BackupSettingsPayload(readerFontID = "custom:Missing.ttf")),
            fontFiles = emptyMap()
        )

        val result = BackupMergeService.merge(BackupLibrarySnapshot(), backup)

        assertEquals("system", result.snapshot.settings.readerFontID)
    }

    @Test
    fun collidingDifferentFontBytesAreSuffixedAndSettingsRetargeted() {
        val existingFont = CustomFont(name = "Reader", fileName = "Reader.ttf", dateAdded = DATE)
        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(
                fonts = listOf(existingFont),
                fontFilesByFileName = mapOf("Reader.ttf" to "local font".toByteArray())
            ),
            backup = samplePackage()
        )

        assertTrue(result.snapshot.fonts.any { it.fileName == "Reader.ttf" })
        assertTrue(result.snapshot.fonts.any { it.fileName == "Reader-restored-1.ttf" })
        assertEquals("custom:Reader-restored-1.ttf", result.snapshot.settings.readerFontID)
    }
}

class BackupRejectsUnsupportedVersionTest {
    @Test
    fun rejectsUnsupportedManifestVersion() {
        val error = assertThrows(BackupError.UnsupportedVersion::class.java) {
            BackupImporter.decodeManifest(
                BackupJson.encodeToString(sampleManifest().copy(version = 99)).toByteArray(Charsets.UTF_8)
            )
        }

        assertEquals(99, error.version)
    }
}

class BackupRejectsMissingManifestTest {
    @Test
    fun rejectsZipWithoutManifest() {
        assertThrows(BackupError.MissingManifest::class.java) {
            BackupImporter.importV2Zip(rawZip(listOf("Works/$WORK_ID.epub" to EPUB_BYTES)))
        }
    }
}

class BackupRejectsPathTraversalTest {
    @Test
    fun rejectsTraversalEntry() {
        assertThrows(BackupError.UnsafePath::class.java) {
            BackupImporter.importV2Zip(
                rawZip(
                    listOf(
                        BackupPaths.MANIFEST to BackupJson.encodeToString(sampleManifest()).toByteArray(),
                        "../evil" to "bad".toByteArray()
                    )
                )
            )
        }
    }
}

class BackupRejectsAbsolutePathTest {
    @Test
    fun rejectsAbsoluteEntry() {
        assertThrows(BackupError.UnsafePath::class.java) {
            BackupImporter.importV2Zip(
                rawZip(
                    listOf(
                        BackupPaths.MANIFEST to BackupJson.encodeToString(sampleManifest()).toByteArray(),
                        "/tmp/evil" to "bad".toByteArray()
                    )
                )
            )
        }
    }
}

class BackupRejectsInvalidJsonTest {
    @Test
    fun rejectsInvalidManifestJson() {
        assertThrows(BackupError.InvalidJson::class.java) {
            BackupImporter.importV2Zip(rawZip(listOf(BackupPaths.MANIFEST to "{".toByteArray())))
        }
    }

    @Test
    fun rejectsInvalidDateAndUuid() {
        assertThrows(BackupError.InvalidDate::class.java) {
            BackupImporter.decodeManifest(
                BackupJson.encodeToString(sampleManifest(exportedAt = "not-a-date")).toByteArray()
            )
        }
        assertThrows(BackupError.InvalidUuid::class.java) {
            BackupImporter.decodeManifest(
                BackupJson.encodeToString(
                    sampleManifest(works = listOf(sampleBackupWork(id = "not-a-uuid")))
                ).toByteArray()
            )
        }
    }
}

class BackupRejectsTruncatedZipTest {
    @Test
    fun rejectsTruncatedZipBeforeReadingEntries() {
        val bytes = BackupExporter.exportV2(samplePackage())
        val truncated = bytes.copyOf(bytes.size - 22)

        assertThrows(BackupError.InvalidPackage::class.java) {
            BackupImporter.importV2Zip(truncated)
        }
    }
}

class BackupRejectsDuplicateEntryTest {
    @Test
    fun rejectsDuplicateZipEntries() {
        val manifestBytes = BackupJson.encodeToString(sampleManifest()).toByteArray()

        assertThrows(BackupError.DuplicateEntry::class.java) {
            BackupImporter.importV2Zip(
                rawZipAllowingDuplicateEntries(
                    listOf(
                        BackupPaths.MANIFEST to manifestBytes,
                        BackupPaths.MANIFEST to manifestBytes
                    )
                )
            )
        }
    }
}

class BackupPreservesLegacyProgressFieldsTest {
    @Test
    fun preservesSpineIndexAndScrollFractionForCrossPlatformResume() {
        val backup = samplePackage(
            manifest = sampleManifest(
                works = listOf(
                    sampleBackupWork(lastSpineIndex = 3, lastScrollFraction = 0.42)
                )
            )
        )

        val result = BackupMergeService.merge(BackupLibrarySnapshot(), backup)

        assertEquals(3, result.snapshot.works.single().lastSpineIndex)
        assertEquals(0.42, result.snapshot.works.single().lastScrollFraction, 0.0)
    }
}

class BackupPreservesReadiumLocatorAsPlatformSpecificDataTest {
    @Test
    fun preservesReadiumLocatorWithoutTreatingItAsFallbackSource() {
        val locator = """{"locations":{"totalProgression":0.72}}"""
        val backup = samplePackage(
            manifest = sampleManifest(
                works = listOf(
                    sampleBackupWork(
                        lastSpineIndex = 4,
                        lastScrollFraction = 0.5,
                        readiumLocator = locator
                    )
                )
            )
        )

        val result = BackupMergeService.merge(BackupLibrarySnapshot(), backup)

        assertEquals(locator, result.snapshot.works.single().readiumLocator)
        assertEquals(4, result.snapshot.works.single().lastSpineIndex)
        assertEquals(0.5, result.snapshot.works.single().lastScrollFraction, 0.0)
    }
}

private const val WORK_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
private const val OTHER_WORK_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
private const val COLLECTION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
private const val OTHER_COLLECTION_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
private const val SEARCH_ID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
private const val DATE_STRING = "2026-06-26T12:00:00Z"
private val DATE: Instant = Instant.parse(DATE_STRING)
private val EPUB_BYTES = "dummy epub bytes".toByteArray()
private val FONT_BYTES = "dummy font bytes".toByteArray()

private fun samplePackage(
    manifest: KudosBackupManifest = sampleManifest(),
    epubFiles: Map<String, ByteArray> = mapOf(WORK_ID to EPUB_BYTES),
    fontFiles: Map<String, ByteArray> = mapOf("Reader.ttf" to FONT_BYTES)
): KudosBackupPackage {
    return KudosBackupPackage(
        manifest = manifest,
        epubFilesByWorkId = epubFiles,
        fontFilesByFileName = fontFiles
    )
}

private fun sampleManifest(
    version: Int = BackupVersion.ZIP_V2,
    exportedAt: String = DATE_STRING,
    works: List<BackupWork> = listOf(sampleBackupWork()),
    settings: BackupSettingsPayload = BackupSettingsPayload(readerFontID = "custom:Reader.ttf"),
    collections: List<BackupCollection> = listOf(
        BackupCollection(
            id = COLLECTION_ID,
            name = "Favorites",
            dateAdded = DATE_STRING,
            workIDs = listOf(WORK_ID)
        )
    ),
    savedSearches: List<BackupSavedSearch> = listOf(
        BackupSavedSearch(
            id = SEARCH_ID,
            name = "Slow Burn",
            dateAdded = DATE_STRING
        )
    )
): KudosBackupManifest {
    return KudosBackupManifest(
        version = version,
        exportedAt = exportedAt,
        exportedBy = if (version == BackupVersion.ZIP_V2) {
            BackupExportedBy(platform = "android", appVersion = "0.1.0")
        } else {
            null
        },
        works = works,
        bookmarks = listOf(
            BackupBookmark(
                title = "Example Bookmark",
                urlString = "https://archiveofourown.org/works/123",
                dateAdded = DATE_STRING
            )
        ),
        fonts = listOf(
            BackupFont(
                name = "Reader",
                fileName = "Reader.ttf",
                dateAdded = DATE_STRING
            )
        ),
        collections = collections,
        savedSearches = savedSearches,
        settings = settings
    )
}

private fun sampleBackupWork(
    id: String = WORK_ID,
    hasEpub: Boolean = true,
    userTags: List<String> = listOf("Comfort"),
    lastSpineIndex: Int = 0,
    lastScrollFraction: Double = 0.0,
    readiumLocator: String? = null
): BackupWork {
    return BackupWork(
        id = id,
        title = "Example Work",
        author = "Example Author",
        summary = "Summary",
        sourceURL = "https://archiveofourown.org/works/123",
        dateAdded = DATE_STRING,
        isFavorite = false,
        isSaved = true,
        isFinished = false,
        hasEPUB = hasEpub,
        isComplete = true,
        rating = "Teen And Up Audiences",
        language = "English",
        wordCount = 1200,
        chapters = "1/1",
        kudos = 7,
        comments = 2,
        hits = 30,
        workWarnings = listOf("No Archive Warnings Apply"),
        workCategories = listOf("Gen"),
        seriesTitle = "",
        seriesPosition = 0,
        seriesURL = "",
        lastSpineIndex = lastSpineIndex,
        lastScrollFraction = lastScrollFraction,
        lastReadDate = DATE_STRING,
        knownChapterCount = 1,
        lastUpdateCheck = DATE_STRING,
        workTags = listOf("Fluff"),
        workFandoms = listOf("Example Fandom"),
        workCharacters = emptyList(),
        workRelationships = emptyList(),
        workFreeforms = listOf("Fluff"),
        workTagsFetched = true,
        userTags = userTags,
        collectionIDs = listOf(COLLECTION_ID),
        readiumLocator = readiumLocator,
        readiumLocatorPlatform = "android",
        readiumLocatorEngine = "readium-kotlin",
        readiumLocatorVersion = "test"
    )
}

private fun sampleSavedWork(
    id: String = WORK_ID,
    title: String = "Existing Work",
    hasEpub: Boolean = true
): SavedWork {
    return SavedWork(
        id = id,
        title = title,
        author = "Existing Author",
        sourceUrl = "https://archiveofourown.org/works/123",
        dateAdded = DATE,
        isSaved = true,
        hasEpub = hasEpub,
        comments = 99,
        hits = 100,
        knownChapterCount = 1,
        lastUpdateCheck = DATE
    )
}

private fun unzip(bytes: ByteArray): Map<String, ByteArray> {
    val result = linkedMapOf<String, ByteArray>()
    ZipInputStream(bytes.inputStream()).use { zip ->
        while (true) {
            val entry = zip.nextEntry ?: break
            if (!entry.isDirectory) {
                result[entry.name] = zip.readBytes()
            }
            zip.closeEntry()
        }
    }
    return result
}

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

private fun rawZipAllowingDuplicateEntries(entries: List<Pair<String, ByteArray>>): ByteArray {
    val output = ByteArrayOutputStream()
    val centralDirectory = ByteArrayOutputStream()
    val centralOffsets = mutableListOf<Int>()

    entries.forEach { (name, bytes) ->
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val crc = CRC32().apply { update(bytes) }.value
        val localOffset = output.size()
        centralOffsets += localOffset

        output.writeIntLe(0x04034b50)
        output.writeShortLe(20)
        output.writeShortLe(0)
        output.writeShortLe(0)
        output.writeShortLe(0)
        output.writeShortLe(0)
        output.writeIntLe(crc.toInt())
        output.writeIntLe(bytes.size)
        output.writeIntLe(bytes.size)
        output.writeShortLe(nameBytes.size)
        output.writeShortLe(0)
        output.write(nameBytes)
        output.write(bytes)
    }

    entries.forEachIndexed { index, (name, bytes) ->
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val crc = CRC32().apply { update(bytes) }.value

        centralDirectory.writeIntLe(0x02014b50)
        centralDirectory.writeShortLe(20)
        centralDirectory.writeShortLe(20)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeIntLe(crc.toInt())
        centralDirectory.writeIntLe(bytes.size)
        centralDirectory.writeIntLe(bytes.size)
        centralDirectory.writeShortLe(nameBytes.size)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeShortLe(0)
        centralDirectory.writeIntLe(0)
        centralDirectory.writeIntLe(centralOffsets[index])
        centralDirectory.write(nameBytes)
    }

    val centralOffset = output.size()
    val centralBytes = centralDirectory.toByteArray()
    output.write(centralBytes)
    output.writeIntLe(0x06054b50)
    output.writeShortLe(0)
    output.writeShortLe(0)
    output.writeShortLe(entries.size)
    output.writeShortLe(entries.size)
    output.writeIntLe(centralBytes.size)
    output.writeIntLe(centralOffset)
    output.writeShortLe(0)
    return output.toByteArray()
}

private fun ByteArrayOutputStream.writeShortLe(value: Int) {
    write(value and 0xff)
    write((value ushr 8) and 0xff)
}

private fun ByteArrayOutputStream.writeIntLe(value: Int) {
    write(value and 0xff)
    write((value ushr 8) and 0xff)
    write((value ushr 16) and 0xff)
    write((value ushr 24) and 0xff)
}

private fun v1ManifestJson(): String {
    return """
        {
          "version": 1,
          "exportedAt": "$DATE_STRING",
          "works": [
            {
              "id": "${WORK_ID.uppercase()}",
              "title": "Example Work",
              "author": "Example Author",
              "summary": "Summary",
              "sourceURL": "https://archiveofourown.org/works/123",
              "dateAdded": "$DATE_STRING",
              "isFavorite": false,
              "isSaved": true,
              "isFinished": false,
              "hasEPUB": true,
              "isComplete": true,
              "rating": "Teen And Up Audiences",
              "language": "English",
              "wordCount": 1200,
              "chapters": "1/1",
              "kudos": 7,
              "workWarnings": ["No Archive Warnings Apply"],
              "workCategories": ["Gen"],
              "seriesTitle": "",
              "seriesPosition": 0,
              "seriesURL": "",
              "lastSpineIndex": 2,
              "lastScrollFraction": 0.25,
              "lastReadDate": "$DATE_STRING",
              "workTags": ["Fluff"],
              "workFandoms": ["Example Fandom"],
              "workCharacters": [],
              "workRelationships": [],
              "workFreeforms": ["Fluff"],
              "workTagsFetched": true,
              "userTags": ["Comfort"],
              "readiumLocator": "{\"locations\":{\"totalProgression\":0.5}}"
            }
          ],
          "bookmarks": [],
          "fonts": [
            {
              "name": "Reader",
              "fileName": "Reader.ttf",
              "dateAdded": "$DATE_STRING"
            }
          ],
          "settings": {
            "readerFontID": "custom:Reader.ttf",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": true,
            "matureContentMode": "obscure",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000"
          }
        }
    """.trimIndent()
}
