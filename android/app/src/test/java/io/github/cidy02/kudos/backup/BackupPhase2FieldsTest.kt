package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupPhase2FieldsTest {

    @Test
    fun workWithEveryNewFieldRoundTrips() {
        val original = sampleSavedWork().copy(
            keepInProgressOverride = true,
            bookmarks = 42,
            epubDigest = "digest-abc-123",
            legacyReaderProgress = 0.65,
            hiddenFromHistoryAt = Instant.parse("2026-08-15T10:00:00Z"),
            datePublished = "2024-01-01",
            dateUpdated = "2024-06-01",
            ao3SeriesID = 987,
            assetIdentifier = "asset-xyz"
        )
        val backupWork = original.toBackupWork()
        val json = BackupJson.encodeToString(backupWork)
        val decodedBackupWork = BackupJson.decodeFromString<BackupWork>(json)
        val restored = decodedBackupWork.toSavedWork(hasEpub = true)

        assertEquals(true, restored.keepInProgressOverride)
        assertEquals(42, restored.bookmarks)
        assertEquals("digest-abc-123", restored.epubDigest)
        assertEquals(0.65, restored.legacyReaderProgress!!, 0.0001)
        assertEquals(Instant.parse("2026-08-15T10:00:00Z"), restored.hiddenFromHistoryAt)
        assertEquals("2024-01-01", restored.datePublished)
        assertEquals("2024-06-01", restored.dateUpdated)
        assertEquals(987, restored.ao3SeriesID)
        assertEquals("asset-xyz", restored.assetIdentifier)
    }

    @Test
    fun workWithNullTriStateFieldsRoundTripsAsJsonNull() {
        val original = sampleSavedWork().copy(
            legacyReaderProgress = null,
            hiddenFromHistoryAt = null,
            bookmarks = null,
            epubDigest = "",
            assetIdentifier = ""
        )
        val backupWork = original.toBackupWork()
        assertEquals(JsonNull, backupWork.legacyReaderProgress)
        assertEquals(JsonNull, backupWork.hiddenFromHistoryAt)
        assertEquals(0, backupWork.bookmarks)
        assertNull(backupWork.epubDigest)
        assertNull(backupWork.assetIdentifier)

        val json = BackupJson.encodeToString(backupWork)
        assertTrue(json.contains("\"legacyReaderProgress\": null"))
        assertTrue(json.contains("\"hiddenFromHistoryAt\": null"))
        assertFalse(json.contains("\"epubDigest\""))
        assertFalse(json.contains("\"assetIdentifier\""))

        val decoded = BackupJson.decodeFromString<BackupWork>(json)
        assertEquals(JsonNull, decoded.legacyReaderProgress)
        assertEquals(JsonNull, decoded.hiddenFromHistoryAt)

        val restored = decoded.toSavedWork(hasEpub = true)
        assertNull(restored.legacyReaderProgress)
        assertNull(restored.hiddenFromHistoryAt)
        assertEquals(0, restored.bookmarks)
        assertEquals("", restored.epubDigest)
        assertEquals("", restored.assetIdentifier)
    }

    @Test
    fun triStateFields_archiveOmitsHiddenFromHistoryAt_localValueIsKeptEvenWhenArchiveWins() {
        val localDate = Instant.parse("2026-05-01T12:00:00Z")
        val local = sampleSavedWork().copy(
            hiddenFromHistoryAt = localDate,
            legacyReaderProgress = 0.5,
            lastModifiedAt = Instant.parse("2026-05-01T12:00:00Z")
        )
        val archive = sampleBackupWork().copy(
            lastModifiedAt = "2026-08-01T12:00:00Z",
            hiddenFromHistoryAt = null,
            legacyReaderProgress = null
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(works = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.works.single { it.id == WORK_ID }
        assertEquals(localDate, merged.hiddenFromHistoryAt)
        assertEquals(0.5, merged.legacyReaderProgress!!, 0.0001)
    }

    @Test
    fun triStateFields_archiveHasExplicitNullAndWins_itClears() {
        val localDate = Instant.parse("2026-05-01T12:00:00Z")
        val local = sampleSavedWork().copy(
            hiddenFromHistoryAt = localDate,
            legacyReaderProgress = 0.5,
            lastModifiedAt = Instant.parse("2026-05-01T12:00:00Z")
        )
        val archive = sampleBackupWork().copy(
            lastModifiedAt = "2026-08-01T12:00:00Z",
            hiddenFromHistoryAt = JsonNull,
            legacyReaderProgress = JsonNull
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(works = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.works.single { it.id == WORK_ID }
        assertNull(merged.hiddenFromHistoryAt)
        assertNull(merged.legacyReaderProgress)
    }

    @Test
    fun triStateFields_archiveHasDateAndLoses_localValueIsKept() {
        val localDate = Instant.parse("2026-08-01T12:00:00Z")
        // The Mac percent goes with the reading progress and its clock (iOS `applyProgress`),
        // so the local side has read later, as well as been edited later.
        val local = sampleSavedWork().copy(
            hiddenFromHistoryAt = localDate,
            legacyReaderProgress = 0.75,
            lastSpineIndex = 3,
            progressModifiedAt = Instant.parse("2026-08-01T12:00:00Z"),
            lastModifiedAt = Instant.parse("2026-08-01T12:00:00Z")
        )
        val archive = sampleBackupWork().copy(
            lastModifiedAt = "2026-05-01T12:00:00Z",
            progressModifiedAt = "2026-05-01T12:00:00Z",
            hiddenFromHistoryAt = JsonPrimitive("2026-04-01T12:00:00Z"),
            legacyReaderProgress = JsonPrimitive(0.2)
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(works = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.works.single { it.id == WORK_ID }
        assertEquals(localDate, merged.hiddenFromHistoryAt)
        assertEquals(0.75, merged.legacyReaderProgress!!, 0.0001)
    }

    @Test
    fun freedAtAndAuthorIdentitiesJsonSurviveAWinningArchive() {
        val localFreedAt = Instant.parse("2026-06-01T00:00:00Z")
        val localAuthorIdentities = "{\"pseud\":\"AuthorAlice\"}"
        val local = sampleSavedWork().copy(
            freedAt = localFreedAt,
            authorIdentitiesJSON = localAuthorIdentities,
            lastModifiedAt = Instant.parse("2026-05-01T00:00:00Z")
        )
        val archive = sampleBackupWork().copy(
            title = "Winning Title",
            lastModifiedAt = "2026-08-01T00:00:00Z"
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(works = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(works = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.works.single { it.id == WORK_ID }
        assertEquals("Winning Title", merged.title)
        assertEquals(localFreedAt, merged.freedAt)
        assertEquals(localAuthorIdentities, merged.authorIdentitiesJSON)
    }

    @Test
    fun chosenColorPortedFromIosExactColourBackupTests() {
        val local = 0.58 to "#1E90FF"

        // Same hue, no hex: written by a build without `colorHex`.
        val dropped = SyncMerge.chosenColor(local = local, incoming = 0.58 to null, incomingWins = true)
        assertEquals(0.58, dropped.first!!, 0.0001)
        assertEquals("#1E90FF", dropped.second)

        // Same hue within 0.01 tolerance (< 0.01), no hex
        val nearHue = SyncMerge.chosenColor(local = local, incoming = 0.585 to null, incomingWins = true)
        assertEquals(0.58, nearHue.first!!, 0.0001)
        assertEquals("#1E90FF", nearHue.second)

        // A different hue that wins is a real recolour, to a preset.
        val preset = SyncMerge.chosenColor(local = local, incoming = 0.0663 to null, incomingWins = true)
        assertEquals(0.0663, preset.first!!, 0.0001)
        assertNull(preset.second)

        // An exact colour that wins replaces the local one.
        val picked = SyncMerge.chosenColor(local = local, incoming = 0.95 to "#E0457B", incomingWins = true)
        assertEquals(0.95, picked.first!!, 0.0001)
        assertEquals("#E0457B", picked.second)

        // Losing, or carrying no hue at all, changes nothing.
        val lost = SyncMerge.chosenColor(local = local, incoming = 0.95 to "#E0457B", incomingWins = false)
        assertEquals(0.58, lost.first!!, 0.0001)
        assertEquals("#1E90FF", lost.second)

        val silent = SyncMerge.chosenColor(local = local, incoming = null to null, incomingWins = true)
        assertEquals(0.58, silent.first!!, 0.0001)
        assertEquals("#1E90FF", silent.second)

        // A colourless local queue takes the archive's, exact or not.
        val filled = SyncMerge.chosenColor(local = null to null, incoming = 0.95 to "#E0457B", incomingWins = false)
        assertEquals(0.95, filled.first!!, 0.0001)
        assertEquals("#E0457B", filled.second)
    }

    @Test
    fun collectionOlderArchiveWithoutHueDoesNotClearLocalColour() {
        val local = WorkCollection(
            id = COLLECTION_ID,
            name = "My Collection",
            dateAdded = DATE,
            lastModifiedAt = Instant.parse("2026-05-01T00:00:00Z"),
            hue = 0.72,
            colorHex = "#7B1FA2",
            showsOnHome = true
        )
        val archive = BackupCollection(
            id = COLLECTION_ID,
            name = "My Collection",
            dateAdded = DATE_STRING,
            lastModifiedAt = "2026-08-01T00:00:00Z",
            hue = null,
            colorHex = null
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(collections = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(collections = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.collections.single { it.id == COLLECTION_ID }
        assertEquals(0.72, merged.hue!!, 0.0001)
        assertEquals("#7B1FA2", merged.colorHex)
    }

    @Test
    fun collectionShowsOnHomeFalseInLosingArchiveDoesNotTakeOffHome() {
        val local = WorkCollection(
            id = COLLECTION_ID,
            name = "Home Collection",
            dateAdded = DATE,
            lastModifiedAt = Instant.parse("2026-08-01T00:00:00Z"),
            showsOnHome = true
        )
        val archive = BackupCollection(
            id = COLLECTION_ID,
            name = "Home Collection",
            dateAdded = DATE_STRING,
            lastModifiedAt = "2026-05-01T00:00:00Z",
            showsOnHome = false
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(collections = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(collections = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.collections.single { it.id == COLLECTION_ID }
        assertTrue(merged.showsOnHome)
    }

    @Test
    fun queueLosingArchiveWithIsPinnedFalseDoesNotUnpin() {
        val local = ReadingQueue(
            id = QUEUE_ID,
            name = "Pinned Queue",
            dateCreated = DATE,
            dateUpdated = Instant.parse("2026-08-01T00:00:00Z"),
            isPinned = true
        )
        val archive = BackupReadingQueue(
            id = QUEUE_ID,
            name = "Pinned Queue",
            dateCreated = DATE_STRING,
            dateUpdated = "2026-05-01T00:00:00Z",
            isPinned = false
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(readingQueues = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(readingQueues = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.readingQueues.single { it.id == QUEUE_ID }
        assertTrue(merged.isPinned)
    }

    @Test
    fun queueWinningArchiveWithIsPinnedFalseDoesUnpin() {
        val local = ReadingQueue(
            id = QUEUE_ID,
            name = "Pinned Queue",
            dateCreated = DATE,
            dateUpdated = Instant.parse("2026-05-01T00:00:00Z"),
            isPinned = true
        )
        val archive = BackupReadingQueue(
            id = QUEUE_ID,
            name = "Pinned Queue",
            dateCreated = DATE_STRING,
            dateUpdated = "2026-08-01T00:00:00Z",
            isPinned = false
        )

        val result = BackupMergeService.merge(
            current = BackupLibrarySnapshot(readingQueues = listOf(local)),
            backup = samplePackage(manifest = sampleManifest(readingQueues = listOf(archive))),
            now = Instant.parse("2026-09-01T00:00:00Z")
        )

        val merged = result.snapshot.readingQueues.single { it.id == QUEUE_ID }
        assertFalse(merged.isPinned)
    }

    @Test
    fun decodeLiteralJsonWorkShapedLikeIosExport() {
        val json = """
            {
              "id": "$WORK_ID",
              "title": "iOS Work",
              "author": "iOS Author",
              "legacyReaderProgress": null,
              "hiddenFromHistoryAt": "2026-09-01T10:00:00Z",
              "bookmarks": 12,
              "keepInProgressOverride": true
            }
        """.trimIndent()

        val decoded = BackupJson.decodeFromString<BackupWork>(json)
        assertEquals(WORK_ID, decoded.id)
        assertEquals("iOS Work", decoded.title)
        assertEquals(JsonNull, decoded.legacyReaderProgress)
        assertTrue(decoded.hiddenFromHistoryAt is JsonPrimitive)
        assertEquals("2026-09-01T10:00:00Z", (decoded.hiddenFromHistoryAt as JsonPrimitive).content)
        assertEquals(12, decoded.bookmarks)
        assertEquals(true, decoded.keepInProgressOverride)

        val savedWork = decoded.toSavedWork(hasEpub = true)
        assertEquals(WORK_ID, savedWork.id)
        assertNull(savedWork.legacyReaderProgress)
        assertEquals(Instant.parse("2026-09-01T10:00:00Z"), savedWork.hiddenFromHistoryAt)
        assertEquals(12, savedWork.bookmarks)
        assertTrue(savedWork.keepInProgressOverride)
    }
}

private const val WORK_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
private const val COLLECTION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
private const val QUEUE_ID = "11111111-1111-4111-8111-111111111111"
private const val DATE_STRING = "2026-06-26T12:00:00Z"
private val DATE: Instant = Instant.parse(DATE_STRING)

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

private fun sampleManifest(
    version: Int = BackupVersion.CURRENT,
    exportedAt: String = DATE_STRING,
    works: List<BackupWork> = listOf(sampleBackupWork()),
    settings: BackupSettingsPayload = BackupSettingsPayload(),
    collections: List<BackupCollection> = emptyList(),
    savedSearches: List<BackupSavedSearch> = emptyList(),
    readingQueues: List<BackupReadingQueue> = emptyList(),
    readingQueueMemberships: List<BackupReadingQueueMembership> = emptyList(),
    annotations: List<BackupAnnotation> = emptyList(),
    tombstones: List<BackupTombstone> = emptyList()
): KudosBackupManifest {
    return KudosBackupManifest(
        version = version,
        exportedAt = exportedAt,
        exportedBy = BackupExportedBy(
            platform = "android",
            appVersion = "0.1.0",
            schemaVersion = version
        ),
        works = works,
        bookmarks = emptyList(),
        fonts = emptyList(),
        collections = collections,
        savedSearches = savedSearches,
        readingQueues = readingQueues,
        readingQueueMemberships = readingQueueMemberships,
        annotations = annotations,
        tombstones = tombstones,
        settings = settings
    )
}

private fun samplePackage(
    manifest: KudosBackupManifest = sampleManifest(),
    epubFiles: Map<String, ByteArray> = emptyMap(),
    fontFiles: Map<String, ByteArray> = emptyMap()
): KudosBackupPackage {
    return KudosBackupPackage(
        manifest = manifest,
        epubFilesByWorkId = epubFiles,
        fontFilesByFileName = fontFiles
    )
}
