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
            afterWorks.findFile("$WORK_REMOTE.epub")
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
        val remoteEpub = remoteWorks.findFile("$WORK_A.epub")
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

        val afterChange = requireKudosLibrary()
            .findFile(BackupPaths.WORKS_DIRECTORY)!!
            .findFile("$WORK_A.epub")!!
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
        val afterSkip = requireKudosLibrary()
            .findFile(BackupPaths.WORKS_DIRECTORY)!!
            .findFile("$WORK_A.epub")!!
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
            afterWorks.findFile("$WORK_A.epub")
        )
        assertArrayEquals(
            "keep-epub".toByteArray(),
            readDocument(afterWorks.findFile("$WORK_A.epub")!!)
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
    }
}
