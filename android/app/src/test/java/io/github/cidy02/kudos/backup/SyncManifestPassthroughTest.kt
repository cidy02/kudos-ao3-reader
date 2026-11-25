package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.documentfile.provider.DocumentFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertArrayEquals
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

/**
 * JVM/Robolectric tests for A-541 part 1: Android must never drop unmodeled backup/sync
 * manifest fields across sync-down and sync-up (including iOS T-541 fields).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SyncManifestPassthroughTest {
    private lateinit var context: Context
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var workFileStore: WorkFileStore
    private lateinit var fontFileStore: FontFileStore
    private lateinit var backupRepository: BackupRepository
    private lateinit var persistenceGate: PersistenceGate
    private lateinit var syncRepository: SyncRepository

    private lateinit var safRoot: File
    private lateinit var filesRoot: java.nio.file.Path
    private lateinit var treeUri: Uri
    private lateinit var provider: FakeTempDocumentsProvider

    private var clockInstant: Instant = FIXED_CLOCK

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()

        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-a541-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )

        filesRoot = Files.createTempDirectory("kudos-a541-files")
        workFileStore = WorkFileStore(filesRoot)
        fontFileStore = FontFileStore(filesRoot)
        persistenceGate = PersistenceGate()
        backupRepository = BackupRepository(
            database = database,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository,
            persistenceGate = persistenceGate,
            clock = { clockInstant },
            uuidFactory = { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" },
            appVersion = "test"
        )

        safRoot = Files.createTempDirectory("kudos-a541-saf").toFile()
        provider = FakeTempDocumentsProvider()
        treeUri = provider.install(context, safRoot)

        syncRepository = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = { clockInstant },
            scheduleBackgroundSync = {}
        )

        runBlocking {
            settingsRepository.updateSyncFolderUri(treeUri.toString())
            settingsRepository.updateSyncIsEnabled(true)
        }
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        safRoot.deleteRecursively()
        filesRoot.toFile().deleteRecursively()
    }

    @Test
    fun iosT541ManifestSurvivesSyncDownAndSyncUpWithEveryUnknownKeyIdentical() = runTest {
        val fixture = iosT541ManifestJson()
        val kudosDir = ensureKudosLibrary()
        writeChild(
            kudosDir,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8)
        )

        val result = syncRepository.runSync()
        assertTrue("sync should succeed: $result", result is SyncResult.Success)
        assertTrue(
            "last-read manifest should be persisted beside sync state",
            Files.isRegularFile(filesRoot.resolve("sync-last-manifest.json"))
        )

        val firstBytes = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        val written = Json.parseToJsonElement(firstBytes.toString(Charsets.UTF_8)).jsonObject

        // 1 & 4: Top-level unknown keys and unknown record arrays.
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(fixture["futureRecords"], written["futureRecords"])
        assertEquals(fixture["futureManifestMeta"], written["futureManifestMeta"])

        // Pronunciations: per-entry stamps and extra key preserved.
        val writtenPron = written.getValue("pronunciations").jsonObject
        val fixturePron = fixture.getValue("pronunciations").jsonObject
        assertEquals(fixturePron["stamps"], writtenPron["stamps"])
        assertEquals(fixturePron["futurePronKey"], writtenPron["futurePronKey"])

        // 2: Settings unknown keys, modifiedAt, and extras preserved.
        val writtenSettings = written.getValue("settings").jsonObject
        val fixtureSettings = fixture.getValue("settings").jsonObject
        assertEquals(fixtureSettings["modifiedAt"], writtenSettings["modifiedAt"])
        assertEquals(fixtureSettings["extras"], writtenSettings["extras"])
        assertEquals(fixtureSettings["futureSetting"], writtenSettings["futureSetting"])

        // 3: Per-record unknown keys across T-541 records.
        val writtenWork = written.getValue("works").jsonArray.first {
            it.jsonObject["id"]?.jsonPrimitive?.content?.equals(WORK_ONE, ignoreCase = true) == true
        }.jsonObject
        val fixtureWork = fixture.getValue("works").jsonArray[0].jsonObject
        assertEquals(fixtureWork["authorIdentitiesJSON"], writtenWork["authorIdentitiesJSON"])
        assertEquals(fixtureWork["futureWorkInsights"], writtenWork["futureWorkInsights"])

        val writtenCollection = written.getValue("collections").jsonArray.single().jsonObject
        val fixtureCollection = fixture.getValue("collections").jsonArray.single().jsonObject
        assertEquals(fixtureCollection["lastMembershipChangedAt"], writtenCollection["lastMembershipChangedAt"])
        assertEquals(fixtureCollection["futureCollectionKey"], writtenCollection["futureCollectionKey"])

        val writtenSession = written.getValue("readingSessions").jsonArray.single().jsonObject
        val fixtureSession = fixture.getValue("readingSessions").jsonArray.single().jsonObject
        listOf(
            "tzOffsetSeconds", "startProgress", "startSpineIndex", "modeRaw",
            "playbackRate", "activeSeconds", "deviceID", "rulesVersion", "futureSessionField"
        ).forEach { key ->
            assertEquals("readingSession.$key", fixtureSession[key], writtenSession[key])
        }

        listOf(
            "readingQueues", "readingQueueMemberships", "annotations",
            "bookmarks", "savedSearches", "readingFavorites", "fandomReadWatermarks", "tombstones"
        ).forEach { listName ->
            val expectedRecord = fixture.getValue(listName).jsonArray.first().jsonObject
            val actualRecord = written.getValue(listName).jsonArray.first {
                it.jsonObject["id"]?.jsonPrimitive?.content
                    ?.equals(expectedRecord["id"]?.jsonPrimitive?.content, ignoreCase = true) == true
            }.jsonObject
            assertEquals("$listName.futureField", expectedRecord["futureField"], actualRecord["futureField"])
        }

        // Second sync is idempotent and byte-identical.
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertArrayEquals(firstBytes, readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
    }

    @Test
    fun knownFieldsChangedByAndroidAreUpdatedWhileUnknownFieldsSurvive() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        // Mutate known fields locally on Android.
        settingsRepository.updateReaderMode(ReaderMode.Scroll)
        settingsRepository.updateReaderFontPt(22.5)
        val storedWork = checkNotNull(database.workDao().getById(WORK_ONE)).toDomain()
        database.workDao().upsert(
            storedWork.copy(
                title = "Android Updated Title",
                lastSpineIndex = 6,
                lastScrollFraction = 0.85,
                lastModifiedAt = FIXED_CLOCK.plusSeconds(120),
                progressModifiedAt = FIXED_CLOCK.plusSeconds(120)
            ).toEntity()
        )
        val storedCollection = checkNotNull(database.collectionDao().getById(COLLECTION_ONE))
        database.collectionDao().upsert(
            storedCollection.copy(
                name = "Android Renamed Collection",
                lastModifiedAt = FIXED_CLOCK.plusSeconds(120)
            )
        )
        KokoroPronunciationStore(filesRoot.toFile()).setOverride("Nico", "nˈikoʊ")

        clockInstant = FIXED_CLOCK.plusSeconds(120)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject

        // Known Android changes are reflected.
        val writtenSettings = written.getValue("settings").jsonObject
        assertEquals(JsonPrimitive("scroll"), writtenSettings["readerMode"])
        assertEquals(JsonPrimitive(22.5), writtenSettings["readerFontPt"])

        val writtenWork = written.getValue("works").jsonArray.first {
            it.jsonObject["id"]?.jsonPrimitive?.content?.equals(WORK_ONE, ignoreCase = true) == true
        }.jsonObject
        assertEquals(JsonPrimitive("Android Updated Title"), writtenWork["title"])
        assertEquals(JsonPrimitive(6), writtenWork["lastSpineIndex"])
        assertEquals(JsonPrimitive(0.85), writtenWork["lastScrollFraction"])

        val writtenCollection = written.getValue("collections").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive("Android Renamed Collection"), writtenCollection["name"])

        val writtenPron = written.getValue("pronunciations").jsonObject
        assertEquals(JsonPrimitive("nˈikoʊ"), writtenPron.getValue("global").jsonObject["Nico"])

        // Unmodeled T-541 keys remain identical.
        val fixtureSettings = fixture.getValue("settings").jsonObject
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(fixtureSettings["modifiedAt"], writtenSettings["modifiedAt"])
        assertEquals(fixtureSettings["extras"], writtenSettings["extras"])
        assertEquals(fixture.getValue("pronunciations").jsonObject["stamps"], writtenPron["stamps"])
        assertEquals(fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"], writtenWork["authorIdentitiesJSON"])
        assertEquals(fixture.getValue("collections").jsonArray.single().jsonObject["lastMembershipChangedAt"], writtenCollection["lastMembershipChangedAt"])
        assertEquals(
            fixture.getValue("readingSessions").jsonArray.single().jsonObject["activeSeconds"],
            written.getValue("readingSessions").jsonArray.single().jsonObject["activeSeconds"]
        )
    }

    @Test
    fun settingsMapsKeepIosEntriesAndUpdateAndroidWrittenEntries() {
        val replaced = Json.parseToJsonElement(
            """{
                "settings": {
                    "readerMode": "paged",
                    "futureSetting": "keepMe",
                    "modifiedAt": {
                        "readerMode": "2026-11-16T01:00:00.000Z",
                        "keepScreenAwake": "2026-11-16T01:00:00.000Z"
                    },
                    "extras": {
                        "keepScreenAwake": true,
                        "readerHighlightColor": "yellow"
                    }
                },
                "pronunciations": {
                    "global": {"Sam": "sæm"},
                    "fandoms": {},
                    "works": {},
                    "stamps": {
                        "[global]Sam": "2026-11-16T01:00:00.000Z",
                        "[global]Nico": "2026-11-16T01:00:00.000Z"
                    }
                }
            }"""
        ).jsonObject
        val outgoing = Json.parseToJsonElement(
            """{
                "settings": {
                    "readerMode": "scroll",
                    "modifiedAt": {
                        "readerMode": "2026-11-16T02:00:00.000Z"
                    },
                    "extras": {
                        "keepScreenAwake": false
                    }
                },
                "pronunciations": {
                    "global": {"Sam": "sæm"},
                    "fandoms": {},
                    "works": {},
                    "stamps": {
                        "[global]Nico": "2026-11-16T02:00:00.000Z"
                    }
                }
            }"""
        ).jsonObject

        val carried = carryUnknownRecordKeys(outgoing, replaced)
        val settings = carried.getValue("settings").jsonObject
        assertEquals(JsonPrimitive("scroll"), settings["readerMode"])
        assertEquals(JsonPrimitive("keepMe"), settings["futureSetting"])
        assertEquals(
            JsonPrimitive("2026-11-16T02:00:00.000Z"),
            settings.getValue("modifiedAt").jsonObject["readerMode"]
        )
        assertEquals(
            JsonPrimitive("2026-11-16T01:00:00.000Z"),
            settings.getValue("modifiedAt").jsonObject["keepScreenAwake"]
        )
        assertEquals(JsonPrimitive(false), settings.getValue("extras").jsonObject["keepScreenAwake"])
        assertEquals(JsonPrimitive("yellow"), settings.getValue("extras").jsonObject["readerHighlightColor"])

        val pronStamps = carried.getValue("pronunciations").jsonObject.getValue("stamps").jsonObject
        assertEquals(JsonPrimitive("2026-11-16T01:00:00.000Z"), pronStamps["[global]Sam"])
        assertEquals(JsonPrimitive("2026-11-16T02:00:00.000Z"), pronStamps["[global]Nico"])
    }

    @Test
    fun deletedRecordsStayDeletedAcrossSyncEvenWhenReplacedManifestHadUnknownKeys() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        // Delete one work, the collection, session, bookmark, and saved search on Android.
        database.workDao().deleteById(WORK_TWO)
        database.collectionDao().deleteById(COLLECTION_ONE)
        database.readingLogDao().deleteSession(SESSION_ONE)
        database.bookmarkDao().deleteById(BOOKMARK_ONE)
        database.savedSearchDao().deleteById(SEARCH_ONE)

        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject

        val workIds = written.getValue("works").jsonArray.map {
            it.jsonObject["id"]?.jsonPrimitive?.content?.lowercase()
        }
        assertEquals(listOf(WORK_ONE), workIds)
        assertEquals(
            fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray.single().jsonObject["authorIdentitiesJSON"]
        )
        assertTrue(written.getValue("collections").jsonArray.isEmpty())
        assertTrue(written.getValue("readingSessions").jsonArray.isEmpty())
        assertTrue(written.getValue("bookmarks").jsonArray.isEmpty())
        assertTrue(written.getValue("savedSearches").jsonArray.isEmpty())
        assertNull(database.workDao().getById(WORK_TWO))
        assertNull(database.collectionDao().getById(COLLECTION_ONE))
    }

    @Test
    fun malformedUnknownValuesAreCarriedVerbatimWithoutParsing() = runTest {
        val base = iosT541ManifestJson()
        val malformed = JsonObject(
            base + mapOf(
                "writingRecovery" to JsonPrimitive("not-an-array"),
                "documents" to Json.parseToJsonElement("""[{"name":123,"bad":[null,true]}]"""),
                "futureMalformed" to Json.parseToJsonElement("""[null,false,{"nested":"raw"}]"""),
                "pronunciations" to JsonObject(
                    base.getValue("pronunciations").jsonObject + mapOf(
                        "stamps" to JsonPrimitive("not-a-timestamp-map")
                    )
                ),
                "settings" to JsonObject(
                    base.getValue("settings").jsonObject + mapOf(
                        "modifiedAt" to Json.parseToJsonElement("""{"readerMode":"not-a-date","bad":999}"""),
                        "extras" to Json.parseToJsonElement("""{"keepScreenAwake":"not-a-bool","bad":[1,null]}"""),
                        "futureNull" to JsonNull
                    )
                ),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            base.getValue("works").jsonArray[0].jsonObject + mapOf(
                                "authorIdentitiesJSON" to Json.parseToJsonElement("""{"unexpected":[1,null]}"""),
                                "futureMalformedWork" to JsonPrimitive("raw-value")
                            )
                        )
                    )
                ),
                "collections" to JsonArray(
                    listOf(
                        JsonObject(
                            base.getValue("collections").jsonArray.single().jsonObject + mapOf(
                                "lastMembershipChangedAt" to JsonPrimitive(12345)
                            )
                        )
                    )
                ),
                "readingSessions" to JsonArray(
                    listOf(
                        JsonObject(
                            base.getValue("readingSessions").jsonArray.single().jsonObject + mapOf(
                                "futureSessionSeconds" to JsonPrimitive("not-a-double"),
                                "futureSessionRules" to Json.parseToJsonElement("""{"broken":true}""")
                            )
                        )
                    )
                )
            )
        )
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), malformed).toByteArray(Charsets.UTF_8)
        )

        val result = syncRepository.runSync()
        assertTrue("sync should tolerate malformed unknown values: $result", result is SyncResult.Success)

        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject

        assertEquals(malformed["writingRecovery"], written["writingRecovery"])
        assertEquals(malformed["documents"], written["documents"])
        assertEquals(malformed["futureMalformed"], written["futureMalformed"])
        assertEquals(
            malformed.getValue("pronunciations").jsonObject["stamps"],
            written.getValue("pronunciations").jsonObject["stamps"]
        )
        assertEquals(
            malformed.getValue("settings").jsonObject["modifiedAt"],
            written.getValue("settings").jsonObject["modifiedAt"]
        )
        assertEquals(
            malformed.getValue("settings").jsonObject["extras"],
            written.getValue("settings").jsonObject["extras"]
        )
        assertEquals(JsonNull, written.getValue("settings").jsonObject["futureNull"])
        assertEquals(
            malformed.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray.single().jsonObject["authorIdentitiesJSON"]
        )
        assertEquals(
            malformed.getValue("works").jsonArray[0].jsonObject["futureMalformedWork"],
            written.getValue("works").jsonArray.single().jsonObject["futureMalformedWork"]
        )
        assertEquals(
            malformed.getValue("collections").jsonArray.single().jsonObject["lastMembershipChangedAt"],
            written.getValue("collections").jsonArray.single().jsonObject["lastMembershipChangedAt"]
        )
        assertEquals(
            malformed.getValue("readingSessions").jsonArray.single().jsonObject["futureSessionSeconds"],
            written.getValue("readingSessions").jsonArray.single().jsonObject["futureSessionSeconds"]
        )
        assertEquals(
            malformed.getValue("readingSessions").jsonArray.single().jsonObject["futureSessionRules"],
            written.getValue("readingSessions").jsonArray.single().jsonObject["futureSessionRules"]
        )
    }

    @Test
    fun backupFallbackConflictFoldingAndPersistedStorePreserveUnknownsAndDisconnectKeepsStore() = runTest {
        val fixture = iosT541ManifestJson()
        val kudosDir = ensureKudosLibrary()

        // 1. Live manifest truncated + .bak valid -> recovers from .bak and preserves unknowns.
        writeChild(kudosDir, BackupPaths.MANIFEST, "application/json", """{"version":8,"works":[""".toByteArray())
        writeChild(
            kudosDir,
            BackupPaths.MANIFEST_BACKUP,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterBak = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(fixture["writingRecovery"], afterBak["writingRecovery"])
        assertEquals(
            fixture.getValue("settings").jsonObject["extras"],
            afterBak.getValue("settings").jsonObject["extras"]
        )

        // 2. Truncated live manifest + no .bak -> falls back to persisted sync-last-manifest.json.
        requireKudosLibrary().findFile(BackupPaths.MANIFEST_BACKUP)?.delete()
        writeChild(requireKudosLibrary(), BackupPaths.MANIFEST, "application/json", """{"version":8""".toByteArray())
        clockInstant = FIXED_CLOCK.plusSeconds(30)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterPersisted = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(fixture["writingRecovery"], afterPersisted["writingRecovery"])
        assertEquals(fixture["documents"], afterPersisted["documents"])

        // 3. When iOS intentionally removes writingRecovery in a newer manifest, Android does not resurrect it.
        val withoutRecovery = JsonObject(
            fixture.filterKeys { it != "writingRecovery" } + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:05:00.000Z")
            )
        )
        writeChild(
            requireKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), withoutRecovery).toByteArray(Charsets.UTF_8)
        )
        clockInstant = FIXED_CLOCK.plusSeconds(360)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterRemoval = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertFalse("Removed top-level key must not be resurrected", "writingRecovery" in afterRemoval)
        assertEquals(fixture["documents"], afterRemoval["documents"])

        // 4. Disconnect keeps the on-device store. It is still the fallback for the next folder.
        assertTrue(Files.isRegularFile(filesRoot.resolve("sync-last-manifest.json")))
        syncRepository.disconnect()
        assertTrue(Files.isRegularFile(filesRoot.resolve("sync-last-manifest.json")))
    }

    @Test
    fun legacyBackupZipAndConflictManifestsPreserveUnknownFields() = runTest {
        val fixture = iosT541ManifestJson()
        val zipBytes = ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST))
                zip.write(BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
            out.toByteArray()
        }
        val root = DocumentFile.fromTreeUri(context, treeUri)!!
        writeChild(root, "Kudos.kudosbackup", "application/zip", zipBytes)

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val fromZip = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(fixture["writingRecovery"], fromZip["writingRecovery"])
        assertEquals(
            fixture.getValue("settings").jsonObject["modifiedAt"],
            fromZip.getValue("settings").jsonObject["modifiedAt"]
        )

        // Newer exportedAt makes this conflict the primary even though it does not hold the live name.
        // Its writingRecovery wins. Its older keepScreenAwake stamp and older work stamp do not.
        val conflictWorkId = "99999999-0000-4000-8000-000000000001"
        val liveWorkOne = fixture.getValue("works").jsonArray[0].jsonObject
        val conflictManifest = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T12:30:00.000Z"),
                "writingRecovery" to JsonPrimitive("from-conflict"),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive("2026-06-26T08:00:00.000Z"))
                        ),
                        "extras" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive(false))
                        )
                    )
                ),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            liveWorkOne + mapOf(
                                "lastModifiedAt" to JsonPrimitive("2026-06-26T09:00:00.000Z"),
                                "authorIdentitiesJSON" to JsonPrimitive("conflict-old")
                            )
                        ),
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(conflictWorkId),
                                "title" to JsonPrimitive("Conflict Work"),
                                "author" to JsonPrimitive("Conflict Author"),
                                "sourceURL" to JsonPrimitive("https://archiveofourown.org/works/777001"),
                                "dateAdded" to JsonPrimitive("2026-06-25T10:00:00.000Z"),
                                "lastModifiedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                                "authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"conflict_u\"}]")
                            )
                        )
                    )
                ),
                "conflictExtra" to JsonObject(mapOf("fromConflict" to JsonPrimitive(true)))
            )
        )
        writeChild(
            requireKudosLibrary(),
            "manifest (1).json",
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), conflictManifest).toByteArray(Charsets.UTF_8)
        )
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterConflict = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(conflictManifest["conflictExtra"], afterConflict["conflictExtra"])
        assertEquals(JsonPrimitive("from-conflict"), afterConflict["writingRecovery"])
        assertEquals(
            fixture.getValue("settings").jsonObject["extras"],
            afterConflict.getValue("settings").jsonObject["extras"]
        )
        val conflictWork = afterConflict.getValue("works").jsonArray.first {
            it.jsonObject["id"]?.jsonPrimitive?.content?.equals(conflictWorkId, ignoreCase = true) == true
        }.jsonObject
        assertEquals(JsonPrimitive("[{\"username\":\"conflict_u\"}]"), conflictWork["authorIdentitiesJSON"])
        val workOne = workJson(afterConflict, WORK_ONE)
        assertEquals(liveWorkOne["authorIdentitiesJSON"], workOne["authorIdentitiesJSON"])
        assertEquals(liveWorkOne["futureWorkInsights"], workOne["futureWorkInsights"])
    }

    @Test
    fun importedBackupZipCarriesT541UnknownFieldsIntoSubsequentExportAndDropsDeletedRecords() = runTest {
        val fixture = iosT541ManifestJson()
        val zipBytes = ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST))
                zip.write(BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
            out.toByteArray()
        }

        backupRepository.importV2ZipBytes(zipBytes)
        database.workDao().deleteById(WORK_TWO)
        settingsRepository.updateReaderMode(ReaderMode.Scroll)

        val exportedZip = backupRepository.exportV2ZipBytes()
        val exportedManifestBytes = ZipInputStream(ByteArrayInputStream(exportedZip)).use { zip ->
            generateSequence { zip.nextEntry }.first { it.name == BackupPaths.MANIFEST }
            zip.readBytes()
        }
        val written = Json.parseToJsonElement(exportedManifestBytes.toString(Charsets.UTF_8)).jsonObject

        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(JsonPrimitive("scroll"), written.getValue("settings").jsonObject["readerMode"])
        assertEquals(
            fixture.getValue("settings").jsonObject["extras"],
            written.getValue("settings").jsonObject["extras"]
        )
        assertEquals(
            fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray.single().jsonObject["authorIdentitiesJSON"]
        )
        assertEquals(
            WORK_ONE,
            written.getValue("works").jsonArray.single().jsonObject["id"]?.jsonPrimitive?.content?.lowercase()
        )
    }

    @Test
    fun backupExportAfterImportedBackupPreservesUnmodeledFieldsWithoutResurrectingDeletedRecords() = runTest {
        val fixture = iosT541ManifestJson()
        val zipBytes = ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST))
                zip.write(BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
            out.toByteArray()
        }

        backupRepository.importV2ZipBytes(zipBytes, mode = BackupImportMode.REPLACE_LIBRARY)
        val storedWork = checkNotNull(database.workDao().getById(WORK_ONE)).toDomain()
        database.workDao().upsert(storedWork.copy(title = "Exported After Import").toEntity())
        database.workDao().deleteById(WORK_TWO)

        val exportedZip = backupRepository.exportV2ZipBytes()
        val exportedManifestBytes = ZipInputStream(ByteArrayInputStream(exportedZip)).use { zip ->
            generateSequence { zip.nextEntry }.first { it.name == BackupPaths.MANIFEST }
            zip.readBytes()
        }
        val written = Json.parseToJsonElement(exportedManifestBytes.toString(Charsets.UTF_8)).jsonObject

        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(fixture["futureRecords"], written["futureRecords"])
        assertEquals(
            fixture.getValue("pronunciations").jsonObject["stamps"],
            written.getValue("pronunciations").jsonObject["stamps"]
        )
        assertEquals(
            fixture.getValue("settings").jsonObject["modifiedAt"],
            written.getValue("settings").jsonObject["modifiedAt"]
        )
        assertEquals(
            fixture.getValue("settings").jsonObject["extras"],
            written.getValue("settings").jsonObject["extras"]
        )
        assertEquals(
            fixture.getValue("collections").jsonArray.single().jsonObject["lastMembershipChangedAt"],
            written.getValue("collections").jsonArray.single().jsonObject["lastMembershipChangedAt"]
        )
        assertEquals(
            fixture.getValue("readingSessions").jsonArray.single().jsonObject["activeSeconds"],
            written.getValue("readingSessions").jsonArray.single().jsonObject["activeSeconds"]
        )
        val exportedWorks = written.getValue("works").jsonArray.map { it.jsonObject }
        assertEquals(1, exportedWorks.size)
        assertEquals(JsonPrimitive("Exported After Import"), exportedWorks.single()["title"])
        assertEquals(
            fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            exportedWorks.single()["authorIdentitiesJSON"]
        )
    }

    @Test
    fun syncDownThenManualBackupExportKeepsOpaqueFields() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray())
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val exported = backupRepository.exportV2ZipBytes()
        val written = ZipInputStream(ByteArrayInputStream(exported)).use { zip ->
            generateSequence { zip.nextEntry }.first { it.name == BackupPaths.MANIFEST }
            Json.parseToJsonElement(zip.readBytes().toString(Charsets.UTF_8)).jsonObject
        }
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(fixture.getValue("settings").jsonObject["extras"], written.getValue("settings").jsonObject["extras"])
        assertEquals(fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"])
    }

    @Test
    fun backupImportThenSyncToEmptyFolderKeepsOpaqueFields() = runTest {
        val fixture = iosT541ManifestJson()
        val zipBytes = ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST))
                zip.write(BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray())
                zip.closeEntry()
            }
            out.toByteArray()
        }
        backupRepository.importV2ZipBytes(zipBytes)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(fixture["documents"], written["documents"])
        assertEquals(fixture.getValue("settings").jsonObject["modifiedAt"], written.getValue("settings").jsonObject["modifiedAt"])
        assertEquals(fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"])
    }

    @Test
    fun usableBakWinsOverOlderStoreForEveryOpaqueLevel() = runTest {
        val old = iosT541ManifestJson()
        val new = JsonObject(old + mapOf(
            "writingRecovery" to JsonPrimitive("new top level"),
            "settings" to JsonObject(old.getValue("settings").jsonObject + mapOf(
                "extras" to JsonObject(old.getValue("settings").jsonObject.getValue("extras").jsonObject +
                    mapOf("readerHighlightColor" to JsonPrimitive("blue")))
            )),
            "works" to JsonArray(listOf(JsonObject(old.getValue("works").jsonArray[0].jsonObject +
                mapOf("authorIdentitiesJSON" to JsonPrimitive("new record")))) +
                old.getValue("works").jsonArray.drop(1))
        ))
        SyncLastManifestStore(filesRoot).save(old)
        val folder = ensureKudosLibrary()
        writeChild(folder, BackupPaths.MANIFEST, "application/json", "{".toByteArray())
        writeChild(folder, BackupPaths.MANIFEST_BACKUP, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), new).toByteArray())
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(new["writingRecovery"], written["writingRecovery"])
        assertEquals(new.getValue("settings").jsonObject["extras"], written.getValue("settings").jsonObject["extras"])
        assertEquals(new.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            written.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"])
    }

    @Test
    fun disconnectWaitsForCommitAndKeepsTheStore() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray())
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val blocked = SyncRepository(context, settingsRepository, backupRepository, workFileStore,
            fontFileStore, persistenceGate, clock = { clockInstant }, beforeManifestCommit = {
                entered.complete(Unit)
                release.await()
            }, scheduleBackgroundSync = {})
        val sync = async(Dispatchers.IO) { blocked.runSync() }
        entered.await()
        val disconnect = async(Dispatchers.IO) { blocked.disconnect() }
        assertNull(withTimeoutOrNull(100) { disconnect.await() })
        release.complete(Unit)
        assertTrue(sync.await() is SyncResult.Success)
        disconnect.await()
        assertNull(settingsRepository.settings.first().sync.folderUri)
        assertTrue(Files.isRegularFile(filesRoot.resolve("sync-last-manifest.json")))
    }

    @Test
    fun changeFolderWaitsForCommitAndKeepsTheStore() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray())
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val blocked = SyncRepository(context, settingsRepository, backupRepository, workFileStore,
            fontFileStore, persistenceGate, clock = { clockInstant }, beforeManifestCommit = {
                entered.complete(Unit)
                release.await()
            }, scheduleBackgroundSync = {})
        val sync = async(Dispatchers.IO) { blocked.runSync() }
        entered.await()
        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("Other")!!
        val newFolder = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(context.packageName, newFolder,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        val change = async(Dispatchers.IO) { blocked.connect(newFolder) }
        assertNull(withTimeoutOrNull(100) { change.await() })
        release.complete(Unit)
        assertTrue(sync.await() is SyncResult.Success)
        change.await()
        assertEquals(newFolder, blocked.getSyncFolderUri())
        assertTrue(Files.isRegularFile(filesRoot.resolve("sync-last-manifest.json")))
    }

    @Test
    fun mergeImportNewerStampRemovesExtrasEntryAndRecordKey() = runTest {
        val fixture = iosT541ManifestJson()
        backupRepository.importV2ZipBytes(zipManifest(fixture), mode = BackupImportMode.MERGE)
        val settings = fixture.getValue("settings").jsonObject
        val extras = settings.getValue("extras").jsonObject
        val modifiedAt = settings.getValue("modifiedAt").jsonObject
        val works = fixture.getValue("works").jsonArray.map { it.jsonObject }.toMutableList()
        works[0] = JsonObject(
            works[0].filterKeys { it != "authorIdentitiesJSON" } + mapOf(
                "lastModifiedAt" to JsonPrimitive("2026-06-26T18:00:00.000Z")
            )
        )
        val newer = JsonObject(
            fixture.filterKeys { it != "writingRecovery" && it != "settings" && it != "works" } + mapOf(
                "settings" to JsonObject(
                    settings + mapOf(
                        "modifiedAt" to JsonObject(
                            modifiedAt + mapOf(
                                "keepScreenAwake" to JsonPrimitive("2026-06-26T18:00:00.000Z"),
                                "[\"ao3CommentDrafts\",\"42\"]" to JsonPrimitive("2026-06-26T18:00:00.000Z")
                            )
                        ),
                        "extras" to JsonObject(
                            extras.filterKeys {
                                it != "keepScreenAwake" && it != "readerHighlightColor" && it != "ao3CommentDrafts"
                            }
                        )
                    )
                ),
                "works" to JsonArray(works)
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(newer), mode = BackupImportMode.MERGE)

        val written = exportedManifest()
        val writtenExtras = written.getValue("settings").jsonObject.getValue("extras").jsonObject
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(JsonPrimitive("yellow"), writtenExtras["readerHighlightColor"])
        assertFalse("keepScreenAwake" in writtenExtras)
        val drafts = writtenExtras["ao3CommentDrafts"]?.jsonObject?.get("map")?.jsonObject
        assertTrue(drafts == null || "42" !in drafts)
        val work = workJson(written, WORK_ONE)
        assertFalse("authorIdentitiesJSON" in work)
        assertEquals(
            fixture.getValue("works").jsonArray[0].jsonObject["futureWorkInsights"],
            work["futureWorkInsights"]
        )
    }

    @Test
    fun mergeImportOlderStampDoesNotOverwriteNewerStoredValue() = runTest {
        val fixture = iosT541ManifestJson()
        backupRepository.importV2ZipBytes(zipManifest(fixture), mode = BackupImportMode.REPLACE_LIBRARY)
        val settings = fixture.getValue("settings").jsonObject
        val works = fixture.getValue("works").jsonArray.map { it.jsonObject }.toMutableList()
        works[0] = JsonObject(
            works[0] + mapOf(
                "lastModifiedAt" to JsonPrimitive("2026-06-26T08:00:00.000Z"),
                "authorIdentitiesJSON" to JsonPrimitive("older")
            )
        )
        val older = JsonObject(
            fixture.filterKeys { it != "writingRecovery" && it != "settings" && it != "works" } + mapOf(
                "settings" to JsonObject(
                    settings + mapOf(
                        "modifiedAt" to JsonObject(
                            settings.getValue("modifiedAt").jsonObject + mapOf(
                                "keepScreenAwake" to JsonPrimitive("2026-06-26T08:00:00.000Z")
                            )
                        ),
                        "extras" to JsonObject(
                            settings.getValue("extras").jsonObject + mapOf(
                                "keepScreenAwake" to JsonPrimitive(false)
                            )
                        )
                    )
                ),
                "works" to JsonArray(works)
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(older), mode = BackupImportMode.MERGE)

        val written = exportedManifest()
        val writtenExtras = written.getValue("settings").jsonObject.getValue("extras").jsonObject
        assertEquals(JsonPrimitive(true), writtenExtras["keepScreenAwake"])
        assertEquals(fixture["writingRecovery"], written["writingRecovery"])
        assertEquals(
            fixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            workJson(written, WORK_ONE)["authorIdentitiesJSON"]
        )
    }

    @Test
    fun primaryManifestPrefersNewerExportedAtThenMtimeThenLiveName() {
        val older = JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("older-export")
            )
        )
        val newer = JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("newer-export")
            )
        )
        val byExport = foldManifestCopies(
            listOf(
                RawManifestCopy(older, modifiedAtMillis = 9_000, liveName = true),
                RawManifestCopy(newer, modifiedAtMillis = 1, liveName = false)
            )
        )
        assertEquals(JsonPrimitive("newer-export"), byExport!!["writingRecovery"])

        val live = JsonObject(mapOf("writingRecovery" to JsonPrimitive("live")))
        val conflict = JsonObject(mapOf("writingRecovery" to JsonPrimitive("conflict")))
        val byMtime = foldManifestCopies(
            listOf(
                RawManifestCopy(live, modifiedAtMillis = 1_000, liveName = true),
                RawManifestCopy(conflict, modifiedAtMillis = 5_000, liveName = false)
            )
        )
        assertEquals(JsonPrimitive("conflict"), byMtime!!["writingRecovery"])

        val byName = foldManifestCopies(
            listOf(
                RawManifestCopy(conflict, modifiedAtMillis = 5_000, liveName = false),
                RawManifestCopy(live, modifiedAtMillis = 5_000, liveName = true)
            )
        )
        assertEquals(JsonPrimitive("live"), byName!!["writingRecovery"])
    }

    @Test
    fun changeFolderToEmptyFolderKeepsFolderASyncedDataOutAndPendingImportIn() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray()
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val importedWorkId = "99999999-0000-4000-8000-000000000081"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(importedWorkId)), mode = BackupImportMode.MERGE)

        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("EmptyOther")!!
        val newFolder = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(
            context.packageName,
            newFolder,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(newFolder)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val library = DocumentFile.fromTreeUri(context, newFolder)!!.findFile("KudosLibrary")
            ?: error("KudosLibrary missing in the new folder")
        val written = Json.parseToJsonElement(
            readDocument(library.findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        // Folder A's synced pass-through data is folder-scoped: it stays out of an empty Folder B.
        assertNull(written["writingRecovery"])
        assertNull(written.getValue("settings").jsonObject["extras"]?.jsonObject?.get("readerHighlightColor"))
        assertNull(workJson(written, WORK_ONE)["authorIdentitiesJSON"])
        // The manual import is this device's own and still reaches it.
        assertEquals(
            listOf("notes/backup-one.json"),
            written.getValue("documents").jsonArray.map { it.jsonObject.getValue("name").jsonPrimitive.content }
        )
        assertEquals(
            JsonPrimitive("[{\"username\":\"ada\"}]"),
            workJson(written, importedWorkId)["authorIdentitiesJSON"]
        )
    }

    @Test
    fun sharedLockKeepsAnInFlightSaveFromLandingAfterClear() = runTest {
        val dir = Files.createTempDirectory("kudos-a541-lock")
        val first = SyncLastManifestStore(dir)
        val second = SyncLastManifestStore(dir)
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        SyncLastManifestStore.beforeFilePublish = { path ->
            if (path == first.file) {
                entered.complete(Unit)
                runBlocking { release.await() }
            }
        }
        try {
            val save = async(Dispatchers.IO) {
                first.save(JsonObject(mapOf("kept" to JsonPrimitive("yes"))))
            }
            entered.await()
            val clear = async(Dispatchers.IO) { second.clear() }
            assertNull(withTimeoutOrNull(100) { clear.await() })
            release.complete(Unit)
            save.await()
            clear.await()
            assertFalse(Files.exists(first.file))
        } finally {
            SyncLastManifestStore.beforeFilePublish = null
            dir.toFile().deleteRecursively()
        }
    }

    @Test
    fun offsetIso8601TimestampsRankAndCompareLikeUtcInstants() {
        val olderUtc = JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("older-utc"),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive("2026-06-26T12:00:00.000Z"))
                        ),
                        "extras" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive(false)))
                    )
                )
            )
        )
        val newerOffset = JsonObject(
            mapOf(
                // 12:00-02:00 == 14:00Z, strictly newer than 12:00Z.
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00-02:00"),
                "writingRecovery" to JsonPrimitive("newer-offset"),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive("2026-06-26T12:00:00-02:00"))
                        ),
                        "extras" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive(true)))
                    )
                )
            )
        )
        val folded = foldManifestCopies(
            listOf(
                RawManifestCopy(olderUtc, modifiedAtMillis = 9_000, liveName = true),
                RawManifestCopy(newerOffset, modifiedAtMillis = 1_000, liveName = false)
            )
        )!!
        assertEquals(JsonPrimitive("newer-offset"), folded["writingRecovery"])
        assertEquals(
            JsonPrimitive(true),
            folded.getValue("settings").jsonObject.getValue("extras").jsonObject["keepScreenAwake"]
        )
    }

    @Test
    fun readingQueuesAndFallbackRecordStampsGovernRemovalsAndOlderCopies() {
        val olderQueue = JsonObject(
            mapOf(
                "id" to JsonPrimitive(QUEUE_ONE),
                "kindRaw" to JsonPrimitive("savedForLater"),
                "dateUpdated" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
                "futureField" to JsonPrimitive("stale")
            )
        )
        val newerQueueWithoutExtra = JsonObject(
            mapOf(
                "id" to JsonPrimitive(QUEUE_ONE),
                "kindRaw" to JsonPrimitive("savedForLater"),
                "dateUpdated" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
                "lastMembershipChangedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z")
            )
        )
        val olderCollection = JsonObject(
            mapOf(
                "id" to JsonPrimitive(COLLECTION_ONE),
                "dateAdded" to JsonPrimitive("2026-06-26T09:00:00.000Z"),
                "futureCollectionKey" to JsonPrimitive("old")
            )
        )
        val newerCollection = JsonObject(
            mapOf(
                "id" to JsonPrimitive(COLLECTION_ONE),
                "dateAdded" to JsonPrimitive("2026-06-26T12:00:00.000Z")
            )
        )
        val olderMembership = JsonObject(
            mapOf(
                "id" to JsonPrimitive(MEMBERSHIP_ONE),
                "queuedAt" to JsonPrimitive("2026-06-26T09:00:00.000Z"),
                "futureField" to JsonPrimitive("old")
            )
        )
        val newerMembership = JsonObject(
            mapOf(
                "id" to JsonPrimitive(MEMBERSHIP_ONE),
                "queuedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z")
            )
        )
        val olderAnnotation = JsonObject(
            mapOf(
                "id" to JsonPrimitive(ANNOTATION_ONE),
                "createdAt" to JsonPrimitive("2026-06-26T09:00:00.000Z"),
                "futureField" to JsonPrimitive("old")
            )
        )
        val newerAnnotation = JsonObject(
            mapOf(
                "id" to JsonPrimitive(ANNOTATION_ONE),
                "createdAt" to JsonPrimitive("2026-06-26T12:00:00.000Z")
            )
        )

        val newerManifest = JsonObject(
            mapOf(
                "readingQueues" to JsonArray(listOf(newerQueueWithoutExtra)),
                "collections" to JsonArray(listOf(newerCollection)),
                "readingQueueMemberships" to JsonArray(listOf(newerMembership)),
                "annotations" to JsonArray(listOf(newerAnnotation))
            )
        )
        val olderManifest = JsonObject(
            mapOf(
                "readingQueues" to JsonArray(listOf(olderQueue)),
                "collections" to JsonArray(listOf(olderCollection)),
                "readingQueueMemberships" to JsonArray(listOf(olderMembership)),
                "annotations" to JsonArray(listOf(olderAnnotation))
            )
        )

        val newerPrimary = mergeFallbackManifestJson(newerManifest, olderManifest)!!
        assertFalse("futureField" in newerPrimary.getValue("readingQueues").jsonArray.single().jsonObject)
        assertFalse("futureCollectionKey" in newerPrimary.getValue("collections").jsonArray.single().jsonObject)
        assertFalse("futureField" in newerPrimary.getValue("readingQueueMemberships").jsonArray.single().jsonObject)
        assertFalse("futureField" in newerPrimary.getValue("annotations").jsonArray.single().jsonObject)

        val olderPrimary = mergeFallbackManifestJson(olderManifest, newerManifest)!!
        assertFalse("futureField" in olderPrimary.getValue("readingQueues").jsonArray.single().jsonObject)
        assertFalse("futureCollectionKey" in olderPrimary.getValue("collections").jsonArray.single().jsonObject)
        assertFalse("futureField" in olderPrimary.getValue("readingQueueMemberships").jsonArray.single().jsonObject)
        assertFalse("futureField" in olderPrimary.getValue("annotations").jsonArray.single().jsonObject)
    }

    @Test
    fun recordImportedManifestPrefersNewerExportedAtAndFavorsImportOnTieOrMissing() = runTest {
        val base = iosT541ManifestJson()
        val baseExtras = base.getValue("settings").jsonObject.getValue("extras").jsonObject
        val newerImport = JsonObject(
            base + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("newer-draft"),
                "settings" to JsonObject(
                    base.getValue("settings").jsonObject + mapOf(
                        "extras" to JsonObject(baseExtras + mapOf("readerHighlightColor" to JsonPrimitive("blue")))
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(newerImport), mode = BackupImportMode.REPLACE_LIBRARY)

        val olderImport = JsonObject(
            base + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T08:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("older-draft"),
                "settings" to JsonObject(
                    base.getValue("settings").jsonObject + mapOf(
                        "extras" to JsonObject(baseExtras + mapOf("readerHighlightColor" to JsonPrimitive("yellow")))
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(olderImport), mode = BackupImportMode.MERGE)
        val afterOlder = exportedManifest()
        assertEquals(JsonPrimitive("newer-draft"), afterOlder["writingRecovery"])
        assertEquals(
            JsonPrimitive("blue"),
            afterOlder.getValue("settings").jsonObject.getValue("extras").jsonObject["readerHighlightColor"]
        )

        val tiedImport = JsonObject(
            base + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("tied-draft")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(tiedImport), mode = BackupImportMode.MERGE)
        assertEquals(JsonPrimitive("tied-draft"), exportedManifest()["writingRecovery"])

        val undatedImport = JsonObject(
            base + mapOf(
                "exportedAt" to JsonPrimitive(""),
                "writingRecovery" to JsonPrimitive("undated-draft")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(undatedImport), mode = BackupImportMode.MERGE)
        assertEquals(JsonPrimitive("undated-draft"), exportedManifest()["writingRecovery"])

        val missingKeyResult = mergeImportedManifestJson(
            incoming = JsonObject(mapOf("writingRecovery" to JsonPrimitive("missing-key-draft"))),
            existing = newerImport
        )
        assertEquals(JsonPrimitive("missing-key-draft"), missingKeyResult["writingRecovery"])
    }

    @Test
    fun autoSyncPausedBeforeExportGateDoesNotOverwriteLastManifestStore() = runTest {
        val folderFixture = iosT541ManifestJson()
        val folderBytes = BackupJson.encodeToString(JsonObject.serializer(), folderFixture).toByteArray(Charsets.UTF_8)
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json", folderBytes)
        // Own-manifest digest skips Phase 1 import so the first gate entry is Phase 2 export.
        settingsRepository.updateSyncLastManifestDigest(BackupPaths.sha256(folderBytes))

        val replacedFixture = JsonObject(
            folderFixture + mapOf("writingRecovery" to JsonPrimitive("from-replace"))
        )
        SyncLastManifestStore(filesRoot).save(replacedFixture)

        val pausingGate = object : PersistenceGate() {
            override suspend fun <T> withLock(action: suspend () -> T): T {
                settingsRepository.updateSyncIsEnabled(false)
                return super.withLock(action)
            }
        }
        val gatedBackup = BackupRepository(
            database = database,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository,
            persistenceGate = pausingGate,
            clock = { clockInstant },
            uuidFactory = { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" },
            appVersion = "test"
        )
        val gatedSync = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = gatedBackup,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = pausingGate,
            clock = { clockInstant },
            scheduleBackgroundSync = {}
        )

        val result = gatedSync.runAutoSync()
        assertTrue(result is SyncResult.Success)
        assertEquals(
            JsonPrimitive("from-replace"),
            SyncLastManifestStore(filesRoot).load()!!["writingRecovery"]
        )
    }

    @Test
    fun unreadableManifestWithoutBakInNewFolderDoesNotTakePreviousFoldersStore() = runTest {
        val oldFixture = iosT541ManifestJson()
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), oldFixture).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("DamagedOther")!!
        val otherKudos = other.createDirectory("KudosLibrary")!!
        writeChild(otherKudos, BackupPaths.MANIFEST, "application/json", """{"version":8,"works":[""".toByteArray())
        val newFolder = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(
            context.packageName,
            newFolder,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(newFolder)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = Json.parseToJsonElement(
            readDocument(otherKudos.findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertFalse("writingRecovery" in written)
        assertFalse("documents" in written)
        assertNull(written.getValue("settings").jsonObject["extras"])
    }

    @Test
    fun legacyKudosBackupReplacesPreviousStoreInsteadOfMergingOverIt() = runTest {
        val oldFixture = JsonObject(
            iosT541ManifestJson() + mapOf("oldFolderOnlyKey" to JsonPrimitive("must-not-leak"))
        )
        SyncLastManifestStore(filesRoot).save(oldFixture)

        val zipManifest = iosT541ManifestJson()
        val root = DocumentFile.fromTreeUri(context, treeUri)!!
        writeChild(root, "Kudos.kudosbackup", "application/zip", zipManifest(zipManifest))

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertFalse("oldFolderOnlyKey" in written)
        assertEquals(zipManifest["writingRecovery"], written["writingRecovery"])
    }

    @Test
    fun connectedBackupImportKeepsPendingOverlayForNextSyncAndFollowsItIntoAnotherFolder() = runTest {
        val folderFixture = iosT541ManifestJson()
        val initialFolder = JsonObject(
            folderFixture.filterKeys { it != "documents" } + mapOf(
                "works" to JsonArray(listOf(folderFixture.getValue("works").jsonArray[0]))
            )
        )
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), initialFolder).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val extraWorkId = "99999999-0000-4000-8000-000000000077"
        val importedBackup = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z"),
                "documents" to folderFixture.getValue("documents"),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive("2026-06-26T14:00:00.000Z"))
                        ),
                        "extras" to JsonObject(
                            mapOf("keepScreenAwake" to JsonPrimitive(false))
                        )
                    )
                ),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(extraWorkId),
                                "title" to JsonPrimitive("Imported While Connected"),
                                "author" to JsonPrimitive("Carol"),
                                "sourceURL" to JsonPrimitive("https://archiveofourown.org/works/820077"),
                                "ao3WorkID" to JsonPrimitive(820077),
                                "dateAdded" to JsonPrimitive("2026-06-26T13:00:00.000Z"),
                                "lastModifiedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z"),
                                "isSaved" to JsonPrimitive(true),
                                "authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"carol\"}]"),
                                "futureWorkInsights" to JsonObject(mapOf("streak" to JsonPrimitive(9)))
                            )
                        )
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(importedBackup), mode = BackupImportMode.MERGE)

        clockInstant = FIXED_CLOCK.plusSeconds(180)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val synced = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(folderFixture["documents"], synced["documents"])
        assertEquals(
            JsonPrimitive(false),
            synced.getValue("settings").jsonObject.getValue("extras").jsonObject["keepScreenAwake"]
        )
        assertEquals(
            folderFixture.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            workJson(synced, WORK_ONE)["authorIdentitiesJSON"]
        )
        val syncedExtraWork = workJson(synced, extraWorkId)
        assertEquals(JsonPrimitive("[{\"username\":\"carol\"}]"), syncedExtraWork["authorIdentitiesJSON"])
        assertEquals(JsonObject(mapOf("streak" to JsonPrimitive(9))), syncedExtraWork["futureWorkInsights"])

        // A manual import belongs to this device: it is untagged and follows the library into
        // whichever folder syncs next, so a folder switch must not drop its extra fields.
        val secondImport = JsonObject(
            importedBackup + mapOf("exportedAt" to JsonPrimitive("2026-06-26T15:00:00.000Z"))
        )
        backupRepository.importV2ZipBytes(zipManifest(secondImport), mode = BackupImportMode.MERGE)
        assertNull(
            SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE).taggedFolderUri()
        )

        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("FolderB")!!
        val otherKudos = other.createDirectory("KudosLibrary")!!
        val folderBManifest = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T16:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("folder-b-only")
            )
        )
        writeChild(
            otherKudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), folderBManifest).toByteArray(Charsets.UTF_8)
        )
        val folderBUri = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(
            context.packageName,
            folderBUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(folderBUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterB = Json.parseToJsonElement(
            readDocument(otherKudos.findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(JsonPrimitive("folder-b-only"), afterB["writingRecovery"])
        assertEquals(folderFixture["documents"], afterB["documents"])
        assertEquals(
            JsonPrimitive("[{\"username\":\"carol\"}]"),
            workJson(afterB, extraWorkId)["authorIdentitiesJSON"]
        )
    }

    /** Review 7 scenario A: import under Folder A, disconnect, connect Folder B. */
    @Test
    fun importUnderFolderAThenDisconnectThenConnectFolderBKeepsImportedFields() = runTest {
        val workId = "99999999-0000-4000-8000-000000000079"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        syncRepository.disconnect()

        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("FolderBScenarioA")!!
        val otherKudos = other.createDirectory("KudosLibrary")!!
        writeChild(
            otherKudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(
                JsonObject.serializer(),
                JsonObject(
                    mapOf(
                        "version" to JsonPrimitive(8),
                        "exportedAt" to JsonPrimitive("2026-06-26T11:00:00.000Z"),
                        "writingRecovery" to JsonPrimitive("folder-b")
                    )
                )
            ).toByteArray(Charsets.UTF_8)
        )
        val folderBUri = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(
            context.packageName,
            folderBUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(folderBUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val afterB = Json.parseToJsonElement(
            readDocument(otherKudos.findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(
            JsonPrimitive("[{\"username\":\"ada\"}]"),
            workJson(afterB, workId)["authorIdentitiesJSON"]
        )
        assertEquals(
            "notes/backup-one.json",
            afterB.getValue("documents").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content
        )
    }

    @Test
    fun olderPendingImportDoesNotReplaceNewerFolderSnapshot() = runTest {
        val base = iosT541ManifestJson()
        val baseSettings = base.getValue("settings").jsonObject
        val folderDocuments = JsonArray(
            listOf(
                JsonObject(
                    mapOf(
                        "name" to JsonPrimitive("folder-doc"),
                        "data" to JsonPrimitive("Zm9sZGVy")
                    )
                )
            )
        )
        val folderManifest = JsonObject(
            base + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T18:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("folder-draft"),
                "documents" to folderDocuments,
                "settings" to JsonObject(
                    baseSettings + mapOf(
                        "extras" to JsonObject(
                            baseSettings.getValue("extras").jsonObject +
                                mapOf("readerHighlightColor" to JsonPrimitive("blue"))
                        )
                    )
                )
            )
        )
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), folderManifest).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val olderImport = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T08:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("old-draft"),
                "importOnly" to JsonPrimitive("kept"),
                "documents" to JsonArray(
                    listOf(JsonObject(mapOf("name" to JsonPrimitive("old-doc"))))
                ),
                "settings" to JsonObject(
                    mapOf(
                        "extras" to JsonObject(
                            mapOf("readerHighlightColor" to JsonPrimitive("yellow"))
                        )
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(olderImport), mode = BackupImportMode.MERGE)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val synced = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(JsonPrimitive("folder-draft"), synced["writingRecovery"])
        assertEquals(
            "folder-doc",
            synced.getValue("documents").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content
        )
        assertEquals(
            JsonPrimitive("blue"),
            synced.getValue("settings").jsonObject.getValue("extras").jsonObject["readerHighlightColor"]
        )
        // Present only on the older import. Dropping the pending file would keep the folder draft too.
        assertEquals(JsonPrimitive("kept"), synced["importOnly"])
    }

    @Test
    fun pendingImportSurvivesDisconnectAndFoldsUntagged() = runTest {
        val folderManifest = JsonObject(
            iosT541ManifestJson() + mapOf("writingRecovery" to JsonPrimitive("from-folder"))
        )
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), folderManifest).toByteArray(Charsets.UTF_8)
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        syncRepository.disconnect()
        assertNull(settingsRepository.settings.first().sync.folderUri)

        val imported = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("from-import"),
                "importOnly" to JsonPrimitive("kept")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(imported), mode = BackupImportMode.MERGE)
        val pending = filesRoot.resolve(BackupRepository.PENDING_IMPORT_MANIFEST_FILE)
        assertTrue(Files.isRegularFile(pending))
        assertFalse(
            "a disconnected import must not tag the pending overlay",
            Files.exists(filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.folder"))
        )

        context.grantUriPermission(
            context.packageName,
            treeUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(treeUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val synced = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(JsonPrimitive("from-import"), synced["writingRecovery"])
        assertEquals(JsonPrimitive("kept"), synced["importOnly"])
    }

    @Test
    fun passthroughStampsIgnoreFarFutureAndCapAtExportedAt() {
        val now = Instant.parse("2021-01-01T00:00:00Z")
        val workId = "10000000-0000-4000-8000-0000000000aa"

        // June is inside the 24h window but after this file's exportedAt, so it caps to January
        // and loses to the March stamp. A missing cap would let June win.
        val cappedForged = stampedManifest(
            exportedAt = "2020-01-01T00:00:00Z",
            workStamp = "2020-06-01T00:00:00Z",
            workId = workId,
            workExtraKey = "forgedOnly",
            workExtraValue = JsonPrimitive("drop-me"),
            queueStamp = "2020-06-01T00:00:00Z",
            queueExtraKey = "forgedQueueKey",
            queueExtraValue = JsonPrimitive("drop-me"),
            awakeStamp = "2020-06-01T00:00:00Z",
            awake = false
        )
        val cappedGenuine = stampedManifest(
            exportedAt = "2020-03-01T00:00:00Z",
            workStamp = "2020-03-01T00:00:00Z",
            workId = workId,
            workExtraKey = "futureField",
            workExtraValue = JsonPrimitive("kept"),
            queueStamp = "2020-03-01T00:00:00Z",
            queueExtraKey = "futureField",
            queueExtraValue = JsonPrimitive("kept"),
            awakeStamp = "2020-03-01T00:00:00Z",
            awake = true
        )
        assertGenuineStampsWin(mergeFallbackManifestJson(cappedForged, cappedGenuine, now)!!)
        assertGenuineStampsWin(mergeFallbackManifestJson(cappedGenuine, cappedForged, now)!!)

        // exportedAt is later than the genuine stamp, so merely capping year 3000 at it would
        // still crown the forged record. Only ignoring the far-future instant lets March win.
        val futureForged = stampedManifest(
            exportedAt = "2020-06-01T00:00:00Z",
            workStamp = "3000-01-01T00:00:00Z",
            workId = workId,
            workExtraKey = "forgedOnly",
            workExtraValue = JsonPrimitive("drop-me"),
            queueStamp = "3000-01-01T00:00:00Z",
            queueExtraKey = "forgedQueueKey",
            queueExtraValue = JsonPrimitive("drop-me"),
            awakeStamp = "2020-06-01T00:00:00Z",
            awake = false
        )
        val futureGenuine = stampedManifest(
            exportedAt = "2020-03-01T00:00:00Z",
            workStamp = "2020-03-01T00:00:00Z",
            workId = workId,
            workExtraKey = "authorIdentitiesJSON",
            workExtraValue = JsonPrimitive("[{\"username\":\"real\"}]"),
            queueStamp = "2020-03-01T00:00:00Z",
            queueExtraKey = "futureField",
            queueExtraValue = JsonObject(mapOf("queueMeta" to JsonPrimitive(1))),
            awakeStamp = "2020-03-01T00:00:00Z",
            awake = true
        )
        assertFarFutureLoses(mergeFallbackManifestJson(futureForged, futureGenuine, now)!!)
        assertFarFutureLoses(mergeFallbackManifestJson(futureGenuine, futureForged, now)!!)
    }

    @Test
    fun saveWithoutFolderUriKeepsTagAndKudosBackupWritesCurrentFolder() = runTest {
        val dir = Files.createTempDirectory("kudos-a541-tag")
        try {
            val store = SyncLastManifestStore(dir)
            store.save(
                JsonObject(mapOf("writingRecovery" to JsonPrimitive("first"))),
                folderUri = "content://folder-a"
            )
            store.save(JsonObject(mapOf("writingRecovery" to JsonPrimitive("second"))))
            assertTrue(store.belongsToFolder("content://folder-a"))
            assertEquals(JsonPrimitive("second"), store.load()!!["writingRecovery"])
        } finally {
            dir.toFile().deleteRecursively()
        }

        SyncLastManifestStore(filesRoot).save(
            JsonObject(iosT541ManifestJson() + mapOf("oldFolderOnlyKey" to JsonPrimitive("must-not-leak"))),
            folderUri = "content://previous"
        )
        val root = DocumentFile.fromTreeUri(context, treeUri)!!
        writeChild(root, "Kudos.kudosbackup", "application/zip", zipManifest(iosT541ManifestJson()))
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = SyncLastManifestStore(filesRoot)
        val current = syncRepository.getSyncFolderUri()!!.toString()
        assertTrue(after.belongsToFolder(current))
        assertFalse(after.belongsToFolder("content://previous"))
    }

    @Test
    fun failedPublishWhileClearingStaleTagLeavesOldBodyAndTagTogether() = runTest {
        val dir = Files.createTempDirectory("kudos-a541-tag-crash")
        try {
            val store = SyncLastManifestStore(dir)
            store.save(
                JsonObject(mapOf("writingRecovery" to JsonPrimitive("folder-a-body"))),
                folderUri = "content://folder-a"
            )
            SyncLastManifestStore.beforeFilePublish = { throw java.io.IOException("simulated crash before publish") }
            val thrown = try {
                store.save(
                    JsonObject(mapOf("writingRecovery" to JsonPrimitive("disconnected-body"))),
                    clearStaleFolderTag = true
                )
                false
            } catch (_: java.io.IOException) {
                true
            }
            assertTrue(thrown)
            // One file, so the failed publish cannot leave the old body untagged or a new body tagged.
            assertEquals(JsonPrimitive("folder-a-body"), store.load()!!["writingRecovery"])
            assertTrue(store.belongsToFolder("content://folder-a"))
            SyncLastManifestStore.beforeFilePublish = null
            store.save(
                JsonObject(mapOf("writingRecovery" to JsonPrimitive("disconnected-body"))),
                clearStaleFolderTag = true
            )
            assertEquals(JsonPrimitive("disconnected-body"), store.load()!!["writingRecovery"])
            assertNull(store.taggedFolderUri())
        } finally {
            SyncLastManifestStore.beforeFilePublish = null
            dir.toFile().deleteRecursively()
        }
    }

    @Test
    fun legacyFileAndFolderPairIsReadAndFolderFileDeletedAfterSingleFileSave() = runTest {
        val dir = Files.createTempDirectory("kudos-a541-legacy-pair")
        try {
            Files.write(dir.resolve("sync-last-manifest.json"), "{\"writingRecovery\":\"legacy\"}".toByteArray())
            Files.write(dir.resolve("sync-last-manifest.json.folder"), "content://folder-a".toByteArray())
            val store = SyncLastManifestStore(dir)
            assertEquals(JsonPrimitive("legacy"), store.load()!!["writingRecovery"])
            assertTrue(store.belongsToFolder("content://folder-a"))

            SyncLastManifestStore.beforeFilePublish = { throw java.io.IOException("simulated crash") }
            runCatching { store.save(JsonObject(mapOf("k" to JsonPrimitive("v")))) }
            SyncLastManifestStore.beforeFilePublish = null
            assertTrue("a failed publish keeps the legacy tag", Files.exists(dir.resolve("sync-last-manifest.json.folder")))

            store.save(JsonObject(mapOf("k" to JsonPrimitive("v"))))
            assertFalse(Files.exists(dir.resolve("sync-last-manifest.json.folder")))
            assertTrue(store.belongsToFolder("content://folder-a"))
            assertEquals(JsonPrimitive("v"), store.load()!!["k"])
        } finally {
            SyncLastManifestStore.beforeFilePublish = null
            dir.toFile().deleteRecursively()
        }
    }

    @Test
    fun leftoverLegacySidecarNeverRetagsAnUntaggedEnvelope() = runTest {
        val dir = Files.createTempDirectory("kudos-a541-sidecar")
        try {
            val store = SyncLastManifestStore(dir)
            store.save(JsonObject(mapOf("k" to JsonPrimitive("new"))), clearStaleFolderTag = true)
            // The crash window: the new envelope moved in, the old sidecar was not deleted yet.
            Files.write(dir.resolve("sync-last-manifest.json.folder"), "content://folder-a".toByteArray())
            assertNull(store.taggedFolderUri())
            assertFalse(store.belongsToFolder("content://folder-a"))
            store.save(JsonObject(mapOf("k" to JsonPrimitive("newer"))))
            assertNull("a default save must not copy the sidecar's tag in", store.taggedFolderUri())
        } finally {
            dir.toFile().deleteRecursively()
        }
    }

    @Test
    fun legacyTaggedPendingOverlayIsAdoptedUntaggedByNextImportKeepingItsData() = runTest {
        val workId = "99999999-0000-4000-8000-000000000080"
        val pending = SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE)
        Files.write(
            filesRoot.resolve(BackupRepository.PENDING_IMPORT_MANIFEST_FILE),
            BackupJson.encodeToString(JsonObject.serializer(), backupOneOverlay(workId)).toByteArray()
        )
        Files.write(
            filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.folder"),
            "content://old-folder".toByteArray()
        )
        val backupTwo = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("backup-two-draft")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(backupTwo), mode = BackupImportMode.MERGE)
        assertNull(pending.taggedFolderUri())
        assertFalse(Files.exists(filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.folder")))
        assertEquals(
            JsonPrimitive("[{\"username\":\"ada\"}]"),
            workJson(pending.load()!!, workId)["authorIdentitiesJSON"]
        )
    }

    @Test
    fun disconnectedImportAfterUnsyncedConnectedImportDropsStaleFolderTag() = runTest {
        val pendingStore = SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE)

        // 1. A connected Merge under Folder A writes the pending overlay untagged.
        val connectedAImport = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("folder-a-unsynced")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(connectedAImport), mode = BackupImportMode.MERGE)
        assertNull(pendingStore.taggedFolderUri())
        assertNotNull(pendingStore.load())

        // 2. Disconnect without syncing, then perform a disconnected Merge of a new backup.
        syncRepository.disconnect()
        val extraWorkId = "99999999-0000-4000-8000-000000000088"
        val disconnectedImport = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("disconnected-draft"),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(extraWorkId),
                                "title" to JsonPrimitive("Disconnected Work"),
                                "author" to JsonPrimitive("Dana"),
                                "sourceURL" to JsonPrimitive("https://archiveofourown.org/works/820088"),
                                "ao3WorkID" to JsonPrimitive(820088),
                                "dateAdded" to JsonPrimitive("2026-06-26T11:00:00.000Z"),
                                "lastModifiedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                                "isSaved" to JsonPrimitive(true),
                                "authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"dana\"}]")
                            )
                        )
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(disconnectedImport), mode = BackupImportMode.MERGE)
        assertNull("the Merge half leaves the pending overlay untagged", pendingStore.taggedFolderUri())

        // 3. Connecting Folder B must retain the untagged disconnected overlay and fold it on sync.
        val other = DocumentFile.fromTreeUri(context, treeUri)!!.createDirectory("FolderBForDisconnected")!!
        val otherKudos = other.createDirectory("KudosLibrary")!!
        val folderBManifest = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T11:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("folder-b-older")
            )
        )
        writeChild(
            otherKudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), folderBManifest).toByteArray(Charsets.UTF_8)
        )
        val folderBUri = android.provider.DocumentsContract.buildTreeDocumentUri(
            FakeTempDocumentsProvider.AUTHORITY,
            android.provider.DocumentsContract.getDocumentId(other.uri)
        )
        context.grantUriPermission(
            context.packageName,
            folderBUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(folderBUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val syncedB = Json.parseToJsonElement(
            readDocument(otherKudos.findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(JsonPrimitive("disconnected-draft"), syncedB["writingRecovery"])
        assertEquals(
            JsonPrimitive("[{\"username\":\"dana\"}]"),
            workJson(syncedB, extraWorkId)["authorIdentitiesJSON"]
        )

        // 4. Connected Replace followed by disconnect + disconnected Replace also drops the stale tag.
        backupRepository.importV2ZipBytes(
            zipManifest(
                JsonObject(
                    connectedAImport + mapOf(
                        "documents" to JsonArray(listOf(JsonObject(mapOf("name" to JsonPrimitive("old-only")))))
                    )
                )
            ),
            mode = BackupImportMode.MERGE
        )
        assertNull(pendingStore.taggedFolderUri())
        syncRepository.disconnect()
        val replacement = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T13:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("disconnected-replace")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(replacement), mode = BackupImportMode.REPLACE_LIBRARY)
        assertNull(pendingStore.taggedFolderUri())
        // Replace stores the replacement alone: a merge with the old overlay would keep old-only.
        assertEquals(replacement, pendingStore.load())
    }

    @Test
    fun disconnectedMergeKeepsAuthorIdentitiesAndDocumentsTheNewerFileLacks() = runTest {
        val workId = "99999999-0000-4000-8000-000000000077"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        syncRepository.disconnect()

        val backupTwo = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("backup-two-draft")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(backupTwo), mode = BackupImportMode.MERGE)
        assertFalse(
            Files.exists(filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.folder"))
        )

        val folderManifest = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T11:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("folder-without-backup-one")
            )
        )
        writeChild(
            ensureKudosLibrary(),
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), folderManifest).toByteArray(Charsets.UTF_8)
        )
        context.grantUriPermission(
            context.packageName,
            treeUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(treeUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val synced = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(
            JsonPrimitive("[{\"username\":\"ada\"}]"),
            workJson(synced, workId)["authorIdentitiesJSON"]
        )
        assertTrue("documents from Backup 1 must survive a newer file that lacks them", "documents" in synced)
        assertEquals(
            "notes/backup-one.json",
            synced.getValue("documents").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content
        )
    }

    @Test
    fun disconnectedImportSaveDoesNotEmptyPendingBeforePublish() = runTest {
        val workId = "99999999-0000-4000-8000-000000000078"
        val pendingFile = filesRoot.resolve(BackupRepository.PENDING_IMPORT_MANIFEST_FILE)
        val pendingStore = SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE)
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        syncRepository.disconnect()

        val backupTwo = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("backup-two-draft")
            )
        )
        assertPendingBodySurvivesUntilSave(pendingFile, workId) {
            backupRepository.importV2ZipBytes(zipManifest(backupTwo), mode = BackupImportMode.MERGE)
        }

        settingsRepository.updateSyncFolderUri(treeUri.toString())
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        syncRepository.disconnect()
        // Replace clears the old overlays before its transaction and writes the incoming manifest
        // alone afterwards: nothing of the old pending body may be merged into it.
        val replacement = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T13:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("disconnected-replace")
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(replacement), mode = BackupImportMode.REPLACE_LIBRARY)
        assertEquals(replacement, pendingStore.load())
        assertNull(pendingStore.taggedFolderUri())
    }

    private fun failOverlayPublishes(block: () -> Unit) {
        SyncLastManifestStore.beforeFilePublish = { throw java.io.IOException("killed before the overlay is written") }
        try { block() } finally { SyncLastManifestStore.beforeFilePublish = null }
    }

    @Test
    fun replaceKilledBetweenCommitAndOverlayWriteExportsNoOldLibraryOpaqueData() = runTest {
        val workId = "99999999-0000-4000-8000-000000000091"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        val replacement = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-28T00:00:00.000Z"),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            backupOneOverlay(workId).getValue("works").jsonArray.single().jsonObject +
                                mapOf("authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"bob\"}]"))
                        )
                    )
                )
            )
        )
        failOverlayPublishes {
            runBlocking { backupRepository.importV2ZipBytes(zipManifest(replacement), mode = BackupImportMode.REPLACE_LIBRARY) }
        }
        val exported = exportedManifest()
        assertNull("the old library's documents must not be exported", exported["documents"])
        assertTrue(Files.list(filesRoot).use { it.noneMatch { p -> p.fileName.toString().endsWith(".replace-aside") } })
        assertNull(workJson(exported, workId)["authorIdentitiesJSON"])
    }

    @Test
    fun anOverlayWriteFailureAfterReplaceCommitsStillReportsTheReplace() = runTest {
        val workId = "99999999-0000-4000-8000-000000000092"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        val empty = JsonObject(mapOf("version" to JsonPrimitive(8), "exportedAt" to JsonPrimitive("2026-06-28T00:00:00.000Z")))
        var summary: BackupRestoreSummary? = null
        failOverlayPublishes {
            summary = runBlocking { backupRepository.importV2ZipBytes(zipManifest(empty), mode = BackupImportMode.REPLACE_LIBRARY) }
        }
        assertEquals(true, database.workDao().getById(workId)!!.isDeleted)
        assertTrue(summary!!.opaqueDataNotSaved)
        assertTrue(summary!!.toUserMessage().contains("some extra iOS data could not be kept"))
    }

    @Test
    fun aNewerPendingTypedEditKeepsAnOpaqueFieldOnlyTheLiveManifestHolds() = runTest {
        val fixture = iosT541ManifestJson()
        writeChild(
            ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray()
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val work = fixture.getValue("works").jsonArray[0].jsonObject
        val edited = JsonObject(
            work.filterKeys { it != "authorIdentitiesJSON" } +
                mapOf("title" to JsonPrimitive("Edited"), "lastModifiedAt" to JsonPrimitive("2026-06-27T11:00:00.000Z"))
        )
        val backup = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-27T12:00:00.000Z"),
                "works" to JsonArray(listOf(edited))
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(backup), mode = BackupImportMode.MERGE)
        clockInstant = FIXED_CLOCK.plusSeconds(600)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val published = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(work["authorIdentitiesJSON"], workJson(published, WORK_ONE)["authorIdentitiesJSON"])
    }

    @Test
    fun aSyncThatFailsItsFinalFolderCheckLeavesTheRawCacheAlone() = runTest {
        val fixture = iosT541ManifestJson()
        SyncLastManifestStore(filesRoot).save(JsonObject(mapOf("writingRecovery" to JsonPrimitive("cached"))))
        writeChild(
            ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), fixture).toByteArray()
        )
        val failing = SyncRepository(
            context, settingsRepository, backupRepository, workFileStore,
            fontFileStore, persistenceGate, clock = { clockInstant }, beforeManifestCommit = {
                writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json", "{}".toByteArray())
            }
        )
        assertTrue(failing.runSync() is SyncResult.Error)
        assertEquals(JsonPrimitive("cached"), SyncLastManifestStore(filesRoot).load()!!["writingRecovery"])
    }

    private val emptyReplacement = JsonObject(
        mapOf("version" to JsonPrimitive(8), "exportedAt" to JsonPrimitive("2026-06-28T00:00:00.000Z"))
    )

    private fun assertOldOverlaysStillExported(exported: JsonObject) {
        assertEquals(
            "notes/backup-one.json",
            exported.getValue("documents").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content
        )
    }

    @Test
    fun aReplaceThatFailsBeforeRoomPutsBothOverlaysBack() = runTest {
        val workId = "99999999-0000-4000-8000-000000000093"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        val pendingBefore = SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE).load()
        val exportBefore = SyncLastManifestStore(filesRoot).load()
        BackupRepository.afterOverlaysStaged = { throw java.io.IOException("Room failed") }
        try {
            assertTrue(
                runCatching {
                    backupRepository.importV2ZipBytes(zipManifest(emptyReplacement), mode = BackupImportMode.REPLACE_LIBRARY)
                }.isFailure
            )
        } finally {
            BackupRepository.afterOverlaysStaged = null
        }
        assertEquals(false, database.workDao().getById(workId)!!.isDeleted)
        assertOldOverlaysStillExported(exportedManifest())
        // Both stores, not just the one manual export reads.
        assertEquals(exportBefore, SyncLastManifestStore(filesRoot).load())
        assertEquals(pendingBefore, SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE).load())
        assertTrue(Files.list(filesRoot).use { it.noneMatch { p -> p.fileName.toString().endsWith(".replace-aside") } })
    }

    @Test
    fun aReplaceWhoseLegacySidecarCannotBeSetAsideRestoresTheBody() = runTest {
        val workId = "99999999-0000-4000-8000-000000000095"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        // The export overlay is a legacy pair: body plus a .folder sidecar.
        val body = BackupJson.encodeToString(JsonObject.serializer(), backupOneOverlay(workId)).toByteArray()
        Files.write(filesRoot.resolve("sync-last-manifest.json"), body)
        Files.write(filesRoot.resolve("sync-last-manifest.json.folder"), "content://folder-a".toByteArray())
        val slot = filesRoot.resolve("sync-last-manifest.json.folder.replace-aside")
        Files.createDirectories(slot.resolve("blocked")).also { Files.write(it.resolve("x"), byteArrayOf(0)) }
        assertTrue(
            runCatching {
                backupRepository.importV2ZipBytes(zipManifest(emptyReplacement), mode = BackupImportMode.REPLACE_LIBRARY)
            }.isFailure
        )
        assertEquals(false, database.workDao().getById(workId)!!.isDeleted)
        val store = SyncLastManifestStore(filesRoot)
        assertTrue(store.belongsToFolder("content://folder-a"))
        assertOldOverlaysStillExported(exportedManifest())
        // A restart must not delete a stranded body: nothing was left aside.
        backupRepository.recoverInterruptedReplace()
        assertOldOverlaysStillExported(exportedManifest())
    }

    @Test
    fun pendingOpaqueDataOverTheCapIsHeldBackAndTheRestPublishes() = runTest {
        val big = { n: Int -> JsonPrimitive("x".repeat(n)) }
        val half = (BackupLimits.MAX_MANIFEST_BYTES / 2).toInt()
        writeChild(
            ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), JsonObject(iosT541ManifestJson() + mapOf("liveOpaque" to big(half)))).toByteArray()
        )
        val pending = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-27T12:00:00.000Z"),
                "importOpaque" to big(half + 1024)
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(pending), mode = BackupImportMode.MERGE)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val published = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        assertTrue(published.size <= BackupLimits.MAX_MANIFEST_BYTES)
        val json = Json.parseToJsonElement(published.toString(Charsets.UTF_8)).jsonObject
        assertNotNull(json["liveOpaque"])
        assertNull(json["importOpaque"])
        assertNotNull(SyncLastManifestStore(filesRoot, BackupRepository.PENDING_IMPORT_MANIFEST_FILE).load())
    }

    @Test
    fun aManifestOverTheCapEvenWithoutPendingDataIsStillPublished() = runTest {
        val cap = BackupLimits.MAX_MANIFEST_BYTES.toInt()
        writeChild(
            ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(
                JsonObject.serializer(),
                JsonObject(iosT541ManifestJson() + mapOf("liveOpaque" to JsonPrimitive("x".repeat(cap - 200_000))))
            ).toByteArray()
        )
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val stored = checkNotNull(database.workDao().getById(WORK_ONE)).toDomain()
        repeat(3) { i ->
            database.workDao().upsert(
                stored.copy(
                    id = "99999999-0000-4000-8000-0000000002%02d".format(i),
                    ao3WorkID = 840000 + i,
                    sourceUrl = "https://archiveofourown.org/works/${840000 + i}",
                    title = "y".repeat(900_000),
                    hasEpub = false,
                    lastModifiedAt = FIXED_CLOCK.plusSeconds(60)
                ).toEntity()
            )
        }
        clockInstant = FIXED_CLOCK.plusSeconds(600)
        assertTrue("parity publishes whatever it builds", syncRepository.runSync() is SyncResult.Success)
        val published = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        assertTrue(published.size > BackupLimits.MAX_MANIFEST_BYTES)
        assertNotNull(Json.parseToJsonElement(published.toString(Charsets.UTF_8)).jsonObject["liveOpaque"])
    }

    @Test
    fun aManifestJustUnderTheLimitRoundTripsImportExportAndSync() = runTest {
        val limit = BackupLimits.MAX_MANIFEST_BYTES.toInt()
        val base = iosT541ManifestJson()
        fun withPad(n: Int) = JsonObject(base + mapOf("liveOpaque" to JsonPrimitive("x".repeat(n))))
        val baseSize = BackupJson.encodeToString(JsonObject.serializer(), withPad(0)).toByteArray().size
        val pad = limit - baseSize - 4096
        val manifest = withPad(pad)
        assertTrue(BackupJson.encodeToString(JsonObject.serializer(), manifest).toByteArray().size in (limit - 8192)..limit)

        backupRepository.importV2ZipBytes(zipManifest(manifest), mode = BackupImportMode.MERGE)
        val exported = exportedManifest()
        assertEquals(pad, (exported["liveOpaque"] as JsonPrimitive).content.length)

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val published = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        assertTrue(published.size <= limit)
        val json = BackupValidator.decodeManifestWithRaw(published).second!!
        assertEquals(pad, (json["liveOpaque"] as JsonPrimitive).content.length)
    }

    @Test
    fun aCancelledReplaceDropsTheSetAsideOverlaysInsteadOfRestoringThem() = runTest {
        // Cancellation can surface after Room committed, so the old overlays must never come back.
        val workId = "99999999-0000-4000-8000-000000000095"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        BackupRepository.afterOverlaysStaged = { throw kotlinx.coroutines.CancellationException("cancelled") }
        try {
            assertTrue(
                runCatching {
                    backupRepository.importV2ZipBytes(zipManifest(emptyReplacement), mode = BackupImportMode.REPLACE_LIBRARY)
                }.isFailure
            )
        } finally {
            BackupRepository.afterOverlaysStaged = null
        }
        assertTrue(exportedManifest()["documents"]?.jsonArray.isNullOrEmpty())
        assertTrue(Files.list(filesRoot).use { it.noneMatch { p -> p.fileName.toString().endsWith(".replace-aside") } })
    }

    @Test
    fun aReplaceWhoseSecondOverlayCannotBeSetAsideLeavesTheFirstInPlace() = runTest {
        val workId = "99999999-0000-4000-8000-000000000094"
        backupRepository.importV2ZipBytes(zipManifest(backupOneOverlay(workId)), mode = BackupImportMode.MERGE)
        // The aside slot of the pending overlay is occupied by a non-empty directory.
        val slot = filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.replace-aside")
        Files.createDirectories(slot.resolve("blocked")).also { Files.write(it.resolve("x"), byteArrayOf(0)) }
        assertTrue(
            runCatching {
                backupRepository.importV2ZipBytes(zipManifest(emptyReplacement), mode = BackupImportMode.REPLACE_LIBRARY)
            }.isFailure
        )
        assertEquals(false, database.workDao().getById(workId)!!.isDeleted)
        assertOldOverlaysStillExported(exportedManifest())
    }

    @Test
    fun overlayAsidesLeftByADeadReplaceAreDroppedNotRestored() = runTest {
        Files.write(filesRoot.resolve("sync-last-manifest.json.replace-aside"), "{\"documents\":[{\"name\":\"old\"}]}".toByteArray())
        Files.write(
            filesRoot.resolve("${BackupRepository.PENDING_IMPORT_MANIFEST_FILE}.replace-aside"),
            "{\"documents\":[{\"name\":\"old\"}]}".toByteArray()
        )
        backupRepository.recoverInterruptedReplace()
        assertTrue(Files.list(filesRoot).use { it.noneMatch { p -> p.fileName.toString().endsWith(".replace-aside") } })
        assertNull(exportedManifest()["documents"])
    }

    private suspend fun assertPendingBodySurvivesUntilSave(
        pendingFile: java.nio.file.Path,
        workId: String,
        block: suspend () -> Unit
    ) {
        var publishes = 0
        SyncLastManifestStore.beforeFilePublish = { path ->
            if (path.fileName?.toString() == pendingFile.fileName?.toString()) {
                val held = path
                assertTrue(
                    "pending overlay must still hold Backup 1 when save begins",
                    Files.isRegularFile(held) && Files.size(held) > 0L
                )
                val body = SyncLastManifestStore(held.parent, held.fileName.toString()).load()!!
                assertEquals(
                    JsonPrimitive("[{\"username\":\"ada\"}]"),
                    workJson(body, workId)["authorIdentitiesJSON"]
                )
                assertEquals(
                    "notes/backup-one.json",
                    body.getValue("documents").jsonArray.single().jsonObject.getValue("name").jsonPrimitive.content
                )
                publishes += 1
            }
        }
        try {
            block()
        } finally {
            SyncLastManifestStore.beforeFilePublish = null
        }
        assertEquals(1, publishes)
    }

    private fun backupOneOverlay(workId: String): JsonObject = JsonObject(
        mapOf(
            "version" to JsonPrimitive(8),
            "exportedAt" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
            "documents" to JsonArray(
                listOf(
                    JsonObject(
                        mapOf(
                            "name" to JsonPrimitive("notes/backup-one.json"),
                            "data" to JsonPrimitive("eyJpdGVtcyI6W119"),
                            "modifiedAt" to JsonPrimitive("2026-06-26T10:35:00.000Z")
                        )
                    )
                )
            ),
            "works" to JsonArray(
                listOf(
                    JsonObject(
                        mapOf(
                            "id" to JsonPrimitive(workId),
                            "title" to JsonPrimitive("Backup One"),
                            "author" to JsonPrimitive("Ada"),
                            "sourceURL" to JsonPrimitive("https://archiveofourown.org/works/820077"),
                            "ao3WorkID" to JsonPrimitive(820077),
                            "dateAdded" to JsonPrimitive("2026-06-26T09:00:00.000Z"),
                            "lastModifiedAt" to JsonPrimitive("2026-06-26T10:00:00.000Z"),
                            "isSaved" to JsonPrimitive(true),
                            "authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"ada\"}]")
                        )
                    )
                )
            )
        )
    )

    @Test
    fun legacyKudosBackupSyncFoldsPendingImportOverlay() = runTest {
        syncRepository.disconnect()

        val localWorkId = "99999999-0000-4000-8000-000000000099"
        val localImport = JsonObject(
            mapOf(
                "version" to JsonPrimitive(8),
                "exportedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("local-pending-draft"),
                "pendingOnlyKey" to JsonPrimitive("kept-across-legacy-zip"),
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(localWorkId),
                                "title" to JsonPrimitive("Local Pending Work"),
                                "author" to JsonPrimitive("Eve"),
                                "sourceURL" to JsonPrimitive("https://archiveofourown.org/works/820099"),
                                "ao3WorkID" to JsonPrimitive(820099),
                                "dateAdded" to JsonPrimitive("2026-06-26T13:00:00.000Z"),
                                "lastModifiedAt" to JsonPrimitive("2026-06-26T14:00:00.000Z"),
                                "isSaved" to JsonPrimitive(true),
                                "authorIdentitiesJSON" to JsonPrimitive("[{\"username\":\"eve\"}]")
                            )
                        )
                    )
                )
            )
        )
        backupRepository.importV2ZipBytes(zipManifest(localImport), mode = BackupImportMode.MERGE)

        val root = DocumentFile.fromTreeUri(context, treeUri)!!
        val legacyZipManifest = JsonObject(
            iosT541ManifestJson() + mapOf(
                "exportedAt" to JsonPrimitive("2026-06-26T12:00:00.000Z"),
                "writingRecovery" to JsonPrimitive("older-legacy-zip-draft")
            )
        )
        writeChild(root, "Kudos.kudosbackup", "application/zip", zipManifest(legacyZipManifest))

        context.grantUriPermission(
            context.packageName,
            treeUri,
            android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        syncRepository.connect(treeUri)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val synced = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(JsonPrimitive("local-pending-draft"), synced["writingRecovery"])
        assertEquals(JsonPrimitive("kept-across-legacy-zip"), synced["pendingOnlyKey"])
        assertEquals(
            JsonPrimitive("[{\"username\":\"eve\"}]"),
            workJson(synced, localWorkId)["authorIdentitiesJSON"]
        )
        assertEquals(
            legacyZipManifest.getValue("works").jsonArray[0].jsonObject["authorIdentitiesJSON"],
            workJson(synced, WORK_ONE)["authorIdentitiesJSON"]
        )
        assertFalse(Files.exists(filesRoot.resolve(BackupRepository.PENDING_IMPORT_MANIFEST_FILE)))
    }

    @Test
    fun winningFallbackStampsAreWrittenCappedAtOwnExportedAtAndFarFutureDropped() {
        val now = Instant.parse("2021-01-01T00:00:00Z")
        val workId = "10000000-0000-4000-8000-0000000000aa"
        val unmatchedWorkId = "10000000-0000-4000-8000-0000000000bb"

        val primary = JsonObject(
            stampedManifest(
                exportedAt = "2020-06-01T00:00:00Z",
                workStamp = "2020-01-01T00:00:00Z",
                workId = workId,
                workExtraKey = "futureField",
                workExtraValue = JsonPrimitive("older-primary"),
                queueStamp = "2020-01-01T00:00:00Z",
                queueExtraKey = "futureField",
                queueExtraValue = JsonPrimitive("older-primary"),
                awakeStamp = "2020-01-01T00:00:00Z",
                awake = true
            ) + mapOf(
                "pronunciations" to JsonObject(
                    mapOf("stamps" to JsonObject(mapOf("[global]Sam" to JsonPrimitive("2020-01-01T00:00:00Z"))))
                )
            )
        )
        val fallbackForged = JsonObject(
            stampedManifest(
                exportedAt = "2020-02-01T00:00:00Z",
                workStamp = "2020-05-01T00:00:00Z",
                workId = workId,
                workExtraKey = "forgedOnly",
                workExtraValue = JsonPrimitive("from-forged-fallback"),
                queueStamp = "2020-05-01T00:00:00Z",
                queueExtraKey = "forgedQueueKey",
                queueExtraValue = JsonPrimitive("from-forged-fallback"),
                awakeStamp = "2020-05-01T00:00:00Z",
                awake = false
            ) + mapOf(
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(workId),
                                "lastModifiedAt" to JsonPrimitive("2020-05-01T00:00:00Z"),
                                "forgedOnly" to JsonPrimitive("from-forged-fallback")
                            )
                        ),
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(unmatchedWorkId),
                                "lastModifiedAt" to JsonPrimitive("2020-05-01T00:00:00Z"),
                                "forgedOnly" to JsonPrimitive("unmatched-fallback")
                            )
                        )
                    )
                ),
                "pronunciations" to JsonObject(
                    mapOf("stamps" to JsonObject(mapOf("[global]Sam" to JsonPrimitive("2020-05-01T00:00:00Z"))))
                )
            )
        )

        val folded = mergeFallbackManifestJson(primary, fallbackForged, now)!!
        assertEquals(JsonPrimitive("2020-06-01T00:00:00Z"), folded["exportedAt"])
        assertEquals(JsonPrimitive("2020-02-01T00:00:00.000Z"), workJson(folded, workId)["lastModifiedAt"])
        assertEquals(JsonPrimitive("2020-02-01T00:00:00.000Z"), workJson(folded, unmatchedWorkId)["lastModifiedAt"])
        assertEquals(
            JsonPrimitive("2020-02-01T00:00:00.000Z"),
            folded.getValue("readingQueues").jsonArray.single().jsonObject["dateUpdated"]
        )
        assertEquals(
            JsonPrimitive("2020-02-01T00:00:00.000Z"),
            folded.getValue("settings").jsonObject.getValue("modifiedAt").jsonObject["keepScreenAwake"]
        )
        assertEquals(
            JsonPrimitive("2020-02-01T00:00:00.000Z"),
            folded.getValue("pronunciations").jsonObject.getValue("stamps").jsonObject["[global]Sam"]
        )

        // A later merge with a genuine 2020-03-01 manifest must let 2020-03-01 win over the capped 2020-02-01 stamps.
        val genuine = JsonObject(
            stampedManifest(
                exportedAt = "2020-03-01T00:00:00Z",
                workStamp = "2020-03-01T00:00:00Z",
                workId = workId,
                workExtraKey = "futureField",
                workExtraValue = JsonPrimitive("kept"),
                queueStamp = "2020-03-01T00:00:00Z",
                queueExtraKey = "futureField",
                queueExtraValue = JsonPrimitive("kept"),
                awakeStamp = "2020-03-01T00:00:00Z",
                awake = true
            ) + mapOf(
                "works" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(workId),
                                "lastModifiedAt" to JsonPrimitive("2020-03-01T00:00:00Z"),
                                "futureField" to JsonPrimitive("kept")
                            )
                        ),
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(unmatchedWorkId),
                                "lastModifiedAt" to JsonPrimitive("2020-03-01T00:00:00Z"),
                                "futureField" to JsonPrimitive("kept-second")
                            )
                        )
                    )
                ),
                "pronunciations" to JsonObject(
                    mapOf("stamps" to JsonObject(mapOf("[global]Sam" to JsonPrimitive("2020-03-01T00:00:00Z"))))
                )
            )
        )
        listOf(
            mergeFallbackManifestJson(folded, genuine, now)!!,
            mergeFallbackManifestJson(genuine, folded, now)!!
        ).forEach { merged ->
            val firstWork = workJson(merged, workId)
            assertEquals(JsonPrimitive("kept"), firstWork["futureField"])
            assertFalse("forgedOnly" in firstWork)
            val secondWork = workJson(merged, unmatchedWorkId)
            assertEquals(JsonPrimitive("kept-second"), secondWork["futureField"])
            assertFalse("forgedOnly" in secondWork)
            val queue = merged.getValue("readingQueues").jsonArray.single().jsonObject
            assertEquals(JsonPrimitive("kept"), queue["futureField"])
            assertFalse("forgedQueueKey" in queue)
            val settings = merged.getValue("settings").jsonObject
            assertEquals(JsonPrimitive(true), settings.getValue("extras").jsonObject["keepScreenAwake"])
            assertEquals(
                JsonPrimitive("2020-03-01T00:00:00Z"),
                settings.getValue("modifiedAt").jsonObject["keepScreenAwake"]
            )
            assertEquals(
                JsonPrimitive("2020-03-01T00:00:00Z"),
                merged.getValue("pronunciations").jsonObject.getValue("stamps").jsonObject["[global]Sam"]
            )
        }

        // Unvalidated far-future stamps (> now + 24h) are stripped even on a tie against an unstamped side.
        val unstampedPrimary = JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive("2020-06-01T00:00:00Z"),
                "readingQueues" to JsonArray(
                    listOf(JsonObject(mapOf("id" to JsonPrimitive(QUEUE_ONE), "kindRaw" to JsonPrimitive("custom"))))
                )
            )
        )
        val farFutureFallback = JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive("2020-02-01T00:00:00Z"),
                "readingQueues" to JsonArray(
                    listOf(
                        JsonObject(
                            mapOf(
                                "id" to JsonPrimitive(QUEUE_ONE),
                                "kindRaw" to JsonPrimitive("custom"),
                                "dateUpdated" to JsonPrimitive("3000-01-01T00:00:00Z")
                            )
                        )
                    )
                ),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive("3000-01-01T00:00:00Z"))),
                        "extras" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive(true)))
                    )
                ),
                "pronunciations" to JsonObject(
                    mapOf("stamps" to JsonObject(mapOf("[global]Future" to JsonPrimitive("3000-01-01T00:00:00Z"))))
                )
            )
        )
        val sanitized = mergeFallbackManifestJson(unstampedPrimary, farFutureFallback, now)!!
        assertFalse(
            "dateUpdated" in sanitized.getValue("readingQueues").jsonArray.single().jsonObject
        )
        assertEquals(
            JsonPrimitive(true),
            sanitized.getValue("settings").jsonObject.getValue("extras").jsonObject["keepScreenAwake"]
        )
        assertFalse(
            "keepScreenAwake" in sanitized.getValue("settings").jsonObject.getValue("modifiedAt").jsonObject
        )
        assertFalse(
            "[global]Future" in sanitized.getValue("pronunciations").jsonObject.getValue("stamps").jsonObject
        )
    }

    private fun stampedManifest(
        exportedAt: String,
        workStamp: String,
        workId: String,
        workExtraKey: String,
        workExtraValue: JsonElement,
        queueStamp: String,
        queueExtraKey: String,
        queueExtraValue: JsonElement,
        awakeStamp: String,
        awake: Boolean
    ): JsonObject {
        val work = linkedMapOf<String, JsonElement>(
            "id" to JsonPrimitive(workId),
            "lastModifiedAt" to JsonPrimitive(workStamp)
        )
        work[workExtraKey] = workExtraValue
        val queue = linkedMapOf<String, JsonElement>(
            "id" to JsonPrimitive(QUEUE_ONE),
            "kindRaw" to JsonPrimitive("custom"),
            "dateUpdated" to JsonPrimitive(queueStamp)
        )
        queue[queueExtraKey] = queueExtraValue
        return JsonObject(
            mapOf(
                "exportedAt" to JsonPrimitive(exportedAt),
                "works" to JsonArray(listOf(JsonObject(work))),
                "readingQueues" to JsonArray(listOf(JsonObject(queue))),
                "settings" to JsonObject(
                    mapOf(
                        "modifiedAt" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive(awakeStamp))),
                        "extras" to JsonObject(mapOf("keepScreenAwake" to JsonPrimitive(awake)))
                    )
                )
            )
        )
    }

    private fun assertGenuineStampsWin(merged: JsonObject) {
        val work = merged.getValue("works").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive("kept"), work["futureField"])
        assertFalse("forgedOnly" in work)
        val queue = merged.getValue("readingQueues").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive("kept"), queue["futureField"])
        assertFalse("forgedQueueKey" in queue)
        val settings = merged.getValue("settings").jsonObject
        assertEquals(JsonPrimitive(true), settings.getValue("extras").jsonObject["keepScreenAwake"])
        assertEquals(
            JsonPrimitive("2020-03-01T00:00:00Z"),
            settings.getValue("modifiedAt").jsonObject["keepScreenAwake"]
        )
    }

    private fun assertFarFutureLoses(merged: JsonObject) {
        val work = merged.getValue("works").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive("[{\"username\":\"real\"}]"), work["authorIdentitiesJSON"])
        assertFalse("forgedOnly" in work)
        val queue = merged.getValue("readingQueues").jsonArray.single().jsonObject
        assertEquals(JsonObject(mapOf("queueMeta" to JsonPrimitive(1))), queue["futureField"])
        assertFalse("forgedQueueKey" in queue)
    }

    private fun iosT541ManifestJson(): JsonObject {
        val pair = Ed25519Sign.KeyPair.newKeyPair()
        runBlocking { settingsRepository.trustTombstonePublicKey(pair.publicKey.toLowerHex()) }
        val signedTombstone = TombstoneSigning.signWithRawKey(
            SyncTombstone(
                id = TOMBSTONE_ONE,
                recordID = "99999999-0000-4000-8000-000000000099",
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse("2026-06-20T10:00:00Z"),
                lastModifiedAt = Instant.parse("2026-06-20T10:00:00Z"),
                deletedOnDeviceID = "ios",
                deletionReason = "deleted"
            ),
            pair.privateKey,
            pair.publicKey.toLowerHex()
        )
        return Json.parseToJsonElement(
        """{
            "version": 8,
            "exportedAt": "2026-06-26T11:00:00.000Z",
            "exportedBy": {
                "app": "Kudos",
                "platform": "ios",
                "appVersion": "1.9.0",
                "schemaVersion": 8
            },
            "works": [
                {
                    "id": "$WORK_ONE",
                    "title": "iOS Work One",
                    "author": "Alice",
                    "summary": "Summary",
                    "sourceURL": "https://archiveofourown.org/works/820001",
                    "ao3WorkID": 820001,
                    "dateAdded": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "isFavorite": true,
                    "isSaved": true,
                    "isFinished": false,
                    "hasEPUB": false,
                    "isComplete": true,
                    "lastSpineIndex": 2,
                    "lastScrollFraction": 0.4,
                    "authorIdentitiesJSON": "[{\"username\":\"alice\",\"pseud\":\"Alice\",\"displayName\":\"Alice\",\"kind\":\"registered\"}]",
                    "futureWorkInsights": {"readingStreakDays": 4}
                },
                {
                    "id": "$WORK_TWO",
                    "title": "iOS Work Two",
                    "author": "Bob",
                    "summary": "",
                    "sourceURL": "https://archiveofourown.org/works/820002",
                    "ao3WorkID": 820002,
                    "dateAdded": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "isSaved": true,
                    "hasEPUB": false,
                    "authorIdentitiesJSON": "[{\"username\":\"bob\"}]"
                }
            ],
            "collections": [
                {
                    "id": "$COLLECTION_ONE",
                    "name": "iOS Collection",
                    "dateAdded": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "workIDs": ["$WORK_ONE"],
                    "lastMembershipChangedAt": "2026-06-25T15:00:00.000Z",
                    "futureCollectionKey": "preserved"
                }
            ],
            "readingQueues": [
                {
                    "id": "$QUEUE_ONE",
                    "name": "Saved for Later",
                    "kindRaw": "savedForLater",
                    "sortOrder": -1000,
                    "dateCreated": "2026-06-20T10:00:00.000Z",
                    "dateUpdated": "2026-06-26T10:00:00.000Z",
                    "futureField": {"queueMeta": 1}
                }
            ],
            "readingQueueMemberships": [
                {
                    "id": "$MEMBERSHIP_ONE",
                    "queueID": "$QUEUE_ONE",
                    "workID": "$WORK_ONE",
                    "queuedAt": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "sortOrderInQueue": 0,
                    "note": "",
                    "futureField": "membershipExtra"
                }
            ],
            "annotations": [
                {
                    "id": "$ANNOTATION_ONE",
                    "workID": "$WORK_ONE",
                    "kindRaw": "highlight",
                    "colorRaw": "yellow",
                    "locatorString": "{\"href\":\"ch1.xhtml\"}",
                    "selectedText": "Marked",
                    "note": "Note",
                    "progression": 0.25,
                    "spineIndex": 1,
                    "chapterTitle": "One",
                    "createdAt": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "isPendingDeletion": false,
                    "futureField": {"anchorVersion": 2}
                }
            ],
            "bookmarks": [
                {
                    "id": "$BOOKMARK_ONE",
                    "title": "Saved Link",
                    "urlString": "https://archiveofourown.org/works/820001#comments",
                    "dateAdded": "2026-06-20T10:00:00.000Z",
                    "futureField": ["tag1", "tag2"]
                }
            ],
            "savedSearches": [
                {
                    "id": "$SEARCH_ONE",
                    "name": "Saved Query",
                    "dateAdded": "2026-06-20T10:00:00.000Z",
                    "filters": {},
                    "futureField": true
                }
            ],
            "readingSessions": [
                {
                    "id": "$SESSION_ONE",
                    "workID": "$WORK_ONE",
                    "ao3WorkID": 820001,
                    "sourceURL": "https://archiveofourown.org/works/820001",
                    "workTitle": "iOS Work One",
                    "startedAt": "2026-06-26T09:00:00.000Z",
                    "endedAt": "2026-06-26T09:30:00.000Z",
                    "durationSeconds": 1800.0,
                    "tzOffsetSeconds": -18000,
                    "startProgress": 0.1,
                    "startSpineIndex": 0,
                    "modeRaw": "reading",
                    "playbackRate": 1.25,
                    "activeSeconds": 1650.5,
                    "deviceID": "ios-device-1",
                    "rulesVersion": 2,
                    "lastSpineIndex": 2,
                    "chapterTitle": "Two",
                    "endingProgress": 0.4,
                    "wordCount": 12000,
                    "chapterCountAtVisit": 5,
                    "didFinish": false,
                    "lastModifiedAt": "2026-06-26T09:30:00.000Z",
                    "futureSessionField": "kept"
                }
            ],
            "readingFavorites": [
                {
                    "id": "$FAVORITE_ONE",
                    "kindRaw": "fandom",
                    "targetKey": "Portable Fandom",
                    "displayName": "Portable Fandom",
                    "createdAt": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-26T10:00:00.000Z",
                    "futureField": 7
                }
            ],
            "fandomReadWatermarks": [
                {
                    "id": "$WATERMARK_ONE",
                    "fandomName": "Portable Fandom",
                    "lastVisitedAt": "2026-06-26T08:00:00.000Z",
                    "newestWorkIDSeen": 820001,
                    "newestWorkTitleSeen": "iOS Work One",
                    "lastModifiedAt": "2026-06-26T08:00:00.000Z",
                    "futureField": "watermarkExtra"
                }
            ],
            "tombstones": [
                {
                    "id": "$TOMBSTONE_ONE",
                    "recordID": "99999999-0000-4000-8000-000000000099",
                    "recordTypeRaw": "savedWork",
                    "createdAt": "2026-06-20T10:00:00.000Z",
                    "lastModifiedAt": "2026-06-20T10:00:00.000Z",
                    "sourceURL": "",
                    "deletedOnDeviceID": "ios",
                    "deletionReason": "deleted",
                    "signerPublicKey": "${signedTombstone.signerPublicKey}",
                    "signature": "${signedTombstone.signature}",
                    "futureField": {"permanence": true}
                }
            ],
            "fonts": [],
            "pronunciations": {
                "global": {"Sam": "sæm"},
                "fandoms": {},
                "works": {},
                "stamps": {
                    "[global]Sam": "2026-06-26T10:00:00.000Z"
                },
                "futurePronKey": "kept"
            },
            "settings": {
                "readerFontID": "system",
                "readerMode": "paged",
                "readerTwoPage": false,
                "readerCustomize": false,
                "readerBoldText": false,
                "readerFontPt": 18.0,
                "readerLineHeight": 1.65,
                "readerLetterSpacing": 0.0,
                "readerWordSpacing": 0.0,
                "readerMargin": 28.0,
                "readerJustify": false,
                "confirmBeforeDelete": true,
                "hideMatureContent": true,
                "matureContentMode": "obscure",
                "requireBiometricToReveal": false,
                "appTheme": "dark",
                "readerTheme": "dark",
                "matchAppReaderTheme": true,
                "accentColorHex": "#2468AC",
                "autoPreserveSmallSeriesOnSaveForLater": false,
                "autoPreserveSeriesWorkThreshold": 5,
                "modifiedAt": {
                    "readerMode": "2026-06-26T10:00:00.000Z",
                    "keepScreenAwake": "2026-06-26T10:00:00.000Z",
                    "[\"ao3CommentDrafts\",\"42\"]": "2026-06-26T10:00:00.000Z"
                },
                "extras": {
                    "keepScreenAwake": true,
                    "showsZeroStats": false,
                    "readerSpeechRate": 1.25,
                    "readerHighlightColor": "yellow",
                    "writing.recentTags.v1": {"data": "eyJieUtpbmQiOnt9fQ=="},
                    "ao3CommentDrafts": {"map": {"42": "Draft comment text"}}
                },
                "futureSetting": {"nested": [1, null, "ok"]}
            },
            "writingRecovery": [
                {
                    "fileName": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef.s1.json",
                    "entry": {
                        "text": "Unpublished chapter draft",
                        "savedAt": "2026-06-26T10:30:00.000Z"
                    }
                }
            ],
            "documents": [
                {
                    "name": "mail/updates.json",
                    "data": "eyJpdGVtcyI6W119",
                    "modifiedAt": "2026-06-26T10:35:00.000Z"
                }
            ],
            "futureRecords": [
                {"id": "f0000000-0000-4000-8000-000000000001", "kind": "unknownRecord"}
            ],
            "futureManifestMeta": "ios-t541"
        }"""
        ).jsonObject
    }

    private fun workJson(manifest: JsonObject, id: String): JsonObject {
        return manifest.getValue("works").jsonArray.first {
            it.jsonObject["id"]?.jsonPrimitive?.content.equals(id, ignoreCase = true)
        }.jsonObject
    }

    private fun zipManifest(json: JsonObject): ByteArray {
        return ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST))
                zip.write(BackupJson.encodeToString(JsonObject.serializer(), json).toByteArray())
                zip.closeEntry()
            }
            out.toByteArray()
        }
    }

    private suspend fun exportedManifest(): JsonObject {
        val exported = backupRepository.exportV2ZipBytes()
        return ZipInputStream(ByteArrayInputStream(exported)).use { zip ->
            generateSequence { zip.nextEntry }.first { it.name == BackupPaths.MANIFEST }
            Json.parseToJsonElement(zip.readBytes().toString(Charsets.UTF_8)).jsonObject
        }
    }

    private fun ensureKudosLibrary(): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: error("fromTreeUri returned null for $treeUri")
        return root.findFile("KudosLibrary")
            ?: root.createDirectory("KudosLibrary")
            ?: error("Could not create KudosLibrary")
    }

    private fun requireKudosLibrary(): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: error("fromTreeUri returned null for $treeUri")
        return root.findFile("KudosLibrary")
            ?: error("KudosLibrary missing under $treeUri")
    }

    private fun writeChild(dir: DocumentFile, name: String, mime: String, bytes: ByteArray) {
        val existing = dir.findFile(name)
        val file = existing ?: dir.createFile(mime, name)
            ?: error("createFile failed for $name")
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: error("openOutputStream failed for $name")
    }

    private fun readDocument(file: DocumentFile): ByteArray {
        return context.contentResolver.openInputStream(file.uri)?.use { it.readBytes() }
            ?: error("openInputStream failed for ${file.name}")
    }

    companion object {
        private val FIXED_CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private const val WORK_ONE = "10000000-0000-4000-8000-000000000001"
        private const val WORK_TWO = "10000000-0000-4000-8000-000000000002"
        private const val COLLECTION_ONE = "20000000-0000-4000-8000-000000000001"
        private const val QUEUE_ONE = "30000000-0000-4000-8000-000000000001"
        private const val MEMBERSHIP_ONE = "40000000-0000-4000-8000-000000000001"
        private const val ANNOTATION_ONE = "50000000-0000-4000-8000-000000000001"
        private const val SESSION_ONE = "60000000-0000-4000-8000-000000000001"
        private const val FAVORITE_ONE = "70000000-0000-4000-8000-000000000001"
        private const val WATERMARK_ONE = "80000000-0000-4000-8000-000000000001"
        private const val BOOKMARK_ONE = "a0000000-0000-4000-8000-000000000001"
        private const val SEARCH_ONE = "b0000000-0000-4000-8000-000000000001"
        private const val TOMBSTONE_ONE = "c0000000-0000-4000-8000-000000000001"
    }
}
