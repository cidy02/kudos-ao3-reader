package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.documentfile.provider.DocumentFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * End-to-end coverage for [SyncRepository] against a fake SAF
 * [android.provider.DocumentsProvider]. Pins the data-loss fixes around
 * atomic-ish manifest writes, corrupt-manifest recovery, equal-length content
 * updates, and post-commit orphan pruning.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SyncRepositoryTest {
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
    private lateinit var treeUri: Uri
    private lateinit var provider: FakeTempDocumentsProvider

    private var clockInstant: Instant = FIXED_CLOCK

    @Test
    fun originalReadLimitCountsStreamBytesWithoutTrustingProviderSize() {
        with(syncRepository) {
            try {
                java.io.ByteArrayInputStream(ByteArray(17)).readLimitedBytes("Originals/work.pdf", 16)
                fail("Actual bytes must be bounded even if a provider reports size zero")
            } catch (_: BackupError.EntryTooLarge) {
                // Expected: the 17th byte exceeds the limit.
            }
        }
    }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()

        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-sync-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )

        val filesRoot = Files.createTempDirectory("kudos-sync-files")
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

        safRoot = Files.createTempDirectory("kudos-saf-root").toFile()
        provider = FakeTempDocumentsProvider()
        treeUri = provider.install(context, safRoot)

        syncRepository = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = { clockInstant }
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
    }

    @Test
    fun fakeDocumentsProviderSupportsDocumentFileRoundTrip() {
        // Infrastructure smoke test: if this fails, every SyncRepository test is
        // measuring DocumentFile/query routing rather than sync behaviour.
        val root = DocumentFile.fromTreeUri(context, treeUri)
        assertNotNull("fromTreeUri", root)

        // Direct ContentResolver probe — surfaces the real exception listFiles swallows.
        val childUri = try {
            android.provider.DocumentsContract.createDocument(
                context.contentResolver,
                root!!.uri,
                android.provider.DocumentsContract.Document.MIME_TYPE_DIR,
                "SmokeDir"
            )
        } catch (error: Exception) {
            throw AssertionError("createDocument failed: $error", error)
        }
        assertNotNull("createDocument uri", childUri)

        try {
            context.contentResolver.query(childUri!!, null, null, null, null).use { cursor ->
                assertNotNull("query(document) returned null cursor", cursor)
                assertTrue("query(document) empty", cursor!!.moveToFirst())
                val nameIdx = cursor.getColumnIndex(
                    android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME
                )
                assertTrue(nameIdx >= 0)
                assertEquals("SmokeDir", cursor.getString(nameIdx))
            }
        } catch (error: Exception) {
            throw AssertionError(
                "query(documentUri=$childUri) failed: ${error.javaClass.name}: ${error.message}",
                error
            )
        }

        val childrenUri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(
            root.uri,
            android.provider.DocumentsContract.getDocumentId(root.uri)
        )
        try {
            context.contentResolver.query(childrenUri, null, null, null, null).use { cursor ->
                assertNotNull("query(children) returned null cursor", cursor)
                val names = mutableListOf<String>()
                while (cursor!!.moveToNext()) {
                    val idx = cursor.getColumnIndex(
                        android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME
                    )
                    if (idx >= 0) names += cursor.getString(idx)
                }
                assertTrue("children=$names", "SmokeDir" in names)
            }
        } catch (error: Exception) {
            throw AssertionError(
                "query(childrenUri=$childrenUri) failed: ${error.javaClass.name}: ${error.message}",
                error
            )
        }

        val found = root.findFile("SmokeDir")
        assertNotNull("findFile after create", found)
        writeChild(found!!, "note.txt", "text/plain", "hello".toByteArray())
        val note = found.findFile("note.txt")
        assertNotNull(note)
        assertArrayEquals("hello".toByteArray(), readDocument(note!!))

        val renamed = android.provider.DocumentsContract.renameDocument(
            context.contentResolver,
            note.uri,
            "note-renamed.txt"
        )
        assertNotNull(renamed)
        assertNotNull(found.findFile("note-renamed.txt"))
        assertTrue(found.findFile("note.txt") == null)
    }

    // ------------------------------------------------------------------ (A)

    @Test
    fun manifestWriteIsAtomicishAndKeepsBakOnSecondSync() = runTest {
        seedLocalWork(WORK_A, "Example A", "epub-a-v1".toByteArray())

        val first = syncRepository.runSync()
        assertTrue("first sync: $first", first is SyncResult.Success)

        val kudos = requireKudosLibrary()
        val manifest = kudos.findFile(BackupPaths.MANIFEST)
        assertNotNull("manifest.json after first sync", manifest)
        val firstBytes = readDocument(manifest!!)
        assertTrue(firstBytes.isNotEmpty())
        BackupValidator.decodeManifest(firstBytes) // throws if invalid
        assertFalse(
            "no .bak until a prior live manifest is demoted",
            kudos.findFile(BackupPaths.MANIFEST_BACKUP)?.exists() == true
        )
        assertNoTempManifests(kudos)

        clockInstant = FIXED_CLOCK.plusSeconds(60)
        val second = syncRepository.runSync()
        assertTrue("second sync: $second", second is SyncResult.Success)

        val kudos2 = requireKudosLibrary()
        val live = kudos2.findFile(BackupPaths.MANIFEST)
        val bak = kudos2.findFile(BackupPaths.MANIFEST_BACKUP)
        assertNotNull("manifest.json after second sync", live)
        assertNotNull("manifest.json.bak after second sync", bak)
        BackupValidator.decodeManifest(readDocument(live!!))
        BackupValidator.decodeManifest(readDocument(bak!!))
        assertNoTempManifests(kudos2)
    }

    // ------------------------------------------------------------------ (B)

    @Test
    fun corruptPrimaryManifestFallsBackToBakAndSelfHealsWithoutPruning() = runTest {
        // Remote holds a good .bak (with a work local does not have) and a
        // truncated primary — the exact wedge that used to make every later
        // sync fail forever because import threw before export could repair it.
        val bakManifest = remoteManifest(
            works = listOf(remoteBackupWork(WORK_REMOTE, "From Bak", hasEpub = true)),
            exportedAt = "2026-01-01T00:00:00Z"
        )
        val bakBytes = BackupJson.encodeToString(bakManifest).toByteArray(Charsets.UTF_8)
        val goodPrimary = remoteManifest(
            works = listOf(remoteBackupWork(WORK_REMOTE, "From Live", hasEpub = true)),
            exportedAt = "2026-01-02T00:00:00Z"
        )
        val goodPrimaryBytes =
            BackupJson.encodeToString(goodPrimary).toByteArray(Charsets.UTF_8)
        // Non-empty truncated JSON — unparseable, but not zero-length.
        val corrupt = goodPrimaryBytes.copyOf(goodPrimaryBytes.size / 2)
        assertTrue(corrupt.isNotEmpty())
        assertTrue(
            runCatching { BackupValidator.decodeManifest(corrupt) }.isFailure
        )

        val kudos = ensureKudosLibrary()
        val worksDir = kudos.findFile(BackupPaths.WORKS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", corrupt)
        writeChild(kudos, BackupPaths.MANIFEST_BACKUP, "application/json", bakBytes)
        writeChild(
            worksDir,
            "$WORK_REMOTE.epub",
            "application/epub+zip",
            "remote-epub-bytes".toByteArray()
        )

        // Local is empty — import of .bak is the only way WORK_REMOTE appears.
        assertTrue(database.workDao().getAllIncludingDeleted().isEmpty())

        val result = syncRepository.runSync()
        assertTrue(
            "corrupt primary must not wedge the folder: $result",
            result is SyncResult.Success
        )

        val imported = database.workDao().getById(WORK_REMOTE)
        assertNotNull("bak contents should be imported", imported)
        assertEquals("From Bak", imported!!.title)

        val healed = requireKudosLibrary().findFile(BackupPaths.MANIFEST)
        assertNotNull(healed)
        val healedManifest = BackupValidator.decodeManifest(readDocument(healed!!))
        assertTrue(
            "export should rewrite a valid manifest listing the recovered work",
            healedManifest.works.any { it.id == WORK_REMOTE }
        )
        // The .bak was the way back to this device's records, never the list of what the
        // folder holds: a damaged manifest is not copied over it.
        assertArrayEquals(bakBytes, readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST_BACKUP)!!))
    }

    @Test
    fun zeroLengthPrimaryWithBakRecoversAndDoesNotPruneWorks() = runTest {
        val bakManifest = remoteManifest(
            works = listOf(remoteBackupWork(WORK_REMOTE, "Bak Work", hasEpub = true)),
            exportedAt = "2026-01-01T00:00:00Z"
        )
        val bakBytes = BackupJson.encodeToString(bakManifest).toByteArray(Charsets.UTF_8)

        val kudos = ensureKudosLibrary()
        val worksDir = kudos.findFile(BackupPaths.WORKS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", ByteArray(0))
        writeChild(kudos, BackupPaths.MANIFEST_BACKUP, "application/json", bakBytes)
        writeChild(
            worksDir,
            "$WORK_REMOTE.epub",
            "application/epub+zip",
            "keep-me".toByteArray()
        )
        // Not in the .bak. It may belong to a work the damaged manifest listed and the
        // older .bak does not, so a run that read only the .bak must keep it.
        writeChild(
            worksDir,
            "orphan-not-in-manifest.epub",
            "application/epub+zip",
            "orphan".toByteArray()
        )

        val result = syncRepository.runSync()
        assertTrue("zero-length primary recovery: $result", result is SyncResult.Success)

        val after = requireKudosLibrary()
        val afterWorks = after.findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull(
            "listed EPUB must not be pruned away on recovery",
            epubIn(afterWorks, WORK_REMOTE)
        )
        assertNotNull(afterWorks.findFile("orphan-not-in-manifest.epub"))
        // The folder is readable again: left damaged, no device could ever sync to it.
        BackupValidator.decodeManifest(readDocument(after.findFile(BackupPaths.MANIFEST)!!))

        val imported = database.workDao().getById(WORK_REMOTE)
        assertNotNull(imported)
        assertEquals("Bak Work", imported!!.title)
    }

    @Test
    fun unparseableConflictCopyDoesNotFailSyncAndIsNotDeleted() = runTest {
        seedLocalWork(WORK_A, "Local A", "local-a".toByteArray())

        val kudos = ensureKudosLibrary()
        // Pre-seed a conflict copy the way a racing SAF provider would leave it.
        writeChild(
            kudos,
            "manifest (1).json",
            "application/json",
            """{"version":8,"exportedAt":"not-json""".toByteArray()
        )

        val result = syncRepository.runSync()
        assertTrue("unparseable conflict must not fail sync: $result", result is SyncResult.Success)
        assertEquals(0, (result as SyncResult.Success).foldedConflicts)

        val stillThere = requireKudosLibrary().findFile("manifest (1).json")
        assertNotNull("unreadable conflict must be left in place", stillThere)
        assertTrue(stillThere!!.exists())
    }

    @Test
    fun aConflictWhoseEpubHasNotArrivedIsFoldedAndItsWorkStaysListed() = runTest {
        // As iOS: a file that is not in the folder is nothing to fetch, not a reason to stop.
        // The work goes into this device's manifest, so its EPUB is kept when it does arrive.
        seedFolder()
        val kudos = requireKudosLibrary()
        val conflict = BackupJson.encodeToString(remoteManifest(
            works = listOf(remoteBackupWork(WORK_REMOTE, "Uploading", hasEpub = true)),
            exportedAt = "2026-06-02T00:00:00Z"
        )).toByteArray()
        writeChild(kudos, "manifest (1).json", "application/json", conflict)

        val result = syncRepository.runSync()

        assertEquals(1, (result as SyncResult.Success).foldedConflicts)
        assertNull(requireKudosLibrary().findFile("manifest (1).json"))
        val manifest = BackupValidator.decodeManifest(readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertTrue(manifest.works.any { it.id == WORK_REMOTE })
    }

    @Test
    fun aFoldedConflictCopyStaysUntilTheManifestThatListsItIsWritten() = runTest {
        // The run folds the copy, then stops before its own manifest is written. Deleted at
        // the fold, as it used to be, the copy's records were then in no index in the folder.
        seedFolder()
        val kudos = requireKudosLibrary()
        val conflict = BackupJson.encodeToString(remoteManifest(
            works = listOf(remoteBackupWork(WORK_REMOTE, "Only in the copy", hasEpub = false)),
            exportedAt = "2026-06-02T00:00:00Z"
        )).toByteArray()
        writeChild(kudos, "manifest (1).json", "application/json", conflict)
        var otherDeviceWrote = false
        val interrupted = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = {
                if (!otherDeviceWrote) {
                    otherDeviceWrote = true
                    val theirs = remoteManifest(emptyList(), "2026-06-03T00:00:00Z")
                    writeChild(requireKudosLibrary(), BackupPaths.MANIFEST, "application/json",
                        BackupJson.encodeToString(theirs).toByteArray())
                }
                clockInstant
            }
        )

        assertTrue(interrupted.runSync() is SyncResult.Error)

        assertArrayEquals(conflict, readDocument(requireKudosLibrary().findFile("manifest (1).json")!!))
    }

    @Test
    fun aFolderWithFilesAndNoManifestIsWrittenToAndNothingInItIsPruned() = runTest {
        // What an interrupted first sync leaves: EPUBs uploaded, no manifest yet. Refusing to
        // write here would leave the folder unable to sync for good; pruning by this device's
        // library alone would delete the other device's book.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        val worksDir = ensureKudosLibrary().createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", "theirs".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = requireKudosLibrary()
        BackupValidator.decodeManifest(readDocument(after.findFile(BackupPaths.MANIFEST)!!))
        assertNotNull(epubIn(after.findFile(BackupPaths.WORKS_DIRECTORY)!!, WORK_REMOTE))
    }

    @Test
    fun aManifestThisBuildCannotReadIsNotWrittenOver() = runTest {
        // Whole JSON of a version this build does not know: another app version's index, not
        // damage. Written over, what that version listed would be gone from the folder.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        val kudos = ensureKudosLibrary()
        val newer = """{"version": 99, "exportedAt": "2026-06-01T00:00:00Z", "works": []}""".toByteArray()
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", newer)
        val worksDir = kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", "theirs".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Error)

        assertArrayEquals(newer, readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull(epubIn(after, WORK_REMOTE))
        assertNull("nothing of this device's is uploaded either", epubIn(after, WORK_A))
    }

    @Test
    fun whatTheManifestHoldsThatThisBuildDoesNotKnowStaysInTheOneItWrites() = runTest {
        // iOS's read-aloud pronunciation corrections: Android has no such thing, and wrote a
        // manifest without them. A device that joined the folder after that never got them.
        val pronunciations = """{"global":{"Cid":"sid"},"fandoms":{},"works":{}}"""
        val theirs = BackupJson.encodeToString(remoteManifest(emptyList(), "2026-06-01T00:00:00Z"))
        val kudos = ensureKudosLibrary()
        writeChild(
            kudos, BackupPaths.MANIFEST, "application/json",
            theirs.trimEnd().removeSuffix("}").plus(""", "pronunciations": $pronunciations}""").toByteArray()
        )
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = Json.parseToJsonElement(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)
        ).jsonObject
        assertEquals(Json.parseToJsonElement(pronunciations), written["pronunciations"])
        // What this build does know is its own: the exporter is this device, not theirs.
        assertTrue(written["works"].toString().contains(WORK_A, ignoreCase = true))
        assertFalse(written["exportedBy"].toString().contains("\"test\""))
    }

    @Test
    fun unknownRecordFieldsSurviveSyncWithLocalChangesAndTheSecondSyncIsByteIdentical() = runTest {
        val date = "2026-01-01T00:00:00Z"
        val theirs = remoteManifest(listOf(remoteBackupWork(WORK_A, "Old title", false).copy(
            sourceURL = "", lastModifiedAt = date
        )), date).copy(
            collections = listOf(BackupCollection(ANDROID_ONE, "Collection", date)),
            bookmarks = listOf(BackupBookmark("Link", "https://example.org/link", date, ANDROID_TWO))
        )
        val raw = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(), theirs).jsonObject.toMutableMap()
        val extras = mapOf(
            "works" to Json.parseToJsonElement("""{"later":{"array":[1,null,true,"exact"]}}"""),
            "collections" to Json.parseToJsonElement("""["future",{"n":2.75}]"""),
            "bookmarks" to Json.parseToJsonElement("null")
        )
        extras.forEach { (list, extra) ->
            raw[list] = JsonArray(raw.getValue(list).jsonArray.map { JsonObject(it.jsonObject + ("futureField" to extra)) })
        }
        val kudos = ensureKudosLibrary()
        writeChild(kudos, BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), JsonObject(raw)).toByteArray())
        val local = SavedWork(id = WORK_A, title = "Android title", author = "Android author", sourceUrl = "",
            dateAdded = FIXED_CLOCK, lastModifiedAt = FIXED_CLOCK, lastSpineIndex = 7,
            lastScrollFraction = 0.75, lastReadDate = FIXED_CLOCK, progressModifiedAt = FIXED_CLOCK,
            isSaved = true, hasEpub = false)
        database.workDao().upsert(local.toEntity())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val first = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        val written = Json.parseToJsonElement(first.toString(Charsets.UTF_8)).jsonObject
        extras.forEach { (list, extra) ->
            assertEquals(extra, written.getValue(list).jsonArray.single().jsonObject["futureField"])
        }
        val work = written.getValue("works").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive(local.title), work["title"])
        assertEquals(JsonPrimitive(local.author), work["author"])
        assertEquals(JsonPrimitive(7), work["lastSpineIndex"])
        assertEquals(JsonPrimitive(0.75), work["lastScrollFraction"])
        assertEquals(BackupPaths.sha256(first), settingsRepository.settings.first().sync.lastManifestDigest)

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertArrayEquals(first, readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
    }

    @Test
    fun unknownKeysDoNotRecreateADeletedRecordOnSync() = runTest {
        val date = "2026-01-01T00:00:00Z"
        val theirs = remoteManifest(emptyList(), date).copy(
            savedSearches = listOf(BackupSavedSearch(ANDROID_ONE, "Omitted", date))
        )
        val raw = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(), theirs).jsonObject
        val search = raw.getValue("savedSearches").jsonArray.single().jsonObject
        val withExtra = JsonObject(raw + ("savedSearches" to JsonArray(listOf(
            JsonObject(search + ("futureField" to JsonPrimitive("never resurrect")))
        ))))
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), withExtra).toByteArray())
        database.syncTombstoneDao().upsert(io.github.cidy02.kudos.core.model.SyncTombstone(
            id = ANDROID_TWO, recordID = ANDROID_ONE,
            recordTypeRaw = io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_SEARCH,
            createdAt = FIXED_CLOCK, lastModifiedAt = FIXED_CLOCK
        ).toEntity())

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val written = Json.parseToJsonElement(readDocument(
            requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!).toString(Charsets.UTF_8)).jsonObject
        assertTrue(written.getValue("savedSearches").jsonArray.isEmpty())
        assertNull(database.savedSearchDao().getById(ANDROID_ONE))
    }

    @Test
    fun unknownKeyCarryIgnoresMalformedOldRecordsAndListsAndNeverOverwritesKnownKeys() {
        val outgoing = Json.parseToJsonElement("""{
            "works":[{"id":"$WORK_A","title":"Android"}],
            "collections":[{"id":"$ANDROID_ONE","name":"Android collection"}],
            "fonts":[{"name":"Android font","fileName":"reader.otf","dateAdded":"now"}]
        }""").jsonObject
        val malformed = Json.parseToJsonElement("""{
            "works":[null,7,[],{"id":"$WORK_A","title":"Old","downloadedAt":"old","extra":[1,null]}],
            "collections":{"id":"$ANDROID_ONE","extra":true},
            "fonts":false
        }""").jsonObject
        val carried = carryUnknownRecordKeys(outgoing, malformed)
        val work = carried.getValue("works").jsonArray.single().jsonObject
        assertEquals(JsonPrimitive("Android"), work["title"])
        assertFalse("A known nullable key absent from outgoing must not be copied", "downloadedAt" in work)
        assertEquals(Json.parseToJsonElement("[1,null]"), work["extra"])
        assertEquals(outgoing["collections"], carried["collections"])
        assertEquals(outgoing["fonts"], carried["fonts"])
    }

    @Test
    fun unknownKeyCarryCoversEveryRecordListAndMergeIdentityFallbacks() {
        val date = "2026-01-01T00:00:00Z"
        val manifest = remoteManifest(listOf(remoteBackupWork(WORK_A, "Work", false)), date).copy(
            bookmarks = listOf(BackupBookmark("Link", "https://example.org/link", date, WORK_A)),
            fonts = listOf(BackupFont("Font", "Café.otf", date)),
            collections = listOf(BackupCollection(WORK_A, "Collection", date)),
            savedSearches = listOf(BackupSavedSearch(WORK_A, "Search", date)),
            readingQueues = listOf(BackupReadingQueue(WORK_A, kindRaw = ReadingQueueKind.SAVED_FOR_LATER)),
            readingQueueMemberships = listOf(BackupReadingQueueMembership(WORK_A, WORK_A, WORK_A)),
            annotations = listOf(BackupAnnotation(WORK_A, WORK_A)),
            readingSessions = listOf(BackupReadingSession(WORK_A)),
            readingFavorites = listOf(BackupReadingFavorite(WORK_A, kindRaw = "fandom", targetKey = "Fandom")),
            fandomReadWatermarks = listOf(BackupFandomReadWatermark(WORK_A, fandomName = "Fandom")),
            tombstones = listOf(BackupTombstone(WORK_A, WORK_A))
        )
        val raw = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(), manifest).jsonObject
        val extra = Json.parseToJsonElement("""{"future":[null,1,"x"]}""")
        val replaced = JsonObject(raw.mapValues { (_, value) ->
            if (value is JsonArray) JsonArray(value.map { element ->
                JsonObject(element.jsonObject + ("futureField" to extra))
            }) else value
        })
        val outgoing = JsonObject(raw.mapValues { (list, value) ->
            if (value !is JsonArray) value else JsonArray(value.map { element ->
                val record = element.jsonObject
                when (list) {
                    // The merge preserves a different local UUID for these identities.
                    "works", "bookmarks", "readingQueues", "readingFavorites", "fandomReadWatermarks" ->
                        JsonObject(record + ("id" to JsonPrimitive(WORK_REMOTE)))
                    "fonts" -> JsonObject(record + ("fileName" to JsonPrimitive("Cafe\u0301.otf")))
                    else -> JsonObject(record + ("id" to JsonPrimitive(WORK_A.uppercase())))
                }
            })
        })
        val carried = carryUnknownRecordKeys(outgoing, replaced)
        outgoing.forEach { (list, value) ->
            if (value is JsonArray) {
                assertEquals(list, extra, carried.getValue(list).jsonArray.single().jsonObject["futureField"])
            }
        }
    }

    @Test
    fun restoringTheSameArchiveTwiceLeavesOneFontFile() = runTest {
        settingsRepository.updateReaderFontId("custom:reader.otf")
        val incoming = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }
        val pack = KudosBackupPackage(
            remoteManifest(emptyList(), "2026-01-01T00:00:00Z").copy(
                fonts = listOf(BackupFont("Font", "reader.otf", "2026-01-01T00:00:00Z")),
                settings = BackupSettingsPayload(readerFontID = "custom:reader.otf")
            ), fontFilesByFileName = mapOf("reader.otf" to incoming)
        )
        val zip = BackupExporter.exportV2(pack)
        backupRepository.importV2ZipBytes(zip)
        backupRepository.importV2ZipBytes(zip)
        assertEquals(listOf("reader.otf"), fontFileStore.readAllFontFiles().keys.toList())
        assertEquals(listOf("reader.otf"), database.customFontDao().getAll().map { it.fileName })
        assertArrayEquals(incoming, fontFileStore.readFont("reader.otf"))
        assertEquals("custom:reader.otf", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun restoringTheSameCollidingArchiveTwiceReusesTheSuffixedFontAndRetainsTheLocalSelector() = runTest {
        val incoming = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }
        val local = "different local font".toByteArray()
        settingsRepository.updateReaderFontId("custom:reader.otf")
        fontFileStore.writeFont("reader.otf", local)
        database.customFontDao().upsert(CustomFont(name = "Local", fileName = "reader.otf", dateAdded = FIXED_CLOCK).toEntity())
        val pack = KudosBackupPackage(
            remoteManifest(emptyList(), "2026-01-01T00:00:00Z").copy(
                fonts = listOf(BackupFont("Remote", "reader.otf", "2026-01-01T00:00:00Z")),
                settings = BackupSettingsPayload(readerFontID = "custom:reader.otf")
            ), fontFilesByFileName = mapOf("reader.otf" to incoming)
        )
        val zip = BackupExporter.exportV2(pack)
        backupRepository.importV2ZipBytes(zip)
        backupRepository.importV2ZipBytes(zip)
        // One incoming copy alongside the original, which must also survive.
        assertEquals(setOf("reader.otf", "reader-restored-1.otf"), fontFileStore.readAllFontFiles().keys)
        assertEquals(2, database.customFontDao().getAll().size)
        assertArrayEquals(local, fontFileStore.readFont("reader.otf"))
        assertArrayEquals(incoming, fontFileStore.readFont("reader-restored-1.otf"))
        assertEquals("custom:reader.otf", settingsRepository.snapshot().reader.readerFontId)
        assertTrue(database.customFontDao().getAll().all { fontFileStore.fontExists(it.fileName) })
        val repeated = BackupMergeService.merge(
            backupRepository.captureLibrarySnapshot(pack.fontFilesByFileName.keys, pack.fontFilesByFileName), pack
        )
        assertEquals("custom:reader-restored-1.otf", repeated.snapshot.settings.readerFontID)
        assertTrue(repeated.fontFilesToWriteByFileName.isEmpty())
    }

    @Test
    fun carryingAnUnknownTombstoneKeyKeepsItsSignatureValid() {
        val pair = com.google.crypto.tink.subtle.Ed25519Sign.KeyPair.newKeyPair()
        val signed = TombstoneSigning.signWithRawKey(
            io.github.cidy02.kudos.core.model.SyncTombstone(
                id = ANDROID_ONE, recordID = WORK_A, recordTypeRaw = "savedWork",
                createdAt = FIXED_CLOCK, lastModifiedAt = FIXED_CLOCK
            ), pair.privateKey, pair.publicKey.toLowerHex()
        )
        val raw = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(),
            remoteManifest(emptyList(), FIXED_CLOCK.toString()).copy(tombstones = listOf(signed.toBackupTombstone()))
        ).jsonObject
        val tombstone = raw.getValue("tombstones").jsonArray.single().jsonObject
        val replaced = JsonObject(raw + ("tombstones" to JsonArray(listOf(
            JsonObject(tombstone + ("futureField" to JsonPrimitive("unsigned extra")))
        ))))
        val carried = carryUnknownRecordKeys(raw, replaced)
        val decoded = BackupJson.decodeFromJsonElement(KudosBackupManifest.serializer(), carried)
        assertEquals(signed.signature, decoded.tombstones.single().signature)
        assertTrue(TombstoneSigning.verify(decoded.tombstones.single().toSyncTombstone()))
    }

    @Test
    fun aCoercibleMalformedListInTheOldManifestDoesNotStopSync() = runTest {
        // Null on a defaulted list decodes as empty with BackupJson.coerceInputValues.
        val raw = BackupJson.encodeToJsonElement(KudosBackupManifest.serializer(),
            remoteManifest(emptyList(), "2026-01-01T00:00:00Z")).jsonObject
        writeChild(ensureKudosLibrary(), BackupPaths.MANIFEST, "application/json",
            BackupJson.encodeToString(JsonObject.serializer(), JsonObject(raw +
                ("fonts" to Json.parseToJsonElement("null")))).toByteArray())
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertNotNull(requireKudosLibrary().findFile(BackupPaths.MANIFEST))
    }

    @Test
    fun theManifestIsReplacedInPlaceAndThePreviousOneIsKeptAsTheBackup() = runTest {
        // iOS reads a folder with files and no manifest as a first write, and prunes by its
        // own library. So the manifest is never renamed away while its replacement goes in.
        seedFolder(remoteBackupWork(WORK_REMOTE, "Theirs", hasEpub = false))
        val previous = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        provider.renames.clear()

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertTrue("renamed: ${provider.renames}", provider.renames.isEmpty())
        val after = requireKudosLibrary()
        assertArrayEquals(previous, readDocument(after.findFile(BackupPaths.MANIFEST_BACKUP)!!))
        assertFalse(previous.contentEquals(readDocument(after.findFile(BackupPaths.MANIFEST)!!)))
    }

    // ------------------------------------------------------------------ (C)

    @Test
    fun equalLengthContentChangeIsRewrittenButIdenticalBytesAreSkipped() = runTest {
        val original = "AAAA".toByteArray() // 4 bytes
        val changed = "BBBB".toByteArray() // same length, different content
        assertEquals(original.size, changed.size)

        seedLocalWork(WORK_A, "Equal Length", original)
        val first = syncRepository.runSync()
        assertTrue(first is SyncResult.Success)

        val remoteWorks = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        val remoteEpub = epubIn(remoteWorks, WORK_A)
        assertNotNull(remoteEpub)
        assertArrayEquals(original, readDocument(remoteEpub!!))
        val writtenOnceAt = remoteEpub.lastModified()

        // Same-length edit that used to be skipped by length-only writeIfChanged.
        runBlocking {
            workFileStore.writeWorkEpub(WORK_A, changed)
        }
        clockInstant = FIXED_CLOCK.plusSeconds(30)
        val second = syncRepository.runSync()
        assertTrue(second is SyncResult.Success)

        val afterChange = epubIn(requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!, WORK_A)!!
        assertArrayEquals(
            "equal-length content change must propagate",
            changed,
            readDocument(afterChange)
        )
        assertTrue(
            "remote EPUB should have been rewritten",
            afterChange.lastModified() >= writtenOnceAt
        )
        val rewrittenAt = afterChange.lastModified()

        // Genuinely identical bytes must still be skipped (incremental sync).
        Thread.sleep(20)
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        val third = syncRepository.runSync()
        assertTrue(third is SyncResult.Success)
        val afterSkip = epubIn(requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!, WORK_A)!!
        assertArrayEquals(changed, readDocument(afterSkip))
        assertEquals(
            "identical content must not rewrite the remote EPUB",
            rewrittenAt,
            afterSkip.lastModified()
        )
    }

    // ------------------------------------------------------------------ (D)

    @Test
    fun pruningHappensAfterManifestCommitAndKeepsListedWorks() = runTest {
        seedLocalWork(WORK_A, "Kept Work", "keep-epub".toByteArray())

        // A folder whose manifest this run reads: without one it has no view of what the
        // folder lists, and prunes nothing.
        val worksDir = seedFolder()
        // Orphan asset that no local work references.
        writeChild(
            worksDir,
            "zzzzzzzz-zzzz-4zzz-8zzz-zzzzzzzzzzzz.epub",
            "application/epub+zip",
            "orphan-epub".toByteArray()
        )

        val result = syncRepository.runSync()
        assertTrue(result is SyncResult.Success)

        val afterWorks = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull(
            "work still listed in the freshly-written manifest keeps its EPUB",
            epubIn(afterWorks, WORK_A)
        )
        assertArrayEquals(
            "keep-epub".toByteArray(),
            readDocument(epubIn(afterWorks, WORK_A)!!)
        )
        assertTrue(
            "orphan assets are removed after the manifest commit",
            afterWorks.findFile("zzzzzzzz-zzzz-4zzz-8zzz-zzzzzzzzzzzz.epub") == null
        )

        val manifest = BackupValidator.decodeManifest(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        )
        assertTrue(manifest.works.any { it.id == WORK_A && it.hasEPUB })
    }

    @Test
    fun folderSyncRejectsInvalidFontBeforePersistenceAndRetainsSelector() = runTest {
        settingsRepository.updateReaderFontId("custom:local.otf")
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(
                BackupFont("Bad", "bad.ttf", "2026-06-26T12:00:00Z")
            ),
            settings = BackupSettingsPayload(readerFontID = "custom:bad.ttf")
        )
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray()
        )
        writeChild(
            fontsDir,
            "bad.ttf",
            "font/ttf",
            byteArrayOf(0x00, 0x01, 0x00, 0x00) + "not a font".toByteArray()
        )

        val result = syncRepository.runSync()

        assertTrue("invalid folder-sync font must abort: $result", result is SyncResult.Error)
        assertEquals("Invalid font file", (result as SyncResult.Error).message)
        assertEquals("custom:local.otf", settingsRepository.snapshot().reader.readerFontId)
        assertTrue(database.customFontDao().getAll().isEmpty())
        assertFalse(fontFileStore.fontExists("bad.ttf"))
    }

    @Test
    fun zipRestoreInstallsValidFontButRetainsDifferentLocalSelector() = runTest {
        settingsRepository.updateReaderFontId("custom:local-only.otf")
        val incomingBytes = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf")
            .use { it.readBytes() }
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(
                BackupFont("ZIP Font", "zip-font.otf", "2026-06-26T12:00:00Z")
            ),
            settings = BackupSettingsPayload(readerFontID = "custom:zip-font.otf")
        )
        val bytes = BackupExporter.exportV2(
            KudosBackupPackage(
                manifest = manifest,
                fontFilesByFileName = mapOf("zip-font.otf" to incomingBytes)
            )
        )

        backupRepository.importV2ZipBytes(bytes)

        assertArrayEquals(incomingBytes, fontFileStore.readFont("zip-font.otf"))
        assertEquals(listOf("zip-font.otf"), database.customFontDao().getAll().map { it.fileName })
        assertEquals("custom:local-only.otf", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun folderSyncPreservesAllLocalFontBytesAndRetainsSelector() = runTest {
        val localBytes = "local-font-bytes".toByteArray()
        val orphanBytes = "orphan-font-bytes".toByteArray()
        fontFileStore.writeFont("reader.otf", localBytes)
        fontFileStore.writeFont("reader-restored-1.otf", orphanBytes)
        database.customFontDao().upsert(
            CustomFont(name = "Local", fileName = "reader.otf").toEntity()
        )
        settingsRepository.updateReaderFontId("custom:reader.otf")

        val incomingBytes = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf")
            .use { it.readBytes() }
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(
                BackupFont("Remote", "reader.otf", "2026-06-26T12:00:00Z")
            ),
            settings = BackupSettingsPayload(readerFontID = "custom:reader-restored-2.otf")
        )
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray()
        )
        writeChild(fontsDir, "reader.otf", "font/otf", incomingBytes)

        val result = syncRepository.runSync()

        assertTrue("valid folder-sync font must restore: $result", result is SyncResult.Success)
        assertArrayEquals(localBytes, fontFileStore.readFont("reader.otf"))
        assertArrayEquals(orphanBytes, fontFileStore.readFont("reader-restored-1.otf"))
        assertArrayEquals(incomingBytes, fontFileStore.readFont("reader-restored-2.otf"))
        assertEquals(
            listOf("reader-restored-2.otf", "reader.otf"),
            database.customFontDao().getAll().map { it.fileName }.sorted()
        )
        assertEquals("custom:reader.otf", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun folderSyncCaseVariantCollisionPreservesLocalBytesAndUsesSuffix() = runTest {
        val localBytes = "occupied local bytes".toByteArray()
        fontFileStore.writeFont("reader.otf", localBytes)
        database.customFontDao().upsert(
            CustomFont(name = "Local", fileName = "reader.otf").toEntity()
        )
        settingsRepository.updateReaderFontId("custom:reader.otf")

        val incomingBytes = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf")
            .use { it.readBytes() }
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(BackupFont("Remote", "Reader.otf", "2026-06-26T12:00:00Z")),
            settings = BackupSettingsPayload(readerFontID = "custom:Reader.otf")
        )
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray()
        )
        writeChild(fontsDir, "Reader.otf", "font/otf", incomingBytes)

        val result = syncRepository.runSync()

        assertTrue("case-variant collision must restore with a suffix: $result", result is SyncResult.Success)
        assertArrayEquals(localBytes, fontFileStore.readFont("reader.otf"))
        assertArrayEquals(incomingBytes, fontFileStore.readFont("Reader-restored-1.otf"))
        assertEquals(
            setOf("reader.otf", "Reader-restored-1.otf"),
            database.customFontDao().getAll().map { it.fileName }.toSet()
        )
        assertEquals("custom:reader.otf", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun zipRestoreHealsMissingFileForExistingFontRowWithoutDuplicate() = runTest {
        val existing = CustomFont(name = "Local", fileName = "reader.otf")
        database.customFontDao().upsert(existing.toEntity())
        settingsRepository.updateReaderFontId("custom:reader.otf")
        val incomingBytes = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf")
            .use { it.readBytes() }
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(BackupFont("Remote", "Reader.otf", "2026-06-26T12:00:00Z")),
            settings = BackupSettingsPayload(readerFontID = "custom:Reader.otf")
        )
        val bytes = BackupExporter.exportV2(
            KudosBackupPackage(
                manifest = manifest,
                fontFilesByFileName = mapOf("Reader.otf" to incomingBytes)
            )
        )

        backupRepository.importV2ZipBytes(bytes)

        assertArrayEquals(incomingBytes, fontFileStore.readFont("reader.otf"))
        val restoredFonts = database.customFontDao().getAll()
        assertEquals(listOf(existing.id), restoredFonts.map { it.id })
        assertEquals(listOf("reader.otf"), restoredFonts.map { it.fileName })
        assertEquals("custom:reader.otf", settingsRepository.snapshot().reader.readerFontId)
    }

    // --------------------------------------------------------------- helpers

    // Cross-platform folder rules (brief 5a): what iOS's FolderSyncService writes, reads and keeps.

    @Test
    fun syncUpNamesEpubsTheWayIosDoes() = runTest {
        seedLocalWork(WORK_A, "Named for iOS", "epub-a".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        // iOS reads, and prunes, by `UUID.uuidString`: the UUID in capitals.
        val names = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!.listFiles().map { it.name }
        assertEquals(listOf("${WORK_A.uppercase()}.epub"), names)
    }

    @Test
    fun syncDownFindsAnEpubIosWrote() = runTest {
        val worksDir = seedFolder(
            remoteBackupWork(WORK_REMOTE, "From iPhone", hasEpub = true)
        )
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", REMOTE_EPUB)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(
            "the EPUB iOS wrote must reach this device",
            REMOTE_EPUB,
            Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE))
        )
        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertEquals(listOf("${WORK_REMOTE.uppercase()}.epub"), after.listFiles().map { it.name })
    }

    @Test
    fun aLowercaseEpubFromAnOlderAndroidBuildIsFoundAndGivenIosName() = runTest {
        val worksDir = seedFolder(
            remoteBackupWork(WORK_REMOTE, "From an older build", hasEpub = true)
        )
        writeChild(worksDir, "$WORK_REMOTE.epub", "application/epub+zip", REMOTE_EPUB)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE)))
        // One file for the work, under iOS's name, with the same bytes.
        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertEquals(listOf("${WORK_REMOTE.uppercase()}.epub"), after.listFiles().map { it.name })
        assertArrayEquals(REMOTE_EPUB, readDocument(epubIn(after, WORK_REMOTE)!!))
    }

    @Test
    fun syncUpKeepsTheEpubOfAListedWorkThisDeviceDoesNotHold() = runTest {
        // The manifest lists the work without an EPUB flag, so this device imports the row and
        // no file; another device's copy is still in the folder. iOS keeps every listed work's
        // EPUB "so one device can never discard an EPUB another device preserved".
        val worksDir = seedFolder(
            remoteBackupWork(WORK_REMOTE, "Held elsewhere", hasEpub = false)
        )
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", "theirs".toByteArray())
        writeChild(worksDir, "orphan-not-in-manifest.epub", "application/epub+zip", "orphan".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull("a listed work's EPUB is not an orphan", epubIn(after, WORK_REMOTE))
        assertTrue("a file no listed work owns is still pruned", after.findFile("orphan-not-in-manifest.epub") == null)
    }

    @Test
    fun nothingIsPrunedWhenTheFoldersManifestCannotBeRead() = runTest {
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        val kudos = ensureKudosLibrary()
        val worksDir = kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        // Unreadable, with no .bak: this run cannot know what the folder lists.
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", "{ not json".toByteArray())
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", "theirs".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull("this device's view was not current, so it prunes nothing", epubIn(after, WORK_REMOTE))
        assertNotNull(epubIn(after, WORK_A))
    }

    @Test
    fun syncDownRejectsAnInvalidEpubWithoutOverwritingTheLocalCopy() = runTest {
        // iOS `syncDownRejectsInvalidEPUBWithoutOverwritingLocalCopy`, with the folder's record
        // the newer one, so only the check on the bytes stands between them and the file.
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "Corrupt in the folder", hasEpub = true)
                .copy(lastModifiedAt = "2026-06-01T00:00:00Z"),
            exportedAt = "2026-06-02T00:00:00Z"
        )
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", "not-an-epub".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
        // The sync-up that follows puts the good copy back in the folder.
        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertArrayEquals(REMOTE_EPUB, readDocument(epubIn(after, WORK_A)!!))
    }

    @Test
    fun aCorrectedBookOfTheSameLengthIsStillFetched() = runTest {
        // iOS `EqualSizeEPUBStillSyncsTests`: equal size is not equal content, and the manifest's
        // digest is what tells them apart without reading every book on every sync.
        val corrected = sameLengthVariant(REMOTE_EPUB)
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "Corrected", hasEpub = true).copy(
                lastModifiedAt = "2026-06-01T00:00:00Z",
                epubDigest = BackupPaths.sha256(corrected)
            ),
            exportedAt = "2026-06-02T00:00:00Z"
        )
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", corrected)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun aManifestAnotherDeviceWritesWithNoDateStopsPublication() = runTest {
        // iOS `aStaleSyncUpKeepsAnotherDevicesRemoteEPUB`. The other device's write lands after
        // this run has read the folder and before it writes: the export asks the clock for its
        // date exactly there.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        ensureKudosLibrary()
        provider.reportedLastModified = 0
        var otherDeviceWrote = false
        val midSync = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = {
                if (!otherDeviceWrote) {
                    otherDeviceWrote = true
                    val worksDir = seedFolder(remoteBackupWork(WORK_REMOTE, "Theirs", hasEpub = true))
                    writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", REMOTE_EPUB)
                }
                clockInstant
            }
        )

        assertTrue(midSync.runSync() is SyncResult.Error)

        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull("a work this run never learned about keeps its EPUB", epubIn(after, WORK_REMOTE))
        assertNotNull(epubIn(after, WORK_A))
        val manifest = BackupValidator.decodeManifest(readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertTrue(manifest.works.any { it.id == WORK_REMOTE })
    }

    @Test
    fun withNoDigestAnEqualSizeCountsAsUnchanged() = runTest {
        // iOS's rule for a manifest written before digests existed: "the byte count is all
        // there is". It is also what lets a sync leave unchanged books unread.
        val sameSize = sameLengthVariant(REMOTE_EPUB)
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "Same size", hasEpub = true)
                .copy(lastModifiedAt = "2026-06-01T00:00:00Z"),
            exportedAt = "2026-06-02T00:00:00Z"
        )
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", sameSize)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun syncUpWritesTheDigestOfTheEpubItUploads() = runTest {
        // The digest in the manifest describes the bytes in the folder, whatever an earlier
        // manifest said: a stale one makes another device skip a changed book.
        database.workDao().upsert(
            SavedWork(
                id = WORK_A,
                title = "Uploaded",
                author = "Author",
                dateAdded = FIXED_CLOCK,
                isSaved = true,
                hasEpub = true,
                epubDigest = "stale"
            ).toEntity()
        )
        workFileStore.writeWorkEpub(WORK_A, REMOTE_EPUB)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val manifest = BackupValidator.decodeManifest(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        )
        assertEquals(BackupPaths.sha256(REMOTE_EPUB), manifest.works.single().epubDigest)
    }

    @Test
    fun aSyncDownLargerThanOneBatchStillBringsEveryEpub() = runTest {
        // One byte per batch: every EPUB arrives in a pass of its own, after the pass that
        // created its record.
        val oneAtATime = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = { clockInstant },
            maxEpubBatchBytes = 1
        )
        val other = sameLengthVariant(REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_REMOTE, "First", hasEpub = true),
            remoteBackupWork(WORK_A, "Second", hasEpub = true)
                .copy(sourceURL = "https://archiveofourown.org/works/1000")
        )
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", REMOTE_EPUB)
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", other)

        assertTrue(oneAtATime.runSync() is SyncResult.Success)

        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE)))
        assertArrayEquals(other, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun aFalseFlagCannotHideAPreservedLocalFileFromTheRestoreGate() = runTest {
        database.workDao().upsert(
            SavedWork(id = WORK_A, title = "Preserved", author = "Author",
                dateAdded = Instant.parse("2026-01-01T00:00:00Z"), hasEpub = false,
                epubPreservationStatusRaw = "preserved").toEntity()
        )
        workFileStore.writeWorkEpub(WORK_A, REMOTE_EPUB)
        val captured = backupRepository.captureLibrarySnapshot()
        assertTrue(WORK_A in captured.epubWorkIds)
        val incoming = KudosBackupPackage(
            remoteManifest(works = listOf(remoteBackupWork(WORK_A, "Incoming", hasEpub = true)),
                exportedAt = "2026-06-02T00:00:00Z"),
            mapOf(WORK_A to sameLengthVariant(REMOTE_EPUB)), emptyMap()
        )
        val merged = BackupMergeService.merge(captured, incoming)
        assertTrue(merged.epubFilesToWriteByWorkId.isEmpty())
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun laterBatchesReplaceExistingEpubsAndDoNotDuplicateCollidingFonts() = runTest {
        val corrected = sameLengthVariant(REMOTE_EPUB)
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        seedOlderLocalWork(WORK_REMOTE, REMOTE_EPUB)
        fontFileStore.writeFont("reader.otf", "local font bytes".toByteArray())
        database.customFontDao().upsert(CustomFont(name = "Local", fileName = "reader.otf").toEntity())
        val incomingFont = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "First corrected", hasEpub = true).copy(
                sourceURL = "", lastModifiedAt = "2026-06-01T00:00:00Z", epubDigest = BackupPaths.sha256(corrected)
            ),
            remoteBackupWork(WORK_REMOTE, "Second corrected", hasEpub = true).copy(
                sourceURL = "", lastModifiedAt = "2026-06-01T00:00:00Z", epubDigest = BackupPaths.sha256(corrected)
            ), exportedAt = "2026-06-02T00:00:00Z"
        )
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", corrected)
        writeChild(worksDir, "${WORK_REMOTE.uppercase()}.epub", "application/epub+zip", corrected)
        val kudos = requireKudosLibrary()
        val manifest = BackupValidator.decodeManifest(readDocument(kudos.findFile(BackupPaths.MANIFEST)!!)).copy(
            fonts = listOf(BackupFont("Remote", "reader.otf", "2026-01-01T00:00:00Z"))
        )
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", BackupJson.encodeToString(manifest).toByteArray())
        val fonts = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        writeChild(fonts, "reader.otf", "font/otf", incomingFont)
        val batched = SyncRepository(context, settingsRepository, backupRepository, workFileStore,
            fontFileStore, persistenceGate, clock = { clockInstant }, maxEpubBatchBytes = 1)
        assertTrue(batched.runSync() is SyncResult.Success)
        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE)))
        assertEquals(setOf("reader.otf", "reader-restored-1.otf"),
            database.customFontDao().getAll().map { it.fileName }.toSet())
    }

    @Test
    fun anEpubThatCannotBeWrittenHereFailsTheSyncAndIsTakenByTheNext() = runTest {
        // A failed write keeps the old bytes, under a row that now carries the folder's
        // clock. Reported as a success, as it was, this same run then uploaded those old
        // bytes as the newest copy, and every other device took them.
        val corrected = sameLengthVariant(REMOTE_EPUB)
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "Corrected", hasEpub = true).copy(
                sourceURL = "", lastModifiedAt = "2026-06-01T00:00:00Z", epubDigest = BackupPaths.sha256(corrected)
            ),
            exportedAt = "2026-06-02T00:00:00Z"
        )
        writeChild(worksDir, "${WORK_A.uppercase()}.epub", "application/epub+zip", corrected)
        val manifest = readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)

        val localWorks = workFileStore.workEpubPath(WORK_A).parent.toFile()
        localWorks.setWritable(false)
        try {
            assertTrue(syncRepository.runSync() is SyncResult.Error)
        } finally {
            localWorks.setWritable(true)
        }

        // Nothing was published: the folder's index and its copy are as they were.
        assertArrayEquals(manifest, readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertArrayEquals(corrected, readDocument(epubIn(worksDir, WORK_A)!!))

        // The first try already moved this device's clock up to the folder's. The EPUB is
        // offered again all the same, and an equal clock lets it in.
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertArrayEquals(corrected, readDocument(epubIn(after, WORK_A)!!))
    }

    @Test
    fun queuePreservationFromAnEarlierBatchDoesNotRejectALaterEpub() = runTest {
        val corrected = sameLengthVariant(REMOTE_EPUB)
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        seedOlderLocalWork(WORK_REMOTE, REMOTE_EPUB)
        val worksDir = seedFolder(
            remoteBackupWork(WORK_A, "First", hasEpub = true).copy(sourceURL = "",
                lastModifiedAt = "2026-06-01T00:00:00Z", epubDigest = BackupPaths.sha256(corrected)),
            remoteBackupWork(WORK_REMOTE, "Second", hasEpub = true).copy(sourceURL = "",
                lastModifiedAt = "2026-06-01T00:00:00Z", epubDigest = BackupPaths.sha256(corrected)),
            exportedAt = "2026-06-02T00:00:00Z"
        )
        val kudos = requireKudosLibrary()
        val queue = ReadingQueue(id = ANDROID_ONE, name = "Incoming queue",
            dateCreated = Instant.parse("2026-06-01T00:00:00Z"))
        val manifest = BackupValidator.decodeManifest(readDocument(kudos.findFile(BackupPaths.MANIFEST)!!)).copy(
            readingQueues = listOf(queue.toBackupReadingQueue(emptyList())),
            readingQueueMemberships = listOf(WORK_A, WORK_REMOTE).map { id ->
                ReadingQueueMembership(id = id, queueID = queue.id, workID = id,
                    queuedAt = queue.dateCreated).toBackupReadingQueueMembership()
            }
        )
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", BackupJson.encodeToString(manifest).toByteArray())
        writeChild(worksDir, BackupPaths.iosEpubAssetIdentifier(WORK_A), "application/epub+zip", corrected)
        writeChild(worksDir, BackupPaths.iosEpubAssetIdentifier(WORK_REMOTE), "application/epub+zip", corrected)
        val before = backupRepository.captureLibrarySnapshot()
        // This is the old per-batch sequence: metadata/membership for the second work
        // lands with the first file, and normalization preserves the second's old file.
        val firstBatch = BackupMergeService.merge(before,
            KudosBackupPackage(manifest, mapOf(WORK_A to corrected)))
        assertEquals("preserved", firstBatch.snapshot.works.single { it.id == WORK_REMOTE }.epubPreservationStatusRaw)
        val singlePass = BackupMergeService.merge(before,
            KudosBackupPackage(manifest, mapOf(WORK_A to corrected, WORK_REMOTE to corrected)))
        assertArrayEquals(corrected, singlePass.epubFilesToWriteByWorkId[WORK_REMOTE])

        val batched = SyncRepository(context, settingsRepository, backupRepository, workFileStore,
            fontFileStore, persistenceGate, clock = { clockInstant }, maxEpubBatchBytes = 1)
        assertTrue(batched.runSync() is SyncResult.Success)
        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
        assertArrayEquals(corrected, Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE)))
        assertEquals("preserved", database.workDao().getById(WORK_REMOTE)!!.epubPreservationStatusRaw)
    }

    @Test
    fun aFontLibraryOverTheRealAggregateLimitConvergesInTwoSyncs() = runTest {
        // As in iOS's real-cap test: a loadable OTF with zero padding after its tables.
        // Nine files at the 4 MiB entry cap exceed the real 32 MiB pass cap by one file.
        val source = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }
        assertTrue(source.size.toLong() <= BackupLimits.MAX_FONT_ENTRY_BYTES)
        val font = source.copyOf(BackupLimits.MAX_FONT_ENTRY_BYTES.toInt())
        val count = (BackupLimits.MAX_TOTAL_FONT_BYTES / font.size).toInt() + 1
        assertEquals(9, count)
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val fonts = (0 until count).map { index ->
            BackupFont("Font $index", "aggregate-$index.otf", "2026-06-26T12:00:00Z")
        }
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", BackupJson.encodeToString(
            remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(fonts = fonts)
        ).toByteArray())
        fonts.forEach { writeChild(fontsDir, it.fileName, "font/otf", font) }

        // The default repository has no injected allowance.
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertEquals(count - 1, database.customFontDao().getAll().size)
        val written = BackupValidator.decodeManifest(readDocument(kudos.findFile(BackupPaths.MANIFEST)!!))
        assertEquals(fonts.map { it.fileName }.toSet(), written.fonts.map { it.fileName }.toSet())
        assertEquals(count, fontsDir.listFiles().size)
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertEquals(count, database.customFontDao().getAll().size)
        fonts.forEach { assertArrayEquals(font, fontFileStore.readFont(it.fileName)) }
    }

    @Test
    fun aConversionRecordArrivingOneSyncAfterItsOriginalIsTaken() = runTest {
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = null)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertNull(workFileStore.readConversionRecord(WORK_REMOTE))
        val originals = requireKudosLibrary().findFile(BackupPaths.ORIGINALS_DIRECTORY)!!
        // Only the sidecar arrives; the manifest bytes are still our own last write.
        writeChild(originals, BackupPaths.iosConversionRecordFileName(WORK_REMOTE),
            "application/json", CONVERSION_RECORD)
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertArrayEquals(CONVERSION_RECORD, workFileStore.readConversionRecord(WORK_REMOTE))
        assertArrayEquals(ORIGINAL_PDF, workFileStore.readOriginal(WORK_REMOTE)!!.second)
    }

    @Test
    fun aConversionRecordBesideADifferentSameSizeOriginalIsNotTaken() = runTest {
        seedOlderLocalWork(WORK_REMOTE, REMOTE_EPUB)
        val localOriginal = ORIGINAL_PDF.copyOf().also { it[it.lastIndex] = 'X'.code.toByte() }
        workFileStore.writeOriginal(WORK_REMOTE, "pdf", localOriginal)
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = CONVERSION_RECORD)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertNull(workFileStore.readConversionRecord(WORK_REMOTE))
        assertArrayEquals(localOriginal, workFileStore.readOriginal(WORK_REMOTE)!!.second)
    }

    @Test
    fun aMatchingOriginalImportedHereGainsOnlyTheMissingRecord() = runTest {
        seedOlderLocalWork(WORK_REMOTE, REMOTE_EPUB)
        workFileStore.writeOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF)
        val path = workFileStore.originalFile(WORK_REMOTE)!!
        val modified = Files.getLastModifiedTime(path)
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = CONVERSION_RECORD)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertArrayEquals(CONVERSION_RECORD, workFileStore.readConversionRecord(WORK_REMOTE))
        assertArrayEquals(ORIGINAL_PDF, workFileStore.readOriginal(WORK_REMOTE)!!.second)
        assertEquals(modified, Files.getLastModifiedTime(path))
    }

    /** A library work older than anything the tests put in the folder, holding [epub]. */
    private suspend fun seedOlderLocalWork(id: String, epub: ByteArray) {
        database.workDao().upsert(
            SavedWork(
                id = id,
                title = "Valid here",
                author = "Author",
                dateAdded = Instant.parse("2026-01-01T00:00:00Z"),
                isSaved = true,
                hasEpub = true
            ).toEntity()
        )
        workFileStore.writeWorkEpub(id, epub)
    }

    /**
     * [epub] with one harmless byte changed (an entry's time in the ZIP's directory): the same
     * length, other content, and still a readable package.
     */
    private fun sameLengthVariant(epub: ByteArray): ByteArray {
        val copy = epub.copyOf()
        val directory = (0..copy.size - 4).first {
            copy[it] == 0x50.toByte() && copy[it + 1] == 0x4B.toByte() &&
                copy[it + 2] == 1.toByte() && copy[it + 3] == 2.toByte()
        }
        copy[directory + 12] = (copy[directory + 12] + 1).toByte()
        return copy
    }

    @Test
    fun syncDownSkipsOversizedFontAndRestoresUnrelatedState() = runTest {
        // iOS's test of the same name: one font over the per-file limit must not stop the sync.
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val manifest = remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
            fonts = listOf(BackupFont("Oversized", "oversized.ttf", "2026-06-26T12:00:00Z")),
            bookmarks = listOf(
                BackupBookmark(
                    title = "Unrelated Bookmark",
                    urlString = "https://example.com/safe",
                    dateAdded = "2026-01-01T00:00:00Z",
                    id = "77777777-7777-4777-8777-777777777777"
                )
            )
        )
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", BackupJson.encodeToString(manifest).toByteArray())
        writeChild(
            fontsDir,
            "oversized.ttf",
            "font/ttf",
            ByteArray(BackupLimits.MAX_FONT_ENTRY_BYTES.toInt() + 1)
        )

        val result = syncRepository.runSync()

        assertTrue("an oversized font must not abort the sync: $result", result is SyncResult.Success)
        assertTrue(database.customFontDao().getAll().isEmpty())
        assertFalse(fontFileStore.fontExists("oversized.ttf"))
        assertEquals(listOf("Unrelated Bookmark"), database.bookmarkDao().getAll().map { it.title })
        // Another device's font this one did not take is not this device's to prune, and
        // stays in the manifest this device writes: left out, the next device to prune
        // would delete it.
        assertNotNull(requireKudosLibrary().findFile(BackupPaths.FONTS_DIRECTORY)!!.findFile("oversized.ttf"))
        val written = BackupValidator.decodeManifest(readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertEquals(listOf("oversized.ttf"), written.fonts.map { it.fileName })
    }

    @Test
    fun aFontLibraryLargerThanOnePassArrivesOverSeveralSyncs() = runTest {
        // iOS `syncDownConvergesWhenFontLibraryExceedsAggregateCap`: over the allowance is a
        // reason to take fewer fonts in one pass, not to fail the sync for good.
        val font = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }
        val oneFontAtATime = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = { clockInstant },
            maxFontPassBytes = font.size.toLong()
        )
        val kudos = ensureKudosLibrary()
        val fontsDir = kudos.createDirectory(BackupPaths.FONTS_DIRECTORY)!!
        val manifest = BackupJson.encodeToString(
            remoteManifest(emptyList(), "2026-06-26T12:00:00Z").copy(
                fonts = listOf(
                    BackupFont("First", "first.otf", "2026-06-26T12:00:00Z"),
                    BackupFont("Second", "second.otf", "2026-06-26T12:00:00Z")
                )
            )
        ).toByteArray()
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", manifest)
        writeChild(fontsDir, "first.otf", "font/otf", font)
        writeChild(fontsDir, "second.otf", "font/otf", font)

        assertTrue(oneFontAtATime.runSync() is SyncResult.Success)
        assertEquals(listOf("first.otf"), database.customFontDao().getAll().map { it.fileName })
        // The font left for later is still in the folder.
        assertNotNull(requireKudosLibrary().findFile(BackupPaths.FONTS_DIRECTORY)!!.findFile("second.otf"))

        // And still in the manifest this device wrote, so no other device has to list it
        // again before the next sync can take it.
        val written = BackupValidator.decodeManifest(readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertEquals(listOf("first.otf", "second.otf"), written.fonts.map { it.fileName }.sorted())
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(oneFontAtATime.runSync() is SyncResult.Success)

        assertEquals(
            listOf("first.otf", "second.otf"),
            database.customFontDao().getAll().map { it.fileName }.sorted()
        )
    }

    @Test
    fun aReadableConflictCopyIsMergedAndRemoved() = runTest {
        // iOS `foldConflictContentsMergesAllInputs`: when two devices wrote at once, every
        // version is merged, so nothing either of them did is dropped.
        val kudos = ensureKudosLibrary()
        seedFolder(remoteBackupWork(WORK_REMOTE, "In the manifest", hasEpub = false))
        writeChild(
            kudos,
            "manifest (1).json",
            "application/json",
            BackupJson.encodeToString(
                remoteManifest(
                    works = listOf(
                        remoteBackupWork(WORK_A, "In the conflict copy", hasEpub = false)
                            .copy(sourceURL = "https://archiveofourown.org/works/1000")
                    ),
                    exportedAt = "2026-01-01T00:00:00Z"
                )
            ).toByteArray()
        )

        val result = syncRepository.runSync()

        assertEquals(SyncResult.Success(foldedConflicts = 1), result)
        assertEquals("In the manifest", database.workDao().getById(WORK_REMOTE)?.title)
        assertEquals("In the conflict copy", database.workDao().getById(WORK_A)?.title)
        assertTrue(requireKudosLibrary().findFile("manifest (1).json") == null)
    }

    @Test
    fun aSecondSyncWhileOneRunsIsSkipped() = runTest {
        // The lifecycle, the background worker and Sync Now can all ask at once. iOS refuses
        // the second (`operationGatePreventsInterleavedFolderSync`); here it is skipped.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        var second: SyncResult? = null
        lateinit var repository: SyncRepository
        repository = SyncRepository(
            context = context,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            persistenceGate = persistenceGate,
            clock = {
                // Asked in the middle of the first run's export.
                if (second == null) second = runBlocking { repository.runSync() }
                clockInstant
            }
        )

        assertTrue(repository.runSync() is SyncResult.Success)

        assertEquals(SyncResult.SkippedAlreadyRunning, second)
    }

    @Test
    fun pendingChangesClearOnlyAfterASyncThatWrote() = runTest {
        // iOS `dirtyFlagOnlyClearsAfterAnActualWrite`: "pending" means local changes not yet
        // written out, and a run that wrote nothing has not written them.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        settingsRepository.updateSyncHasPendingChanges(true)
        settingsRepository.updateSyncFolderUri(null)

        assertTrue(syncRepository.runSync() is SyncResult.Error)
        assertTrue(settingsRepository.snapshot().sync.hasPendingChanges)

        settingsRepository.updateSyncFolderUri(treeUri.toString())
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertFalse(settingsRepository.snapshot().sync.hasPendingChanges)
    }

    @Test
    fun syncUpDoesNotChangeLocalModificationDates() = runTest {
        // iOS's test of the same name: writing the library out is not an edit to it, or
        // every sync would make this device's copy of everything the newest.
        seedOlderLocalWork(WORK_A, REMOTE_EPUB)
        val before = database.workDao().getById(WORK_A)!!

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = database.workDao().getById(WORK_A)!!
        assertEquals(before.lastModifiedAt, after.lastModifiedAt)
        assertEquals(before.dateAdded, after.dateAdded)
    }

    // Originals (brief 5b): the file a converted import was made from, and the record of its
    // conversion, in the folder's `Originals/` as iOS keeps them.

    @Test
    fun syncUpWritesAnOriginalAndItsRecordUnderIosNames() = runTest {
        seedLocalWork(WORK_A, "Imported from a PDF", "local-a".toByteArray())
        workFileStore.writeOriginal(WORK_A, "pdf", ORIGINAL_PDF)
        workFileStore.writeConversionRecord(WORK_A, CONVERSION_RECORD)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val originals = requireKudosLibrary().findFile(BackupPaths.ORIGINALS_DIRECTORY)!!
        assertEquals(
            setOf("${WORK_A.uppercase()}.pdf", "${WORK_A.uppercase()}.conversion.json"),
            originals.listFiles().map { it.name }.toSet()
        )
        assertArrayEquals(ORIGINAL_PDF, readDocument(originals.findFile("${WORK_A.uppercase()}.pdf")!!))
        assertArrayEquals(
            CONVERSION_RECORD,
            readDocument(originals.findFile("${WORK_A.uppercase()}.conversion.json")!!)
        )
    }

    @Test
    fun syncDownBringsAnOriginalThisDeviceLacks() = runTest {
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = CONVERSION_RECORD)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val (extension, bytes) = workFileStore.readOriginal(WORK_REMOTE)!!
        assertEquals("pdf", extension)
        assertArrayEquals(ORIGINAL_PDF, bytes)
        assertArrayEquals(CONVERSION_RECORD, workFileStore.readConversionRecord(WORK_REMOTE))
    }

    @Test
    fun syncDownLeavesALocalOriginalAlone() = runTest {
        // The file the reader imported on this device, of another kind.
        seedOlderLocalWork(WORK_REMOTE, REMOTE_EPUB)
        workFileStore.writeOriginal(WORK_REMOTE, "html", "<html>imported here</html>".toByteArray())
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = CONVERSION_RECORD)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertEquals("html", workFileStore.readOriginal(WORK_REMOTE)!!.first)
        assertTrue(workFileStore.readConversionRecord(WORK_REMOTE) == null)
    }

    @Test
    fun anOriginalOfAWorkNoLongerListedIsPrunedAndAStrangersFileIsNot() = runTest {
        seedFolderOriginal(WORK_REMOTE, "pdf", ORIGINAL_PDF, record = null)
        val originals = requireKudosLibrary().findFile(BackupPaths.ORIGINALS_DIRECTORY)!!
        // A work no manifest lists, and a file that is not one of ours.
        writeChild(originals, "${WORK_A.uppercase()}.pdf", "application/octet-stream", ORIGINAL_PDF)
        writeChild(originals, "notes.txt", "application/octet-stream", "left by someone else".toByteArray())

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val after = requireKudosLibrary().findFile(BackupPaths.ORIGINALS_DIRECTORY)!!
        assertEquals(
            setOf("${WORK_REMOTE.uppercase()}.pdf", "notes.txt"),
            after.listFiles().map { it.name }.toSet()
        )
    }

    /** A folder whose manifest lists [workId], holding that work's original in `Originals/`. */
    private fun seedFolderOriginal(workId: String, extension: String, bytes: ByteArray, record: ByteArray?) {
        seedFolder(remoteBackupWork(workId, "Imported elsewhere", hasEpub = false))
        val kudos = requireKudosLibrary()
        val originals = kudos.findFile(BackupPaths.ORIGINALS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.ORIGINALS_DIRECTORY)!!
        writeChild(originals, "${workId.uppercase()}.$extension", "application/octet-stream", bytes)
        if (record != null) {
            writeChild(originals, "${workId.uppercase()}.conversion.json", "application/octet-stream", record)
        }
    }

    // The sync folder across the two apps (iOS `CrossPlatformFolderSyncTests`). The backup
    // goldens prove each side reads the other's manifest; these prove each side finds the
    // other's files, and leaves them in place.

    @Test
    fun aFolderIosWroteIsReadAndKept() = runTest {
        // Written by iOS's own FolderSyncService. `KUDOS_WRITE_GOLDEN=1` on iOS rewrites it.
        val fixture = iosSyncFolder()
        putFolder(fixture, ensureKudosLibrary())
        val before = relativeFiles(requireKudosLibrary()).keys

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val listed = BackupValidator.decodeManifest(File(fixture, BackupPaths.MANIFEST).readBytes())
            .works.filter { it.hasEPUB }
        assertEquals(2, listed.size)
        listed.forEach { work ->
            val inFolder = "${BackupPaths.WORKS_DIRECTORY}/${BackupPaths.iosEpubAssetIdentifier(work.id)}"
            assertArrayEquals(
                File(fixture, inFolder).readBytes(),
                Files.readAllBytes(workFileStore.workEpubPath(work.id))
            )
        }
        // The original of the converted import among them, and the record of its conversion.
        val originals = File(fixture, BackupPaths.ORIGINALS_DIRECTORY).listFiles().orEmpty()
        assertEquals(2, originals.size)
        originals.forEach { file ->
            val (workId, isRecord) = BackupPaths.parseOriginalFileName(file.name)!!
            val here = if (isRecord) {
                workFileStore.readConversionRecord(workId)
            } else {
                workFileStore.readOriginal(workId)?.second
            }
            assertArrayEquals(file.name, file.readBytes(), here)
        }
        // iOS's files are still there under their own names, with nothing put beside them.
        assertEquals(before, relativeFiles(requireKudosLibrary()).keys)
    }

    @Test
    fun theFolderAndroidWritesIsTheFixtureIosReads() = runTest {
        // The EPUB iOS's own fixture carries, so iOS's check of an incoming EPUB accepts it.
        val epub = File(iosSyncFolder(), BackupPaths.WORKS_DIRECTORY).listFiles()!!
            .first { it.extension == "epub" }.readBytes()
        listOf(ANDROID_ONE to 3001, ANDROID_TWO to 3002).forEach { (id, ao3WorkId) ->
            database.workDao().upsert(
                SavedWork(
                    id = id,
                    title = "Folder Sync $ao3WorkId",
                    author = "Archive Author",
                    sourceUrl = "https://archiveofourown.org/works/$ao3WorkId",
                    dateAdded = FIXED_CLOCK,
                    isSaved = true,
                    hasEpub = true
                ).toEntity()
            )
            workFileStore.writeWorkEpub(id, epub)
        }
        // The first is a converted import: its original and the record of its conversion.
        workFileStore.writeOriginal(ANDROID_ONE, "html", "<html><body><p>From Android.</p></body></html>".toByteArray())
        workFileStore.writeConversionRecord(ANDROID_ONE, CONVERSION_RECORD)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = relativeFiles(requireKudosLibrary())
        val golden = fixturePath("KudosTests/Fixtures/cross-platform/android-sync-folder/KudosLibrary")
        if (System.getProperty("kudos.writeGolden") == "true") {
            golden.deleteRecursively()
            written.forEach { (path, file) ->
                File(golden, path).apply { parentFile.mkdirs() }.writeBytes(readDocument(file))
            }
        }
        // The names are the contract here; what the manifest holds is the backup goldens' business.
        assertEquals(
            written.keys,
            golden.walkTopDown().filter { it.isFile && !it.name.startsWith(".") }
                .map { it.relativeTo(golden).path }.toSet()
        )
    }

    @Test
    fun aPromisedEpubThatDidNotArriveIsPublishedByBackupAndSync() = runTest {
        seedFolder(remoteBackupWork(WORK_REMOTE, "Promised", hasEpub = true))

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val local = database.workDao().getById(WORK_REMOTE)!!
        assertFalse(local.hasEpub)
        assertTrue(local.remoteEpubPending)
        assertFalse(workFileStore.workEpubExists(WORK_REMOTE))
        val published = BackupValidator.decodeManifest(
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!)
        )
        assertTrue(published.works.single().hasEPUB)
        val backup = BackupImporter.importV2Zip(backupRepository.exportV2ZipBytes())
        assertTrue(backup.manifest.works.single().hasEPUB)
        assertTrue(backup.epubFilesByWorkId.isEmpty())
        assertFalse(BackupJson.encodeToString(backup.manifest).contains("remoteEpubPending"))
    }

    @Test
    fun aPromisedEpubIsTakenWhenItArrivesAndTheFlagClears() = runTest {
        val works = seedFolder(remoteBackupWork(WORK_REMOTE, "Promised", hasEpub = true))
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertTrue(database.workDao().getById(WORK_REMOTE)!!.remoteEpubPending)
        writeChild(works, BackupPaths.iosEpubAssetIdentifier(WORK_REMOTE), "application/epub+zip", REMOTE_EPUB)

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val local = database.workDao().getById(WORK_REMOTE)!!
        assertTrue(local.hasEpub)
        assertFalse(local.remoteEpubPending)
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_REMOTE)))
    }

    @Test
    fun aRemovedDownloadStaysRemovedUnlessAnotherManifestPromisesIt() = runTest {
        seedLocalWork(WORK_A, "Local", REMOTE_EPUB)
        val repository = WorkRepository(database, workFileStore, clock = { clockInstant })
        // Removing bytes explicitly clears any previously pending promise.
        database.workDao().upsert(database.workDao().getById(WORK_A)!!.copy(remoteEpubPending = true))
        repository.deleteLocalEpub(WORK_A)
        assertFalse(database.workDao().getById(WORK_A)!!.remoteEpubPending)
        val entry = remoteBackupWork(WORK_A, "Local", hasEpub = false)
        val works = seedFolder(entry)
        writeChild(works, BackupPaths.iosEpubAssetIdentifier(WORK_A), "application/epub+zip", REMOTE_EPUB)

        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertFalse(workFileStore.workEpubExists(WORK_A))
        assertFalse(database.workDao().getById(WORK_A)!!.hasEpub)
        assertNotNull("the folder's copy is retained", epubIn(works, WORK_A))

        // The peer advertises its copy; iOS's hasEPUB loop now permits fetching it.
        seedFolder(entry.copy(hasEPUB = true))
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertTrue(database.workDao().getById(WORK_A)!!.hasEpub)
        assertFalse(database.workDao().getById(WORK_A)!!.remoteEpubPending)
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun aFailedEpubInstallationKeepsThePromiseUntilTheWriteSucceeds() = runTest {
        val pack = KudosBackupPackage(
            remoteManifest(listOf(remoteBackupWork(WORK_REMOTE, "Promised", hasEpub = true)),
                BackupValidator.formatInstant(FIXED_CLOCK)),
            epubFilesByWorkId = mapOf(WORK_REMOTE to REMOTE_EPUB)
        )
        // A nonempty directory at the file destination makes both move attempts fail.
        val destination = workFileStore.workEpubPath(WORK_REMOTE)
        Files.createDirectories(destination)
        val blocker = destination.resolve("blocking-file")
        Files.write(blocker, byteArrayOf(1))
        try {
            backupRepository.importPackage(pack)
            fail("A failed asset write must fail the import")
        } catch (_: java.io.IOException) {
            val held = database.workDao().getById(WORK_REMOTE)!!
            assertFalse(held.hasEpub)
            assertTrue(held.remoteEpubPending)
            assertTrue(held.toDomain().toBackupWork().hasEPUB)
        } finally {
            Files.deleteIfExists(blocker)
            Files.deleteIfExists(destination)
        }

        backupRepository.importPackage(pack)
        assertTrue(database.workDao().getById(WORK_REMOTE)!!.hasEpub)
        assertFalse(database.workDao().getById(WORK_REMOTE)!!.remoteEpubPending)
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(destination))
    }

    @Test
    fun aKeptFlagClearedInANewerSnapshotClearsHereAndTheEpubStays() = runTest {
        assertKeptFlagMerge(localSaved = true, incomingSaved = false, incomingNewer = true, expectedSaved = false)
    }

    @Test
    fun aKeptFlagClearedInAnOlderSnapshotDoesNotClearHere() = runTest {
        assertKeptFlagMerge(localSaved = true, incomingSaved = false, incomingNewer = false, expectedSaved = true)
    }

    @Test
    fun anOlderSnapshotCannotSetAKeptFlagThatWasClearedHere() = runTest {
        assertKeptFlagMerge(localSaved = false, incomingSaved = true, incomingNewer = false, expectedSaved = false)
    }

    /** iOS `KudosBackupService.apply`: the newer snapshot's kept flag, and never a file deleted. */
    private suspend fun assertKeptFlagMerge(
        localSaved: Boolean,
        incomingSaved: Boolean,
        incomingNewer: Boolean,
        expectedSaved: Boolean
    ) {
        val local = SavedWork(
            id = WORK_A, title = "Local", author = "Author", dateAdded = FIXED_CLOCK.minusSeconds(120),
            lastModifiedAt = FIXED_CLOCK, isSaved = localSaved, hasEpub = true
        )
        database.workDao().upsert(local.toEntity())
        workFileStore.writeWorkEpub(WORK_A, REMOTE_EPUB)
        val incoming = local.copy(
            lastModifiedAt = if (incomingNewer) FIXED_CLOCK.plusSeconds(60) else FIXED_CLOCK.minusSeconds(60),
            isSaved = incomingSaved, hasEpub = false
        ).toBackupWork()
        backupRepository.importPackage(KudosBackupPackage(
            remoteManifest(listOf(incoming), BackupValidator.formatInstant(FIXED_CLOCK.plusSeconds(120)))
        ))

        val merged = database.workDao().getById(WORK_A)!!
        assertEquals(expectedSaved, merged.isSaved)
        assertTrue(merged.hasEpub)
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun aQueueOnlyWorkStaysQueueOnlyAndKeepsItsEpub() = runTest {
        val local = SavedWork(
            id = WORK_A, title = "Queue only", author = "Author", dateAdded = FIXED_CLOCK.minusSeconds(120),
            lastModifiedAt = FIXED_CLOCK, isSaved = false, isQueuedForLater = true, hasEpub = true
        )
        database.workDao().upsert(local.toEntity())
        workFileStore.writeWorkEpub(WORK_A, REMOTE_EPUB)
        val queue = ReadingQueue(id = ANDROID_TWO, name = "Queue", dateCreated = FIXED_CLOCK)
        database.readingQueueDao().upsertQueue(queue.toEntity())
        database.readingQueueDao().upsertMembership(
            ReadingQueueMembership(
                id = "44444444-4444-4444-8444-444444444444", queueID = queue.id, workID = WORK_A,
                queuedAt = FIXED_CLOCK
            ).toEntity()
        )
        val incoming = local.copy(lastModifiedAt = FIXED_CLOCK.plusSeconds(60), hasEpub = false).toBackupWork()

        backupRepository.importPackage(KudosBackupPackage(
            remoteManifest(listOf(incoming), BackupValidator.formatInstant(FIXED_CLOCK.plusSeconds(120)))
        ))

        val merged = database.workDao().getById(WORK_A)!!
        assertFalse("a merge must not promote a queue-only work into the library", merged.isSaved)
        assertTrue(merged.isQueuedForLater)
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun aDownloadRemovedHereStaysRemovedThroughThisDevicesNextSync() = runTest {
        // The folder's manifest, written by this device a moment ago, still says the work has
        // an EPUB, and the folder still holds the file. Merged again, that manifest brought
        // the download straight back.
        seedLocalWork(WORK_A, "Local", REMOTE_EPUB)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        val works = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull(epubIn(works, WORK_A))

        WorkRepository(database, workFileStore, clock = { clockInstant }).deleteLocalEpub(WORK_A)
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertFalse(workFileStore.workEpubExists(WORK_A))
        assertFalse(database.workDao().getById(WORK_A)!!.hasEpub)
        val written = BackupValidator.decodeManifest(readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST)!!))
        assertFalse(written.works.single { it.id.equals(WORK_A, ignoreCase = true) }.hasEPUB)
        assertNotNull("the folder keeps its copy", epubIn(works, WORK_A))
    }

    @Test
    fun anEpubThatWentMissingFromThisDeviceIsTakenBackFromTheFolder() = runTest {
        // Not removed by the reader: the file is just gone. The work still says it has one,
        // so the device is owed it, and the folder's copy is how it comes back.
        seedLocalWork(WORK_A, "Local", REMOTE_EPUB)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        Files.delete(workFileStore.workEpubPath(WORK_A))

        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        clockInstant = FIXED_CLOCK.plusSeconds(120)
        assertTrue(syncRepository.runSync() is SyncResult.Success)

        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
        val row = database.workDao().getById(WORK_A)!!
        assertTrue(row.hasEpub)
        assertFalse(row.remoteEpubPending)
    }

    @Test
    fun replaceKeepsOmittedCollectionsAndQueuesForNinetyDaysWithRestorableMemberships() = runTest {
        seedLocalWork(WORK_A, "Kept work", REMOTE_EPUB)
        val collection = WorkCollection(
            id = ANDROID_ONE, name = "Omitted collection", dateAdded = FIXED_CLOCK, workIds = listOf(WORK_A)
        )
        val queue = ReadingQueue(id = ANDROID_TWO, name = "Omitted queue", dateCreated = FIXED_CLOCK)
        val membership = ReadingQueueMembership(
            id = WORK_REMOTE, queueID = queue.id, workID = WORK_A, queuedAt = FIXED_CLOCK, note = "Restore this note"
        )
        database.collectionDao().upsert(collection.toEntity())
        database.collectionDao().addWork(CollectionWorkCrossRef(collection.id, WORK_A))
        database.readingQueueDao().upsertQueue(queue.toEntity())
        database.readingQueueDao().upsertMembership(membership.toEntity())
        val pack = KudosBackupPackage(remoteManifest(
            listOf(database.workDao().getById(WORK_A)!!.toDomain().toBackupWork()),
            BackupValidator.formatInstant(FIXED_CLOCK)
        ))

        backupRepository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)

        val deletedCollection = database.collectionDao().getDeleted().single()
        val queueRepository = ReadingQueueRepository(database, clock = { clockInstant })
        val deletedQueue = queueRepository.listRecentlyDeletedQueues().single()
        val deadline = FIXED_CLOCK.plus(WorkRepository.RECOVERY_WINDOW)
        assertEquals(FIXED_CLOCK, deletedCollection.deletedAt)
        assertEquals(deadline, deletedCollection.permanentDeletionScheduledAt)
        assertEquals(FIXED_CLOCK, deletedQueue.deletedAt)
        assertEquals(deadline, deletedQueue.permanentDeletionScheduledAt)
        assertEquals(listOf(WORK_A), database.collectionDao().getWorkIdsForCollection(collection.id))
        assertEquals(listOf(membership.toEntity()), database.readingQueueDao().getMembershipsForQueue(queue.id))
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())

        clockInstant = FIXED_CLOCK.plusSeconds(86_400)
        backupRepository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)
        assertEquals(deadline, database.collectionDao().getById(collection.id)!!.permanentDeletionScheduledAt)
        assertEquals(deadline, database.readingQueueDao().getQueueById(queue.id)!!.permanentDeletionScheduledAt)

        val workRepository = WorkRepository(database, workFileStore, clock = { clockInstant })
        assertEquals(listOf(WORK_A), workRepository.restoreCollectionFromRecentlyDeleted(collection.id)!!.workIds)
        assertFalse(queueRepository.restoreQueueFromRecentlyDeleted(queue.id)!!.isDeleted)
        assertEquals(listOf(membership.toEntity()), database.readingQueueDao().getMembershipsForQueue(queue.id))
        assertArrayEquals(REMOTE_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_A)))
    }

    @Test
    fun replaceLeavesTheOmittedSystemQueueAndItsMembershipsUntouched() = runTest {
        seedLocalWork(WORK_A, "Queued work", REMOTE_EPUB)
        val queue = ReadingQueue(
            id = ANDROID_ONE, name = ReadingQueueKind.SAVED_FOR_LATER_NAME,
            kindRaw = ReadingQueueKind.SAVED_FOR_LATER, sortOrder = ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER,
            dateCreated = FIXED_CLOCK, notes = "Local system queue"
        ).toEntity()
        val membership = ReadingQueueMembership(
            id = ANDROID_TWO, queueID = queue.id, workID = WORK_A, queuedAt = FIXED_CLOCK, note = "Local note"
        ).toEntity()
        database.readingQueueDao().upsertQueue(queue)
        database.readingQueueDao().upsertMembership(membership)

        backupRepository.importPackage(KudosBackupPackage(remoteManifest(emptyList(),
            BackupValidator.formatInstant(FIXED_CLOCK))), BackupImportMode.REPLACE_LIBRARY)

        assertEquals(queue, database.readingQueueDao().getQueueById(queue.id))
        assertEquals(listOf(membership), database.readingQueueDao().getMembershipsForQueue(queue.id))
        assertTrue(ReadingQueueRepository(database).listRecentlyDeletedQueues().isEmpty())
    }

    @Test
    fun replaceMarksOmittedAnnotationsPendingDeletionWithoutLosingTheirRows() = runTest {
        seedLocalWork(WORK_A, "Annotated work", REMOTE_EPUB)
        val annotation = ReadingAnnotation(
            id = ANDROID_ONE, workID = WORK_A, kindRaw = "highlight", locatorString = "{\"href\":\"chapter.xhtml\"}",
            selectedText = "Kept highlight", note = "Kept note", createdAt = FIXED_CLOCK
        ).toEntity()
        database.annotationDao().upsert(annotation)
        val pack = KudosBackupPackage(remoteManifest(emptyList(), BackupValidator.formatInstant(FIXED_CLOCK)))

        backupRepository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)

        val deleted = database.annotationDao().getById(annotation.id)!!
        assertEquals(annotation.copy(isPendingDeletion = true, deletedAt = FIXED_CLOCK), deleted)
        clockInstant = FIXED_CLOCK.plusSeconds(86_400)
        backupRepository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)
        assertEquals(deleted, database.annotationDao().getById(annotation.id))
    }

    @Test
    fun aFailedBackgroundRunStoresItsMessageAndTheNextSuccessClearsIt() = runTest {
        val kudos = ensureKudosLibrary()
        writeChild(kudos, BackupPaths.MANIFEST, "application/json", "{\"version\":99}".toByteArray())
        // No page state or Sync Now handler participates in these repository calls.
        val failed = syncRepository.runSync()
        assertTrue(failed is SyncResult.Error)
        assertEquals((failed as SyncResult.Error).message, settingsRepository.snapshot().sync.lastError)
        assertNull(settingsRepository.snapshot().sync.lastSyncAt)
        val backup = BackupImporter.importV2Zip(backupRepository.exportV2ZipBytes())
        assertFalse(BackupJson.encodeToString(backup.manifest.settings).contains("lastError"))
        settingsRepository.replaceAll(io.github.cidy02.kudos.core.model.KudosSettings.Defaults)
        assertEquals(failed.message, settingsRepository.snapshot().sync.lastError)

        seedFolder()
        assertTrue(syncRepository.runSync() is SyncResult.Success)
        assertNull(settingsRepository.snapshot().sync.lastError)
        assertEquals(FIXED_CLOCK, settingsRepository.snapshot().sync.lastSyncAt)
    }

    @Test
    fun anEarlySyncFailureAlsoStoresItsMessage() = runTest {
        settingsRepository.updateSyncFolderUri(null)
        val result = syncRepository.runSync()
        assertEquals(SyncResult.Error("No sync folder selected."), result)
        assertEquals("No sync folder selected.", settingsRepository.snapshot().sync.lastError)
    }

    @Test
    fun androidAddsItsWorkToTheIosFolderWithoutPruningEitherDevicesAssets() = runTest {
        val fixture = iosSyncFolder()
        val iosManifestBytes = File(fixture, BackupPaths.MANIFEST).readBytes()
        val iosManifest = BackupValidator.decodeManifest(iosManifestBytes)
        // An outgoing snapshot must not predate the snapshot it just read.
        clockInstant = BackupValidator.parseInstant(iosManifest.exportedAt, "exportedAt").plusSeconds(60)
        putFolder(fixture, ensureKudosLibrary())
        val before = relativeFiles(requireKudosLibrary()).mapValues { (_, file) -> readDocument(file) }
        val androidEpub = EpubBuilder.buildEpub("Android's own work", "<p>Added after the iOS sync.</p>")
        val androidOriginal = "<html><body><p>Android's original.</p></body></html>".toByteArray()
        val androidRecord =
            """{"format":"html","originalFileName":"android.html","converterVersion":1,"convertedAt":721692800}"""
                .toByteArray()
        database.workDao().upsert(SavedWork(
            id = ANDROID_ONE, title = "Android's own work", author = "Android Author",
            sourceUrl = "https://archiveofourown.org/works/3001", ao3WorkID = 3001,
            dateAdded = clockInstant, lastModifiedAt = clockInstant, hasEpub = true, isSaved = true
        ).toEntity())
        workFileStore.writeWorkEpub(ANDROID_ONE, androidEpub)
        workFileStore.writeOriginal(ANDROID_ONE, "html", androidOriginal)
        workFileStore.writeConversionRecord(ANDROID_ONE, androidRecord)
        provider.deletions.clear()

        assertTrue(syncRepository.runSync() is SyncResult.Success)

        val written = relativeFiles(requireKudosLibrary())
        val androidAssets = mapOf(
            "${BackupPaths.WORKS_DIRECTORY}/${BackupPaths.iosEpubAssetIdentifier(ANDROID_ONE)}" to androidEpub,
            "${BackupPaths.ORIGINALS_DIRECTORY}/${BackupPaths.iosOriginalFileName(ANDROID_ONE, "html")}" to androidOriginal,
            "${BackupPaths.ORIGINALS_DIRECTORY}/${BackupPaths.iosConversionRecordFileName(ANDROID_ONE)}" to androidRecord
        )
        assertEquals("only Android's three asset files were added", before.keys + androidAssets.keys, written.keys)
        before.filterKeys { it != BackupPaths.MANIFEST }.forEach { (path, bytes) ->
            assertArrayEquals("iOS asset kept at $path", bytes, readDocument(written.getValue(path)))
        }
        androidAssets.forEach { (path, bytes) ->
            assertArrayEquals("Android asset added at $path", bytes, readDocument(written.getValue(path)))
        }
        assertTrue("no document was pruned: ${provider.deletions}", provider.deletions.isEmpty())
        assertArrayEquals(iosManifestBytes,
            readDocument(requireKudosLibrary().findFile(BackupPaths.MANIFEST_BACKUP)!!))
        val manifestBytes = readDocument(written.getValue(BackupPaths.MANIFEST))
        val manifest = BackupValidator.decodeManifest(manifestBytes)
        assertEquals(3, manifest.works.size)
        assertEquals(iosManifest.works.map { it.id }.toSet() + ANDROID_ONE, manifest.works.map { it.id }.toSet())
        assertTrue(manifest.works.all { it.hasEPUB })
        assertEquals(BackupVersion.CURRENT, manifest.version)
        assertEquals("android", manifest.exportedBy?.platform)
        // iOS's top-level fields Android has no table for survive the shared-folder write too.
        assertEquals(Json.parseToJsonElement(iosManifestBytes.toString(Charsets.UTF_8)).jsonObject["pronunciations"],
            Json.parseToJsonElement(manifestBytes.toString(Charsets.UTF_8)).jsonObject["pronunciations"])

        // Opt-in fixture generation, as for the Android-only golden: the assets and the live
        // manifest, without the .bak. It is kept beside iOS's folder in these test resources
        // and not under `KudosTests/`: Xcode bundles every file there flat, and this folder
        // repeats names the Android-only golden already has.
        val golden = fixturePath(
            "android/app/src/test/resources/cross-platform/android-after-ios-sync-folder/KudosLibrary"
        )
        if (System.getProperty("kudos.writeGolden") == "true") {
            golden.deleteRecursively()
            written.forEach { (path, file) ->
                File(golden, path).apply { parentFile.mkdirs() }.writeBytes(readDocument(file))
            }
        }
        // The folder iOS's `aFolderBothAppsWroteIsReadAndKept` reads is the one this writes.
        assertEquals(
            written.keys,
            golden.walkTopDown().filter { it.isFile && !it.name.startsWith(".") }
                .map { it.relativeTo(golden).path }.toSet()
        )
    }

    private fun iosSyncFolder(): File = File(
        checkNotNull(javaClass.classLoader?.getResource("cross-platform/ios-sync-folder/KudosLibrary")) {
            "Missing the iOS sync folder fixture. Regenerate with KUDOS_WRITE_GOLDEN=1 on iOS."
        }.toURI()
    )

    private fun fixturePath(relative: String): File {
        var candidate = File(System.getProperty("user.dir")).absoluteFile
        while (!File(candidate, "KudosTests").isDirectory && candidate.parentFile != null) {
            candidate = candidate.parentFile
        }
        return File(candidate, relative)
    }

    /** Recreates [source], a folder on disk, inside [target] through the documents provider. */
    private fun putFolder(source: File, target: DocumentFile) {
        source.listFiles().orEmpty().forEach { child ->
            when {
                child.isDirectory ->
                    putFolder(child, target.findFile(child.name) ?: target.createDirectory(child.name)!!)
                !child.name.startsWith(".") -> writeChild(
                    target,
                    child.name,
                    if (child.extension == "epub") "application/epub+zip" else "application/json",
                    child.readBytes()
                )
            }
        }
    }

    /**
     * Every file under [dir] by its path relative to it. Hidden files and the manifest's
     * backup copy (Android keeps one, iOS does not) are not what the two apps must agree on.
     */
    private fun relativeFiles(dir: DocumentFile, prefix: String = ""): Map<String, DocumentFile> =
        dir.listFiles().flatMap { file ->
            val name = file.name ?: return@flatMap emptyList()
            when {
                file.isDirectory -> relativeFiles(file, "$prefix$name/").toList()
                name.startsWith(".") || name.endsWith(".bak") -> emptyList()
                else -> listOf("$prefix$name" to file)
            }
        }.toMap()

    /** A folder holding a manifest that lists [works]; returns its Works directory. */
    private fun seedFolder(vararg works: BackupWork, exportedAt: String = "2026-01-01T00:00:00Z"): DocumentFile {
        val kudos = ensureKudosLibrary()
        val manifest = remoteManifest(works = works.toList(), exportedAt = exportedAt)
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray(Charsets.UTF_8)
        )
        return kudos.findFile(BackupPaths.WORKS_DIRECTORY) ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
    }

    /** A work's EPUB in the folder, whichever case its name has. */
    private fun epubIn(dir: DocumentFile, workId: String): DocumentFile? =
        dir.listFiles().firstOrNull { it.name.equals("$workId.epub", ignoreCase = true) }

    private suspend fun seedLocalWork(id: String, title: String, epub: ByteArray) {
        database.workDao().upsert(
            SavedWork(
                id = id,
                title = title,
                author = "Author",
                dateAdded = FIXED_CLOCK,
                isSaved = true,
                hasEpub = true
            ).toEntity()
        )
        workFileStore.writeWorkEpub(id, epub)
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

    private fun writeChild(
        dir: DocumentFile,
        name: String,
        mime: String,
        bytes: ByteArray
    ) {
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

    private fun assertNoTempManifests(kudos: DocumentFile) {
        val temps = kudos.listFiles().filter {
            it.name?.startsWith(BackupPaths.MANIFEST_TEMP) == true
        }
        assertTrue(
            "temp manifest(s) left behind: ${temps.map { it.name }}",
            temps.isEmpty()
        )
    }

    private fun remoteManifest(
        works: List<BackupWork>,
        exportedAt: String
    ): KudosBackupManifest {
        return KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = exportedAt,
            exportedBy = BackupExportedBy(
                platform = "android",
                appVersion = "test",
                schemaVersion = BackupVersion.CURRENT
            ),
            works = works,
            settings = BackupSettingsPayload()
        )
    }

    private fun remoteBackupWork(
        id: String,
        title: String,
        hasEpub: Boolean
    ): BackupWork {
        return BackupWork(
            id = id,
            title = title,
            author = "Remote Author",
            summary = "",
            sourceURL = "https://archiveofourown.org/works/999",
            dateAdded = "2026-01-01T00:00:00Z",
            isFavorite = false,
            isSaved = true,
            isFinished = false,
            hasEPUB = hasEpub,
            isComplete = true,
            lastSpineIndex = 0,
            lastScrollFraction = 0.0
        )
    }

    companion object {
        private val FIXED_CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private const val WORK_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        private const val WORK_REMOTE = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        // Letters in both: an id of digits alone reads the same in either case, and the case of
        // the file name is the thing under test.
        private const val ANDROID_ONE = "3000abcd-0000-4000-8000-00000000000a"
        private const val ANDROID_TWO = "3000abcd-0000-4000-8000-00000000000b"

        private val ORIGINAL_PDF = "%PDF-1.7 the original".toByteArray()
        private val CONVERSION_RECORD =
            """{"converterVersion":4,"format":"pdf","originalFileName":"story.pdf","convertedAt":0}""".toByteArray()

        /** A real EPUB: sync-down only installs bytes that are a readable package. */
        private val REMOTE_EPUB = EpubBuilder.buildEpub("Remote", "<p>Text.</p>")
    }
}
