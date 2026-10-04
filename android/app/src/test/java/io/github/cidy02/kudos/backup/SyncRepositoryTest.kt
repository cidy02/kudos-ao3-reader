package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.documentfile.provider.DocumentFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
    fun corruptPrimaryManifestFallsBackToBakAndSelfHeals() = runTest {
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
        // Orphan that is NOT in the bak; after a successful recovery+export the
        // orphan is pruned, but the listed work's EPUB must remain.
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
        // Orphan removal is the post-commit prune (D); recovery itself must not
        // have emptied Works/ before export rewrote the manifest.
        assertNotNull(after.findFile(BackupPaths.MANIFEST))
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

        val kudos = ensureKudosLibrary()
        val worksDir = kudos.findFile(BackupPaths.WORKS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
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
    fun aManifestAnotherDeviceWritesMidSyncStopsThePrune() = runTest {
        // iOS `aStaleSyncUpKeepsAnotherDevicesRemoteEPUB`. The other device's write lands after
        // this run has read the folder and before it writes: the export asks the clock for its
        // date exactly there.
        seedLocalWork(WORK_A, "Local", "local-a".toByteArray())
        ensureKudosLibrary()
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

        assertTrue(midSync.runSync() is SyncResult.Success)

        val after = requireKudosLibrary().findFile(BackupPaths.WORKS_DIRECTORY)!!
        assertNotNull("a work this run never learned about keeps its EPUB", epubIn(after, WORK_REMOTE))
        assertNotNull(epubIn(after, WORK_A))
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
        // Another device's font this one did not take is not this device's to prune.
        assertNotNull(requireKudosLibrary().findFile(BackupPaths.FONTS_DIRECTORY)!!.findFile("oversized.ttf"))
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

        // The device that owns both fonts syncs again and lists them again.
        writeChild(requireKudosLibrary(), BackupPaths.MANIFEST, "application/json", manifest)
        clockInstant = FIXED_CLOCK.plusSeconds(60)
        assertTrue(oneFontAtATime.runSync() is SyncResult.Success)

        assertEquals(
            listOf("first.otf", "second.otf"),
            database.customFontDao().getAll().map { it.fileName }.sorted()
        )
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

        /** A real EPUB: sync-down only installs bytes that are a readable package. */
        private val REMOTE_EPUB = EpubBuilder.buildEpub("Remote", "<p>Text.</p>")
    }
}
