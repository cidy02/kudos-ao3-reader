package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.ReadingFavoriteEntity
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupReadingLogTest {
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var repository: BackupRepository
    private lateinit var filesRoot: java.nio.file.Path

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-reading-log-settings").toFile()
        val settings = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        filesRoot = Files.createTempDirectory("kudos-reading-log-files")
        repository = BackupRepository(
            database = database,
            workFileStore = WorkFileStore(filesRoot),
            fontFileStore = FontFileStore(filesRoot),
            settingsRepository = settings,
            persistenceGate = PersistenceGate(),
            clock = { EXPORT_DATE },
            uuidFactory = { NEW_TAG_ID },
            appVersion = "test"
        )
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        filesRoot.toFile().deleteRecursively()
    }

    @Test
    fun readingLogListsRoundTripThroughExportJsonAndImport() {
        val snapshot = BackupLibrarySnapshot(
            readingSessions = listOf(sampleSession()),
            readingFavorites = listOf(sampleFavorite()),
            fandomReadWatermarks = listOf(sampleWatermark())
        )

        val json = BackupJson.encodeToString(snapshot.toV2Manifest(EXPORT_DATE))
        val imported = BackupImporter.decodeManifest(json.toByteArray())
        val restored = BackupMergeService.merge(
            BackupLibrarySnapshot(),
            KudosBackupPackage(imported),
            now = EXPORT_DATE
        ).snapshot

        assertEquals(snapshot.readingSessions, restored.readingSessions)
        assertEquals(snapshot.readingFavorites, restored.readingFavorites)
        assertEquals(snapshot.fandomReadWatermarks, restored.fandomReadWatermarks)
    }

    @Test
    fun olderArchiveWithoutReadingLogListsLeavesLocalRowsAlone() {
        val manifest = BackupImporter.decodeManifest(
            """{"version":8,"exportedAt":"2026-03-01T00:00:00Z"}""".toByteArray()
        )
        val current = BackupLibrarySnapshot(
            readingSessions = listOf(sampleSession()),
            readingFavorites = listOf(sampleFavorite()),
            fandomReadWatermarks = listOf(sampleWatermark())
        )

        val restored = BackupMergeService.merge(
            current,
            KudosBackupPackage(manifest),
            now = EXPORT_DATE
        ).snapshot

        assertEquals(current.readingSessions, restored.readingSessions)
        assertEquals(current.readingFavorites, restored.readingFavorites)
        assertEquals(current.fandomReadWatermarks, restored.fandomReadWatermarks)
    }

    @Test
    fun queueTagsUnionAndReplaceDropsMissingCrossRefWithoutDeletingTag() = runTest {
        val queue = ReadingQueue(
            id = QUEUE_ID,
            name = "To read",
            dateCreated = LOCAL_DATE,
            dateUpdated = LOCAL_DATE
        )
        database.readingQueueDao().upsertQueue(queue.toEntity())
        val localTag = TagEntity(LOCAL_TAG_ID, "Local", LOCAL_DATE)
        val sharedTag = TagEntity(SHARED_TAG_ID, "Shared", LOCAL_DATE)
        database.tagDao().upsert(localTag)
        database.tagDao().upsert(sharedTag)
        database.readingLogDao().upsertQueueTag(QueueTagCrossRef(QUEUE_ID, LOCAL_TAG_ID))

        val archive = KudosBackupPackage(
            KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = BackupValidator.formatInstant(EXPORT_DATE),
                readingQueues = listOf(
                    queue.toBackupReadingQueue(listOf(" Shared "))
                )
            )
        )
        repository.importPackage(archive, BackupImportMode.MERGE)
        assertEquals(setOf("Local", "Shared"), queueTagNames())

        repository.importPackage(archive, BackupImportMode.REPLACE_LIBRARY)
        assertEquals(setOf("Shared"), queueTagNames())
        assertNotNull(database.tagDao().getByName("Local"))
    }

    @Test
    fun exportSortsQueueTagNames() {
        val queue = ReadingQueue(
            id = QUEUE_ID,
            name = "Sorted",
            dateCreated = LOCAL_DATE,
            dateUpdated = LOCAL_DATE
        )
        val manifest = BackupLibrarySnapshot(
            readingQueues = listOf(queue),
            queueTagNamesByQueueId = mapOf(QUEUE_ID to listOf("Zeta", "Alpha"))
        ).toV2Manifest(EXPORT_DATE)

        assertEquals(listOf("Alpha", "Zeta"), manifest.readingQueues.single().tagNames)
    }

    @Test
    fun recordedSittingFieldsRoundTripAndUpdateOnReconcile() = runTest {
        val recorded = recordedSession()
        val json = BackupJson.encodeToString(
            BackupLibrarySnapshot(readingSessions = listOf(recorded)).toV2Manifest(EXPORT_DATE)
        )
        val imported = BackupImporter.decodeManifest(json.toByteArray())
        repository.importPackage(KudosBackupPackage(imported), BackupImportMode.RECONCILE)
        assertEquals(recorded, database.readingLogDao().getAllSessions().single())

        // Reconcile with a newer/equal timestamp updates all 8 sitting facts on an existing row.
        database.readingLogDao().upsertSession(
            recorded.copy(
                tzOffsetSeconds = null,
                startProgress = null,
                startSpineIndex = null,
                modeRaw = "read",
                playbackRate = null,
                activeSeconds = null,
                deviceID = "old-install",
                rulesVersion = 0,
                lastModifiedAt = LOCAL_DATE.plusSeconds(300)
            )
        )
        repository.importPackage(KudosBackupPackage(imported), BackupImportMode.RECONCILE)
        val updated = database.readingLogDao().getAllSessions().single()
        assertEquals(-18_000, updated.tzOffsetSeconds)
        assertEquals(0.2, requireNotNull(updated.startProgress), 0.0)
        assertEquals(1, updated.startSpineIndex)
        assertEquals("listen", updated.modeRaw)
        assertEquals(1.4, requireNotNull(updated.playbackRate), 0.0)
        assertEquals(140.0, requireNotNull(updated.activeSeconds), 0.0)
        assertEquals("install-1", updated.deviceID)
        assertEquals(1, updated.rulesVersion)
    }

    @Test
    fun importWithoutSittingKeysKeepsStoredValuesAndDefaultsNewRows() = runTest {
        val recorded = recordedSession()
        val fullJson = BackupJson.encodeToString(
            BackupLibrarySnapshot(readingSessions = listOf(recorded)).toV2Manifest(EXPORT_DATE)
        )
        val root = BackupJson.parseToJsonElement(fullJson).jsonObject.toMutableMap()
        val strippedSessions = JsonArray(
            root.getValue("readingSessions").jsonArray.map { element ->
                JsonObject(element.jsonObject - SITTING_KEYS)
            }
        )
        root["readingSessions"] = strippedSessions
        val legacyManifest = BackupImporter.decodeManifest(JsonObject(root).toString().toByteArray())

        // Existing row with recorded values (same lastModifiedAt) keeps all 8 stored facts.
        database.readingLogDao().upsertSession(recorded)
        repository.importPackage(KudosBackupPackage(legacyManifest), BackupImportMode.RECONCILE)
        val preserved = database.readingLogDao().getAllSessions().single()
        assertEquals(-18_000, preserved.tzOffsetSeconds)
        assertEquals(0.2, requireNotNull(preserved.startProgress), 0.0)
        assertEquals(1, preserved.startSpineIndex)
        assertEquals("listen", preserved.modeRaw)
        assertEquals(1.4, requireNotNull(preserved.playbackRate), 0.0)
        assertEquals(140.0, requireNotNull(preserved.activeSeconds), 0.0)
        assertEquals("install-1", preserved.deviceID)
        assertEquals(1, preserved.rulesVersion)

        // A brand-new row from a keyless archive gets the defaults.
        database.readingLogDao().deleteSession(recorded.id)
        repository.importPackage(KudosBackupPackage(legacyManifest), BackupImportMode.RECONCILE)
        val defaulted = database.readingLogDao().getAllSessions().single()
        assertNull(defaulted.tzOffsetSeconds)
        assertNull(defaulted.startProgress)
        assertNull(defaulted.startSpineIndex)
        assertEquals("read", defaulted.modeRaw)
        assertNull(defaulted.playbackRate)
        assertNull(defaulted.activeSeconds)
        assertEquals("", defaulted.deviceID)
        assertEquals(0, defaulted.rulesVersion)
    }

    @Test
    fun exportOmitsSittingKeysForUnrecordedRows() {
        val unrecordedJson = BackupJson.encodeToString(
            BackupLibrarySnapshot(readingSessions = listOf(sampleSession())).toV2Manifest(EXPORT_DATE)
        )
        val unrecordedObject = BackupJson.parseToJsonElement(unrecordedJson)
            .jsonObject.getValue("readingSessions").jsonArray.single().jsonObject
        SITTING_KEYS.forEach { key ->
            assertFalse("unrecorded session should omit $key", unrecordedObject.containsKey(key))
        }

        val recordedJson = BackupJson.encodeToString(
            BackupLibrarySnapshot(readingSessions = listOf(recordedSession())).toV2Manifest(EXPORT_DATE)
        )
        val recordedObject = BackupJson.parseToJsonElement(recordedJson)
            .jsonObject.getValue("readingSessions").jsonArray.single().jsonObject
        SITTING_KEYS.forEach { key ->
            assertTrue("recorded session should include $key", recordedObject.containsKey(key))
        }
    }

    @Test
    fun literalIosReadingLogJsonDecodes() {
        val json = """
            {
              "version": 8,
              "exportedAt": "2026-03-01T00:00:00Z",
              "readingSessions": [{
                "id": "$SESSION_ID", "workID": "$WORK_ID", "ao3WorkID": 42,
                "sourceURL": "https://archiveofourown.org/works/42", "workTitle": "Work",
                "startedAt": "2026-02-01T00:00:00Z", "endedAt": "2026-02-01T00:10:00Z",
                "durationSeconds": 600, "lastSpineIndex": 2, "chapterTitle": "Two",
                "endingProgress": 0.5, "wordCount": 1000, "chapterCountAtVisit": 4,
                "didFinish": false, "lastModifiedAt": "2026-02-01T00:10:00Z"
              }],
              "readingFavorites": [{
                "id": "$FAVORITE_ID", "kindRaw": "tag", "targetKey": "Comfort",
                "displayName": "Comfort", "createdAt": "2026-02-02T00:00:00Z",
                "lastModifiedAt": "2026-02-02T00:00:00Z"
              }],
              "fandomReadWatermarks": [{
                "id": "$WATERMARK_ID", "fandomName": "Fandom",
                "lastVisitedAt": "2026-02-03T00:00:00Z", "newestWorkIDSeen": 42,
                "newestWorkTitleSeen": "Work", "lastModifiedAt": "2026-02-03T00:00:00Z"
              }],
              "readingQueues": [{"id":"$QUEUE_ID","tagNames":["Comfort"]}]
            }
        """.trimIndent()

        val manifest = BackupJson.decodeFromString<KudosBackupManifest>(json)

        assertEquals(WORK_ID, manifest.readingSessions.single().workID)
        assertEquals("tag", manifest.readingFavorites.single().kindRaw)
        assertEquals("Fandom", manifest.fandomReadWatermarks.single().fandomName)
        assertEquals(listOf("Comfort"), manifest.readingQueues.single().tagNames)
    }

    private suspend fun queueTagNames(): Set<String> {
        val namesById = database.tagDao().getAll().associate { it.id to it.name }
        return database.readingLogDao().getQueueTags(QUEUE_ID)
            .mapNotNullTo(mutableSetOf()) { namesById[it.tagId] }
    }

    private fun recordedSession() = sampleSession().copy(
        tzOffsetSeconds = -18_000,
        startProgress = 0.2,
        startSpineIndex = 1,
        modeRaw = "listen",
        playbackRate = 1.4,
        activeSeconds = 140.0,
        deviceID = "install-1",
        rulesVersion = 1
    )

    private fun sampleSession() = ReadingSessionEntity(
        id = SESSION_ID,
        workID = WORK_ID,
        ao3WorkID = 42,
        sourceURL = "https://archiveofourown.org/works/42",
        workTitle = "Work",
        startedAt = LOCAL_DATE,
        endedAt = LOCAL_DATE.plusSeconds(600),
        durationSeconds = 600.0,
        lastSpineIndex = 2,
        chapterTitle = "Two",
        endingProgress = 0.5,
        wordCount = 1_000,
        chapterCountAtVisit = 4,
        didFinish = false,
        lastModifiedAt = LOCAL_DATE.plusSeconds(600)
    )

    private fun sampleFavorite() = ReadingFavoriteEntity(
        id = FAVORITE_ID,
        kindRaw = "tag",
        targetKey = "Comfort",
        displayName = "Comfort",
        createdAt = LOCAL_DATE,
        lastModifiedAt = LOCAL_DATE
    )

    private fun sampleWatermark() = FandomReadWatermarkEntity(
        id = WATERMARK_ID,
        fandomName = "Fandom",
        lastVisitedAt = LOCAL_DATE,
        newestWorkIDSeen = 42,
        newestWorkTitleSeen = "Work",
        lastModifiedAt = LOCAL_DATE
    )

    private companion object {
        val LOCAL_DATE: Instant = Instant.parse("2026-02-01T00:00:00Z")
        val EXPORT_DATE: Instant = Instant.parse("2026-03-01T00:00:00Z")
        const val SESSION_ID = "11111111-1111-4111-8111-111111111111"
        const val FAVORITE_ID = "22222222-2222-4222-8222-222222222222"
        const val WATERMARK_ID = "33333333-3333-4333-8333-333333333333"
        const val WORK_ID = "44444444-4444-4444-8444-444444444444"
        const val QUEUE_ID = "55555555-5555-4555-8555-555555555555"
        const val LOCAL_TAG_ID = "66666666-6666-4666-8666-666666666666"
        const val SHARED_TAG_ID = "77777777-7777-4777-8777-777777777777"
        const val NEW_TAG_ID = "88888888-8888-4888-8888-888888888888"
        val SITTING_KEYS = setOf(
            "tzOffsetSeconds",
            "startProgress",
            "startSpineIndex",
            "modeRaw",
            "playbackRate",
            "activeSeconds",
            "deviceID",
            "rulesVersion"
        )
    }
}
