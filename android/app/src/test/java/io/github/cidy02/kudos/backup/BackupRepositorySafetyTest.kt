package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupRepositorySafetyTest {
    private val devices = mutableListOf<Device>()

    @After
    fun tearDown() {
        devices.forEach(Device::close)
        TombstoneSigning.resetForTests()
    }

    @Test
    fun metadataCheckValidatesTheRealSnapshotWithoutChangingRowsOrAssets() = runTest {
        val device = device()
        device.seed()
        val rows = device.database.workDao().getAllIncludingDeleted()
        val assets = device.assetFiles()
        device.repository.metadataCheck.run()
        assertEquals("Ready", device.repository.metadataCheck.status.value.title)
        assertEquals(rows, device.database.workDao().getAllIncludingDeleted())
        assertEquals(assets, device.assetFiles())
        assertEquals(0, device.workFiles.attempts)
        device.database.workDao().upsert(work("not-a-uuid", "Broken metadata").toEntity())
        device.repository.metadataCheck.run()
        assertEquals("Needs Retry", device.repository.metadataCheck.status.value.title)
        device.database.workDao().deleteById("not-a-uuid")
        device.repository.metadataCheck.run()
        assertEquals("Ready", device.repository.metadataCheck.status.value.title)
    }

    @Test
    fun secondEpubFailureRestoresOverwrittenBytesAndEveryRow() = runTest {
        assertSecondEpubFailure(firstId = A)
    }

    @Test
    fun secondEpubFailureRemovesNewlyInstalledBytesAndEveryRow() = runTest {
        assertSecondEpubFailure(firstId = NEW)
    }

    private suspend fun assertSecondEpubFailure(firstId: String) {
        val device = device()
        device.seed()
        val before = device.repository.captureLibrarySnapshot()
        val rowsBefore = device.database.workDao().getAllIncludingDeleted()
        val filesBefore = device.assetFiles()
        device.workFiles.failAtWrite = 2

        val pack = packageOf(listOf(work(firstId, "Archive first"), work(B, "Archive second")))
        try {
            // Exercise the screen's ZIP import path as well as the shared apply path.
            device.repository.importV2ZipBytes(BackupExporter.exportV2(pack), BackupImportMode.REPLACE_LIBRARY)
            fail("The second EPUB write must fail")
        } catch (error: IOException) {
            assertEquals("Injected EPUB write failure", error.message)
        }

        assertEquals(2, device.workFiles.attempts)
        assertEquals(before, device.repository.captureLibrarySnapshot())
        assertEquals(rowsBefore, device.database.workDao().getAllIncludingDeleted())
        assertTrue(device.database.tagDao().getAll().isEmpty())
        assertEquals(filesBefore, device.assetFiles())
        assertEquals("Local first", device.database.workDao().getById(A)!!.title)
        assertFalse(device.database.workDao().getById(OMITTED)!!.isDeleted)
        assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(device.workFiles.workEpubPath(B)))
    }

    @Test
    fun lateFontFailureAlsoUndoesEarlierEpubAndRows() = runTest {
        val device = device()
        device.seed()
        val before = device.repository.captureLibrarySnapshot()
        val font = CustomFont(name = "Archive font", fileName = "archive.ttf", dateAdded = NOW)
        val base = packageOf(listOf(work(A, "Archive first")))
        val pack = base.copy(
            manifest = base.manifest.copy(
                fonts = listOf(BackupFont(font.name, font.fileName, NOW.toString()))
            ),
            fontFilesByFileName = mapOf(font.fileName to byteArrayOf(1, 2, 3))
        )
        val merge = BackupMergeService.merge(before, pack, BackupImportMode.REPLACE_LIBRARY, now = NOW)
        assertTrue(merge.fontFilesToWriteByFileName.isNotEmpty())
        // Created after merge: apply must reach this late destination conflict.
        Files.createDirectories(device.root.resolve("fonts/${font.fileName}"))
        val filesBefore = device.assetFiles()
        try {
            device.repository.applyMergeResult(merge)
            fail("The font destination is a directory")
        } catch (error: IOException) {
            assertTrue(error.message.orEmpty().contains(font.fileName))
        }
        assertEquals(1, device.workFiles.attempts)
        assertEquals(before, device.repository.captureLibrarySnapshot())
        assertEquals(filesBefore, device.assetFiles())
        assertTrue(Files.isDirectory(device.root.resolve("fonts/${font.fileName}")))
    }

    @Test
    fun replaceNeverOverwritesADifferentFontInstalledAfterCapture() = runTest {
        val device = device()
        val pack = KudosBackupPackage(
            manifest = BackupLibrarySnapshot().toV2Manifest(NOW).copy(
                fonts = listOf(BackupFont("Archive", "reader.ttf", NOW.toString()))
            ),
            fontFilesByFileName = mapOf("reader.ttf" to byteArrayOf(1, 2, 3))
        )
        val merge = BackupMergeService.merge(
            device.repository.captureLibrarySnapshot(), pack, BackupImportMode.REPLACE_LIBRARY, now = NOW
        )
        val localBytes = byteArrayOf(4, 5, 6)
        FontFileStore(device.root).writeFont("reader.ttf", localBytes)
        val summary = device.repository.applyMergeResult(merge)
        assertArrayEquals(localBytes, Files.readAllBytes(device.root.resolve("fonts/reader.ttf")))
        assertEquals(1, summary.concurrentRowsDeferred)
    }

    // iOS WorkSearchIndexTests: restored metadata and user tags are searchable immediately.
    /**
     * A61 #10. In a merge an existing work keeps its own tags (the backup's are for new works),
     * so A carries a local tag its stored index does not have yet, and B arrives with the
     * backup's. Both are searchable by their tags after the restore.
     */
    @Test fun restoreReindexesNewAndAlreadyCurrentWorksAfterAttachingTags() = runTest {
        val device = device()
        val indexed = io.github.cidy02.kudos.works.WorkSearchIndex.reindex(work(A, "Local"))
        device.database.workDao().upsert(indexed.toEntity())
        val local = io.github.cidy02.kudos.data.local.entity.TagEntity("local-tag", "Wintër Favorites", NOW)
        device.database.tagDao().upsert(local)
        device.database.tagDao().addToWork(io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef(A, local.id))
        val incoming = listOf(work(A, "Local"), work(B, "Heroine"))
        val pack = KudosBackupPackage(manifest = BackupLibrarySnapshot(works = incoming,
            userTagsByWorkId = mapOf(B to listOf("Wintër Favorites"))).toV2Manifest(NOW))
        device.repository.importPackage(pack, BackupImportMode.MERGE)
        for (id in listOf(A, B)) {
            val restored = device.database.workDao().getById(id)!!.toDomain()
            assertEquals(io.github.cidy02.kudos.works.WorkSearchIndex.CURRENT_VERSION, restored.searchIndexVersion)
            assertTrue(id, io.github.cidy02.kudos.works.WorkSearchIndex.matches(restored, listOf("winter", "favorites")))
            assertEquals(NOW, restored.lastModifiedAt)
        }
    }

    @Test
    fun successfulReplaceKeepsNewFilesAndDiscardsUndoAsides() = runTest {
        val device = device()
        device.seed()
        device.repository.importPackage(packageOf(listOf(work(A, "Archive first"))), BackupImportMode.REPLACE_LIBRARY)
        assertEquals("Archive first", device.database.workDao().getById(A)!!.title)
        assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(device.workFiles.workEpubPath(A)))
        assertTrue(device.database.workDao().getById(OMITTED)!!.isDeleted)
        assertFalse(device.assetFiles().keys.any { it.endsWith(BackupFileUndo.UNDO_SUFFIX) || it.endsWith(".tmp") })
    }

    @Test
    fun interruptedReplaceRestoresAsidesWithoutDestinations() = runTest {
        val device = device()
        val paths = recoveryPaths(device)
        val undo = BackupFileUndo()
        paths.forEach { path ->
            Files.createDirectories(path.parent)
            Files.write(path, LOCAL_EPUB)
            undo.beforeWrite(path)
            assertFalse(Files.exists(path))
            assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(path.resolveSibling(
                "${path.fileName}${BackupFileUndo.UNDO_SUFFIX}"
            )))
        }

        // Simulate a new process: the launch repair uses no in-memory journal.
        device.repository.recoverInterruptedReplace()
        device.repository.recoverInterruptedReplace()

        paths.forEach { assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(it)) }
        assertEquals(paths.size, device.assetFiles().size)
        assertFalse(device.assetFiles().keys.any { it.endsWith(BackupFileUndo.UNDO_SUFFIX) })
    }

    @Test
    fun interruptedReplaceDiscardsAsidesBesideDestinations() = runTest {
        val device = device()
        val paths = recoveryPaths(device)
        val undo = BackupFileUndo()
        paths.forEach { path ->
            Files.createDirectories(path.parent)
            Files.write(path, LOCAL_EPUB)
            undo.beforeWrite(path)
            Files.write(path, INCOMING_EPUB)
        }

        device.repository.recoverInterruptedReplace()
        device.repository.recoverInterruptedReplace()

        paths.forEach { assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(it)) }
        assertEquals(paths.size, device.assetFiles().size)
        assertFalse(device.assetFiles().keys.any { it.endsWith(BackupFileUndo.UNDO_SUFFIX) })
    }

    private fun recoveryPaths(device: Device) = listOf(
        device.workFiles.workEpubPath(A), device.root.resolve("fonts/reader.ttf"),
        device.workFiles.originalPath(A, "pdf"), device.workFiles.conversionRecordPath(A)
    )

    @Test
    fun everyReplaceEntryRecoversInterruptedFilesBeforeWriting() = runTest {
        for (entry in listOf("package", "zip", "planned")) {
            val device = device()
            device.seed()
            val before = device.repository.captureLibrarySnapshot()
            val filesBefore = device.assetFiles()
            val pack = packageOf(listOf(work(A, "Archive first")))
            val merge = BackupMergeService.merge(before, pack, BackupImportMode.REPLACE_LIBRARY, now = NOW)
            BackupFileUndo().beforeWrite(device.workFiles.workEpubPath(A))
            device.workFiles.failAtWrite = 1
            try {
                when (entry) {
                    "package" -> device.repository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)
                    "zip" -> device.repository.importV2ZipBytes(
                        BackupExporter.exportV2(pack), BackupImportMode.REPLACE_LIBRARY
                    )
                    else -> device.repository.applyMergeResult(merge)
                }
                fail("The EPUB write must fail")
            } catch (error: IOException) {
                assertEquals("Injected EPUB write failure", error.message)
            }
            assertEquals(1, device.workFiles.attempts)
            assertEquals(before, device.repository.captureLibrarySnapshot())
            assertEquals(filesBefore, device.assetFiles())
        }
    }

    @Test
    fun mergeAndReconcileRetainTheirPartialApplyAndPendingFileFlags() = runTest {
        for (mode in listOf(BackupImportMode.MERGE, BackupImportMode.RECONCILE)) {
            val device = device()
            device.workFiles.failAtWrite = 2
            try {
                device.repository.importPackage(packageOf(listOf(work(A, "First"), work(B, "Second"))), mode)
                fail("The second EPUB write must fail")
            } catch (error: IOException) {
                assertEquals("Injected EPUB write failure", error.message)
            }
            assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(device.workFiles.workEpubPath(A)))
            assertEquals(2, device.database.workDao().getAllIncludingDeleted().size)
            val pending = device.database.workDao().getById(B)!!
            assertFalse(pending.hasEpub)
            assertTrue(pending.remoteEpubPending)
        }
    }

    @Test
    fun lateOriginalFailureUndoesEpubFontOriginalAndConversionRecordDeletion() = runTest {
        val device = device()
        device.seed()
        val record = "{\"converterVersion\":4}".toByteArray()
        device.workFiles.writeConversionRecord(A, record) // Orphan record: writeOriginal removes it.
        val before = device.repository.captureLibrarySnapshot()
        val base = packageOf(listOf(work(A, "Archive first"), work(B, "Archive second")))
        val pack = base.copy(
            manifest = base.manifest.copy(fonts = listOf(BackupFont("New font", "new.ttf", NOW.toString()))),
            fontFilesByFileName = mapOf("new.ttf" to byteArrayOf(1, 2, 3))
        )
        val merge = BackupMergeService.merge(before, pack, BackupImportMode.REPLACE_LIBRARY, now = NOW)
        Files.createDirectories(device.root.resolve("originals/$B.pdf"))
        val filesBefore = device.assetFiles()
        try {
            device.repository.applyMergeResult(merge, linkedMapOf(
                "${A.uppercase()}.pdf" to "%PDF-1.7 first original".toByteArray(),
                "${B.uppercase()}.pdf" to "%PDF-1.7 second original".toByteArray()
            ))
            fail("The second original destination is a directory")
        } catch (error: IOException) {
            assertTrue(error.message.orEmpty().contains("$B.pdf"))
        }
        assertEquals(2, device.workFiles.attempts)
        assertEquals(before, device.repository.captureLibrarySnapshot())
        assertEquals(filesBefore, device.assetFiles())
        assertArrayEquals(record, device.workFiles.readConversionRecord(A))
        assertFalse(device.workFiles.originalExists(A))
        assertFalse(Files.exists(device.root.resolve("fonts/new.ttf")))
    }

    @Test
    fun exportReportsTheBookWhosePromisedFileIsMissing() = runTest {
        val device = device()
        device.database.workDao().upsert(work(A, "Missing Book").toEntity())
        val result = device.repository.exportV2Zip()
        assertEquals(listOf("Missing Book"), result.omittedBookTitles)
        assertTrue(result.omittedFontNames.isEmpty())
        val archive = BackupImporter.importV2Zip(result.bytes)
        assertTrue(archive.epubFilesByWorkId.isEmpty())
        assertTrue(archive.manifest.works.single().hasEPUB)
        assertTrue(result.toUserMessage().contains("1 book was left out because its file is missing: Missing Book."))
    }

    @Test
    fun exportReportsEmptyEpubAndMissingAndEmptyFonts() = runTest {
        val device = device()
        device.database.workDao().upsert(work(A, "Empty Book").toEntity())
        Files.createDirectories(device.root.resolve("works"))
        Files.write(device.workFiles.workEpubPath(A), byteArrayOf())
        listOf("missing.ttf", "empty.ttf").forEach { name ->
            device.database.customFontDao().upsert(CustomFont(name = name, fileName = name, dateAdded = NOW).toEntity())
        }
        Files.createDirectories(device.root.resolve("fonts"))
        Files.write(device.root.resolve("fonts/empty.ttf"), byteArrayOf())
        val result = device.repository.exportV2Zip()
        assertEquals(listOf("Empty Book"), result.omittedBookTitles)
        assertEquals(setOf("missing.ttf", "empty.ttf"), result.omittedFontNames.toSet())
        assertTrue(BackupImporter.importV2Zip(result.bytes).fontFilesByFileName.isEmpty())
        assertTrue(result.toUserMessage().contains("2 fonts were left out because their files are missing:"))
    }

    @Test
    fun completeExportReportsNoOmissionsAndIgnoresMetadataOnlyWorks() = runTest {
        val device = device()
        device.database.workDao().upsert(work(A, "Downloaded").toEntity())
        device.database.workDao().upsert(work(B, "Metadata only").copy(hasEpub = false).toEntity())
        device.workFiles.writeWorkEpub(A, LOCAL_EPUB)
        val result = device.repository.exportV2Zip()
        assertTrue(result.omittedBookTitles.isEmpty())
        assertTrue(result.omittedFontNames.isEmpty())
        assertEquals("Exported ${result.bytes.size / 1024} KB as a v8 .kudosbackup ZIP.", result.toUserMessage())
        assertEquals(setOf(A), BackupImporter.importV2Zip(result.bytes).epubFilesByWorkId.keys)
    }

    @Test
    fun omissionMessageNamesThreeTitlesThenTheRemainingCount() {
        val result = BackupExportResult(byteArrayOf(), listOf("One", "Two", "Three", "Four", "Five"))
        assertTrue(result.toUserMessage().contains(
            "5 books were left out because their files are missing: One, Two, Three and 2 more."
        ))
        assertFalse(result.toUserMessage().contains("Four"))
    }

    @Test
    fun omissionMessageUsesSingularPluralAndNaturalListsForBooksAndFonts() {
        val names = listOf("A", "B", "C", "D", "E")
        val expected = listOf("A", "A and B", "A, B and C", "A, B, C and 1 more", "A, B, C and 2 more")
        for (count in 1..5) {
            val values = names.take(count)
            val result = BackupExportResult(byteArrayOf(), values, values)
            val books = if (count == 1) "book was" else "books were"
            val fonts = if (count == 1) "font was" else "fonts were"
            val reason = if (count == 1) "its file is missing" else "their files are missing"
            assertEquals(
                "Exported 0 KB as a v8 .kudosbackup ZIP. " +
                    "$count $books left out because $reason: ${expected[count - 1]}. " +
                    "$count $fonts left out because $reason: ${expected[count - 1]}.",
                result.toUserMessage()
            )
        }
    }

    private fun device() = Device().also(devices::add)

    private class FailingWorkFileStore(root: Path) : WorkFileStore(root) {
        var failAtWrite: Int? = null
        var attempts = 0

        override suspend fun writeWorkEpub(workId: String, bytes: ByteArray): FileWriteResult {
            attempts++
            if (attempts == failAtWrite) return FileWriteResult.Failure("Injected EPUB write failure")
            return super.writeWorkEpub(workId, bytes)
        }
    }

    private class Device : AutoCloseable {
        private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val root: Path = Files.createTempDirectory("kudos-backup-safety")
        private val settingsRoot = Files.createTempDirectory("kudos-backup-safety-settings")
        val database: KudosDatabase = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java
        ).allowMainThreadQueries().build()
        val workFiles = FailingWorkFileStore(root)
        val repository = BackupRepository(
            database, workFiles, FontFileStore(root),
            SettingsRepository(PreferenceDataStoreFactory.create(
                scope = scope, produceFile = { settingsRoot.resolve("settings.preferences_pb").toFile() }
            )), PersistenceGate(), clock = { NOW }, appVersion = "test"
        )

        suspend fun seed() {
            listOf(work(A, "Local first"), work(B, "Local second"), work(OMITTED, "Omitted")).forEach {
                database.workDao().upsert(it.toEntity())
                workFiles.writeWorkEpub(it.id, LOCAL_EPUB)
            }
            database.bookmarkDao().upsert(Bookmark(
                title = "Local link", urlString = "https://example.com/local", dateAdded = NOW
            ).toEntity())
            database.syncTombstoneDao().upsert(SyncTombstoneEntity(
                id = "3fa00000-0000-4000-8000-000000000010", recordID = NEW,
                recordTypeRaw = "savedWork", createdAt = NOW, lastModifiedAt = NOW
            ))
            workFiles.attempts = 0
        }

        fun assetFiles(): Map<String, List<Byte>> = Files.walk(root).use { paths ->
            paths.filter { Files.isRegularFile(it) }.toList().associate {
                root.relativize(it).toString() to Files.readAllBytes(it).toList()
            }
        }

        override fun close() {
            database.close()
            scope.cancel()
            root.toFile().deleteRecursively()
            settingsRoot.toFile().deleteRecursively()
        }
    }

    private companion object {
        const val A = "3fa00000-0000-4000-8000-000000000001"
        const val B = "3fa00000-0000-4000-8000-000000000002"
        const val OMITTED = "3fa00000-0000-4000-8000-000000000003"
        const val NEW = "3fa00000-0000-4000-8000-000000000000"
        val NOW: Instant = Instant.parse("2026-01-15T12:00:00Z")
        val LOCAL_EPUB = EpubBuilder.buildEpub("Local", "<p>Local bytes.</p>")
        val INCOMING_EPUB = EpubBuilder.buildEpub("Incoming", "<p>Incoming bytes.</p>")

        fun work(id: String, title: String) = SavedWork(
            id = id, title = title, author = "Author", dateAdded = NOW.minusSeconds(60), lastModifiedAt = NOW
        )

        fun packageOf(works: List<SavedWork>) = KudosBackupPackage(
            manifest = BackupLibrarySnapshot(
                works = works, userTagsByWorkId = works.associate { it.id to listOf("Archive tag") }
            ).toV2Manifest(NOW),
            epubFilesByWorkId = works.associate { it.id to INCOMING_EPUB }
        )
    }
}
