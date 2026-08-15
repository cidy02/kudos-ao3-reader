package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.documentfile.provider.DocumentFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production-entry-point coverage for Phase 1 backup trust:
 * [BackupRepository.importPackage] and folder-sync ingest via [SyncRepository].
 *
 * Mutation A: restore unconditional tombstone adopt in merge →
 * [importPackageDoesNotAdoptIncomingTombstones] goes red.
 * Mutation B: drop tombstones on file import but still adopt on folder sync →
 * [folderSyncIngestDoesNotAdoptIncomingTombstones] goes red.
 * File Merge add-only vs folder-sync LWW: [importPackageMergeDoesNotOverwriteExistingOverlap]
 * vs [importPackageReconcileStillLwwUpdatesOverlap] / [folderSyncIngestStillLwwUpdatesOverlap].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupTrustPhase1Test {
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
        val settingsDir = Files.createTempDirectory("kudos-trust-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )

        val filesRoot = Files.createTempDirectory("kudos-trust-files")
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

        safRoot = Files.createTempDirectory("kudos-trust-saf").toFile()
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
    fun importPackageDoesNotAdoptIncomingTombstones() = runTest {
        val pack = packageWithWorkAndTombstone(
            workId = WORK_K,
            workTitle = "Should still insert",
            tombstoneRecordId = WORK_K,
            ao3WorkId = 4242
        )

        val summary = backupRepository.importPackage(pack)

        assertEquals(1, summary.worksCreated)
        assertEquals(0, summary.worksSuppressed)
        assertNotNull(database.workDao().getById(WORK_K))
        assertTrue(
            "incoming unsigned tombstones must not be written to Room",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun importPackageDoesNotSuppressUsingIncomingTombstonesThenLaterMergeInserts() = runTest {
        val hostile = packageWithWorkAndTombstone(
            workId = WORK_J,
            workTitle = "Hostile first file",
            tombstoneRecordId = WORK_K,
            ao3WorkId = 999
        )
        backupRepository.importPackage(hostile)
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())

        val later = packageWithWorkAndTombstone(
            workId = WORK_K,
            workTitle = "Later real backup",
            tombstoneRecordId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
            ao3WorkId = 1
        )
        val summary = backupRepository.importPackage(later)

        assertEquals(1, summary.worksCreated)
        assertEquals(0, summary.worksSuppressed)
        assertNotNull("later merge must still insert K; no standing suppressor", database.workDao().getById(WORK_K))
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())
    }

    @Test
    fun localTombstonesStillSuppressOnImportPackage() = runTest {
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = WORK_K,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse("2026-06-01T00:00:00Z"),
                lastModifiedAt = Instant.parse("2026-06-01T00:00:00Z"),
                sourceURL = "https://archiveofourown.org/works/4242",
                ao3WorkID = 4242
            ).toEntity()
        )

        val pack = packageWithWorkAndTombstone(
            workId = WORK_K,
            workTitle = "Stale copy",
            tombstoneRecordId = WORK_K,
            ao3WorkId = 4242,
            lastModifiedAt = "2026-01-01T00:00:00Z"
        )
        val summary = backupRepository.importPackage(pack)

        assertEquals(1, summary.worksSuppressed)
        assertNull(database.workDao().getById(WORK_K))
        assertEquals(1, database.syncTombstoneDao().getAll().size)
    }

    @Test
    fun replaceLibraryRemovesLocalOnlyWorkWithoutMintingTombstones() = runTest {
        database.workDao().upsert(savedWork(WORK_J, "Keep me out of the snapshot").toEntity())
        database.workDao().upsert(savedWork(WORK_K, "Will be replaced").toEntity())

        val pack = packageWithWorkAndTombstone(
            workId = WORK_K,
            workTitle = "Snapshot K",
            tombstoneRecordId = WORK_J,
            ao3WorkId = 111
        )
        val summary = backupRepository.importPackage(pack, BackupImportMode.REPLACE_LIBRARY)

        assertEquals(1, summary.worksRemoved)
        assertNull("J must leave this device's library", database.workDao().getById(WORK_J))
        assertEquals("Snapshot K", database.workDao().getById(WORK_K)?.title)
        assertTrue(
            "replace must not persist the file tombstone or mint one for J",
            database.syncTombstoneDao().getAll().isEmpty()
        )

        val later = packageWithWorkAndTombstone(
            workId = WORK_J,
            workTitle = "J from later backup",
            tombstoneRecordId = "ffffffff-ffff-4fff-8fff-ffffffffffff",
            ao3WorkId = 222
        )
        val laterSummary = backupRepository.importPackage(later)
        assertEquals(1, laterSummary.worksCreated)
        assertEquals("J from later backup", database.workDao().getById(WORK_J)?.title)
    }

    @Test
    fun importPackageMergeDoesNotOverwriteExistingOverlap() = runTest {
        seedLocalOverlapWork()
        val incoming = overlapPackage(
            title = "Incoming Title",
            lastModifiedAt = "2026-07-01T00:00:00Z",
            lastSpineIndex = 8,
            lastScrollFraction = 0.8,
            userTags = listOf("Incoming"),
            epubBytes = "incoming-epub".toByteArray(),
            tombstoneRecordId = WORK_J
        )

        val summary = backupRepository.importPackage(incoming, BackupImportMode.MERGE)

        val stored = database.workDao().getById(WORK_K)
        assertNotNull(stored)
        assertEquals("Local Title", stored?.title)
        assertEquals(3, stored?.lastSpineIndex)
        assertEquals(0.3, stored?.lastScrollFraction ?: -1.0, 0.0)
        assertEquals(listOf("Local"), database.tagDao().getTagsForWork(WORK_K).map { it.name })
        assertArrayEquals(
            "local-epub".toByteArray(),
            Files.readAllBytes(workFileStore.workEpubPath(WORK_K))
        )
        assertEquals(0, summary.worksUpdated)
        assertEquals(0, summary.worksCreated)
        assertTrue(
            "incoming unsigned tombstones must not be written to Room",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun importPackageMergeUndeletesPendingDeletion() = runTest {
        database.workDao().upsert(
            savedWork(WORK_K, "Recently Deleted").copy(
                isDeleted = true,
                deletedAt = Instant.parse("2026-06-01T00:00:00Z"),
                permanentDeletionScheduledAt = Instant.parse("2026-08-30T00:00:00Z"),
                lastModifiedAt = Instant.parse("2026-06-01T00:00:00Z"),
                sourceUrl = "https://archiveofourown.org/works/4242"
            ).toEntity()
        )
        val incoming = overlapPackage(
            title = "Restored From File",
            lastModifiedAt = "2026-07-01T00:00:00Z",
            lastSpineIndex = 8,
            lastScrollFraction = 0.8,
            userTags = listOf("Incoming"),
            epubBytes = "incoming-epub".toByteArray()
        )

        val summary = backupRepository.importPackage(incoming, BackupImportMode.MERGE)

        val stored = database.workDao().getById(WORK_K)
        assertNotNull(stored)
        assertEquals(false, stored?.isDeleted)
        assertEquals(null, stored?.deletedAt)
        assertEquals("Restored From File", stored?.title)
        assertEquals(1, summary.worksUpdated)
        assertEquals(
            listOf("Incoming"),
            database.tagDao().getTagsForWork(WORK_K).map { it.name }
        )
        assertArrayEquals(
            "incoming-epub".toByteArray(),
            Files.readAllBytes(workFileStore.workEpubPath(WORK_K))
        )
    }

    @Test
    fun importPackageReconcileStillLwwUpdatesOverlap() = runTest {
        seedLocalOverlapWork()
        val incoming = overlapPackage(
            title = "Incoming Title",
            lastModifiedAt = "2026-07-01T00:00:00Z",
            lastSpineIndex = 8,
            lastScrollFraction = 0.8,
            userTags = listOf("Incoming"),
            epubBytes = "incoming-epub".toByteArray()
        )

        val summary = backupRepository.importPackage(incoming, BackupImportMode.RECONCILE)

        val stored = database.workDao().getById(WORK_K)
        assertNotNull(stored)
        assertEquals("Incoming Title", stored?.title)
        assertEquals(8, stored?.lastSpineIndex)
        assertEquals(0.8, stored?.lastScrollFraction ?: -1.0, 0.0)
        assertEquals(
            listOf("Incoming", "Local"),
            database.tagDao().getTagsForWork(WORK_K).map { it.name }.sorted()
        )
        assertArrayEquals(
            "incoming-epub".toByteArray(),
            Files.readAllBytes(workFileStore.workEpubPath(WORK_K))
        )
        assertEquals(1, summary.worksUpdated)
    }

    @Test
    fun importPackageMergeDoesNotAdoptIncomingTombstones() = runTest {
        val pack = packageWithWorkAndTombstone(
            workId = WORK_K,
            workTitle = "Should still insert",
            tombstoneRecordId = WORK_K,
            ao3WorkId = 4242
        )

        val summary = backupRepository.importPackage(pack, BackupImportMode.MERGE)

        assertEquals(1, summary.worksCreated)
        assertEquals(0, summary.worksSuppressed)
        assertNotNull(database.workDao().getById(WORK_K))
        assertTrue(
            "incoming unsigned tombstones must not be written to Room",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun folderSyncIngestDoesNotAdoptIncomingTombstones() = runTest {
        val remoteWork = backupWork(WORK_K, "From sync folder", 4242)
        val remoteTombstone = BackupTombstone(
            id = TOMBSTONE_ID,
            recordID = WORK_K,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = "2026-01-01T00:00:00Z",
            lastModifiedAt = "2026-01-01T00:00:00Z",
            sourceURL = "https://archiveofourown.org/works/4242",
            ao3WorkID = 4242
        )
        val manifest = KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = "2026-01-02T00:00:00Z",
            exportedBy = BackupExportedBy(
                platform = "android",
                appVersion = "test",
                schemaVersion = BackupVersion.CURRENT
            ),
            works = listOf(remoteWork),
            tombstones = listOf(remoteTombstone),
            settings = BackupSettingsPayload()
        )

        val kudos = ensureKudosLibrary()
        val worksDir = kudos.findFile(BackupPaths.WORKS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray()
        )
        writeChild(worksDir, "$WORK_K.epub", "application/epub+zip", "remote-epub".toByteArray())

        val result = syncRepository.runSync()
        assertTrue("sync: $result", result is SyncResult.Success)

        assertNotNull(
            "folder-sync must not skip a work present in the remote snapshot",
            database.workDao().getById(WORK_K)
        )
        assertTrue(
            "folder-sync must not insert the remote unsigned tombstone",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun folderSyncIngestStillLwwUpdatesOverlap() = runTest {
        seedLocalOverlapWork()
        val remoteWork = backupWork(
            id = WORK_K,
            title = "From sync folder",
            ao3WorkId = 4242,
            lastModifiedAt = "2026-07-01T00:00:00Z"
        ).copy(
            lastSpineIndex = 8,
            lastScrollFraction = 0.8,
            lastReadDate = "2026-07-01T00:00:00Z",
            progressModifiedAt = "2026-07-01T00:00:00Z",
            userTags = listOf("Incoming")
        )
        val remoteTombstone = BackupTombstone(
            id = TOMBSTONE_ID,
            recordID = WORK_K,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = "2026-01-01T00:00:00Z",
            lastModifiedAt = "2026-01-01T00:00:00Z",
            sourceURL = "https://archiveofourown.org/works/4242",
            ao3WorkID = 4242
        )
        val manifest = KudosBackupManifest(
            version = BackupVersion.CURRENT,
            exportedAt = "2026-07-02T00:00:00Z",
            exportedBy = BackupExportedBy(
                platform = "android",
                appVersion = "test",
                schemaVersion = BackupVersion.CURRENT
            ),
            works = listOf(remoteWork),
            tombstones = listOf(remoteTombstone),
            settings = BackupSettingsPayload()
        )

        val kudos = ensureKudosLibrary()
        val worksDir = kudos.findFile(BackupPaths.WORKS_DIRECTORY)
            ?: kudos.createDirectory(BackupPaths.WORKS_DIRECTORY)!!
        writeChild(
            kudos,
            BackupPaths.MANIFEST,
            "application/json",
            BackupJson.encodeToString(manifest).toByteArray()
        )
        writeChild(worksDir, "$WORK_K.epub", "application/epub+zip", "remote-epub".toByteArray())

        val result = syncRepository.runSync()
        assertTrue("sync: $result", result is SyncResult.Success)

        val stored = database.workDao().getById(WORK_K)
        assertEquals("From sync folder", stored?.title)
        assertEquals(8, stored?.lastSpineIndex)
        assertEquals(0.8, stored?.lastScrollFraction ?: -1.0, 0.0)
        assertTrue(
            "folder-sync must not insert the remote unsigned tombstone",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    private suspend fun seedLocalOverlapWork() {
        database.workDao().upsert(
            savedWork(WORK_K, "Local Title").copy(
                lastSpineIndex = 3,
                lastScrollFraction = 0.3,
                lastReadDate = Instant.parse("2026-01-01T00:00:00Z"),
                progressModifiedAt = Instant.parse("2026-01-01T00:00:00Z"),
                lastModifiedAt = Instant.parse("2026-01-01T00:00:00Z"),
                sourceUrl = "https://archiveofourown.org/works/4242"
            ).toEntity()
        )
        database.tagDao().upsert(
            TagEntity(id = LOCAL_TAG_ID, name = "Local", dateCreated = FIXED_CLOCK)
        )
        database.tagDao().addToWork(WorkTagCrossRef(workId = WORK_K, tagId = LOCAL_TAG_ID))
        workFileStore.writeWorkEpub(WORK_K, "local-epub".toByteArray())
    }

    private fun overlapPackage(
        title: String,
        lastModifiedAt: String,
        lastSpineIndex: Int,
        lastScrollFraction: Double,
        userTags: List<String>,
        epubBytes: ByteArray,
        tombstoneRecordId: String = TOMBSTONE_ID
    ): KudosBackupPackage {
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-07-02T00:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "android",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(
                    backupWork(WORK_K, title, 4242, lastModifiedAt).copy(
                        lastSpineIndex = lastSpineIndex,
                        lastScrollFraction = lastScrollFraction,
                        lastReadDate = lastModifiedAt,
                        progressModifiedAt = lastModifiedAt,
                        userTags = userTags
                    )
                ),
                tombstones = listOf(
                    BackupTombstone(
                        id = TOMBSTONE_ID,
                        recordID = tombstoneRecordId,
                        recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                        createdAt = lastModifiedAt,
                        lastModifiedAt = lastModifiedAt,
                        sourceURL = "https://archiveofourown.org/works/111",
                        ao3WorkID = 111
                    )
                ),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = mapOf(WORK_K to epubBytes)
        )
    }

    private fun packageWithWorkAndTombstone(
        workId: String,
        workTitle: String,
        tombstoneRecordId: String,
        ao3WorkId: Int,
        lastModifiedAt: String = "2026-01-01T00:00:00Z"
    ): KudosBackupPackage {
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-06-26T12:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "android",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(backupWork(workId, workTitle, ao3WorkId, lastModifiedAt)),
                tombstones = listOf(
                    BackupTombstone(
                        id = TOMBSTONE_ID,
                        recordID = tombstoneRecordId,
                        recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                        createdAt = lastModifiedAt,
                        lastModifiedAt = lastModifiedAt,
                        sourceURL = "https://archiveofourown.org/works/$ao3WorkId",
                        ao3WorkID = ao3WorkId
                    )
                ),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = mapOf(workId to "epub".toByteArray())
        )
    }

    private fun backupWork(
        id: String,
        title: String,
        ao3WorkId: Int,
        lastModifiedAt: String = "2026-01-01T00:00:00Z"
    ): BackupWork {
        return BackupWork(
            id = id,
            title = title,
            author = "Author",
            sourceURL = "https://archiveofourown.org/works/$ao3WorkId",
            dateAdded = lastModifiedAt,
            isSaved = true,
            hasEPUB = true,
            lastModifiedAt = lastModifiedAt,
            ao3WorkID = ao3WorkId
        )
    }

    private fun savedWork(id: String, title: String): SavedWork {
        return SavedWork(
            id = id,
            title = title,
            author = "Author",
            dateAdded = FIXED_CLOCK,
            isSaved = true,
            hasEpub = true
        )
    }

    private fun ensureKudosLibrary(): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, treeUri)
            ?: error("fromTreeUri returned null for $treeUri")
        return root.findFile("KudosLibrary")
            ?: root.createDirectory("KudosLibrary")
            ?: error("Could not create KudosLibrary")
    }

    private fun writeChild(dir: DocumentFile, name: String, mime: String, bytes: ByteArray) {
        val file = dir.findFile(name) ?: dir.createFile(mime, name)
            ?: error("createFile failed for $name")
        context.contentResolver.openOutputStream(file.uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: error("openOutputStream failed for $name")
    }

    companion object {
        private val FIXED_CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private const val WORK_J = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        private const val WORK_K = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
        private const val LOCAL_TAG_ID = "44444444-4444-4444-8444-444444444444"
    }
}
