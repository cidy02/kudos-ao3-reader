package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.backup.BackupAnnotation
import io.github.cidy02.kudos.backup.BackupExportedBy
import io.github.cidy02.kudos.backup.BackupImportMode
import io.github.cidy02.kudos.backup.BackupRepository
import io.github.cidy02.kudos.backup.BackupSettingsPayload
import io.github.cidy02.kudos.backup.BackupVersion
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.KudosBackupManifest
import io.github.cidy02.kudos.backup.KudosBackupPackage
import io.github.cidy02.kudos.backup.PersistenceGate
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.backup.toBackupTombstone
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production-entry coverage for annotation delete tombstones.
 *
 * [AnnotationRepository.deleteAnnotation] is the reader delete path.
 * Folder sync ingest is [BackupRepository.importPackage] (default RECONCILE).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnnotationTombstoneTest {
    private lateinit var context: Context
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var backupRepository: BackupRepository
    private lateinit var annotationRepository: AnnotationRepository

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-ann-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-ann-files")
        backupRepository = BackupRepository(
            database = database,
            workFileStore = WorkFileStore(filesRoot),
            fontFileStore = FontFileStore(filesRoot),
            settingsRepository = settingsRepository,
            persistenceGate = PersistenceGate(),
            clock = { CLOCK },
            uuidFactory = { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" },
            appVersion = "test"
        )
        annotationRepository = AnnotationRepository(
            dao = database.annotationDao(),
            tombstoneDao = database.syncTombstoneDao(),
            clock = { CLOCK },
            uuidFactory = { TOMBSTONE_ID }
        )
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    @Test
    fun remoteDeleteRemovesExistingAnnotationMembershipAndLinkFromRoomAndNextExport() = runTest {
        val work = SavedWork(id = WORK_ID, title = "Work", author = "Writer", dateAdded = ANNOTATION_CREATED)
        val mark = ReadingAnnotation(id = ANN_ID, workID = WORK_ID, createdAt = ANNOTATION_CREATED)
        val queue = io.github.cidy02.kudos.core.model.ReadingQueue(id = QUEUE_ID, name = "Queue", dateCreated = ANNOTATION_CREATED)
        val membership = io.github.cidy02.kudos.core.model.ReadingQueueMembership(id = MEMBER_ID, queueID = QUEUE_ID, workID = WORK_ID, queuedAt = ANNOTATION_CREATED)
        val link = io.github.cidy02.kudos.core.model.Bookmark(id = LINK_ID, title = "Link", urlString = "https://example.invalid/saved", dateAdded = ANNOTATION_CREATED)
        database.workDao().upsert(work.toEntity())
        database.annotationDao().upsert(mark.toEntity())
        database.readingQueueDao().upsertQueue(queue.toEntity())
        database.readingQueueDao().upsertMembership(membership.toEntity())
        database.bookmarkDao().upsert(link.toEntity())
        val tombstones = listOf(ANN_ID to SyncTombstoneRecordType.READING_ANNOTATION,
            MEMBER_ID to SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
            LINK_ID to SyncTombstoneRecordType.BOOKMARK).map { (id, kind) ->
            TombstoneSigning.sign(io.github.cidy02.kudos.core.model.SyncTombstone(recordID = id, recordTypeRaw = kind, createdAt = CLOCK))
        }
        val remote = KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = CLOCK.toString(),
            tombstones = tombstones.map { it.toBackupTombstone() }))
        backupRepository.importPackage(remote)
        assertNull(database.annotationDao().getById(ANN_ID))
        assertNull(database.readingQueueDao().getMembershipForWork(QUEUE_ID, WORK_ID))
        assertNull(database.bookmarkDao().getById(LINK_ID))
        val exported = backupRepository.captureLibrarySnapshot()
        assertTrue(exported.annotations.isEmpty())
        assertTrue(exported.readingQueueMemberships.isEmpty())
        assertTrue(exported.bookmarks.isEmpty())
    }

    @Test
    fun fileMergeRetractsWorkDeletionFromRoomAsRecentlyDeletedRestoreDoes() = runTest {
        val work = SavedWork(id = WORK_ID, title = "Work", author = "Writer", dateAdded = ANNOTATION_CREATED,
            sourceUrl = "https://archiveofourown.org/works/4242", isDeleted = true, deletedAt = CLOCK,
            permanentDeletionScheduledAt = CLOCK.plusSeconds(500), lastModifiedAt = CLOCK)
        database.workDao().upsert(work.toEntity())
        val tombstone = TombstoneSigning.sign(io.github.cidy02.kudos.core.model.SyncTombstone(
            recordID = WORK_ID, recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK, createdAt = CLOCK))
        database.syncTombstoneDao().upsert(tombstone.toEntity())
        backupRepository.importPackage(packageWithWorkAndAnnotation(), BackupImportMode.MERGE)
        assertTrue(database.syncTombstoneDao().getAll().none { it.recordTypeRaw == SyncTombstoneRecordType.SAVED_WORK })
        assertEquals(false, database.workDao().getById(WORK_ID)!!.isDeleted)
    }

    @Test
    fun remoteDeletionDoesNotDeleteAnnotationOrMembershipEditedSinceCapture() = runTest {
        val work = SavedWork(id = WORK_ID, title = "Work", author = "Writer", dateAdded = ANNOTATION_CREATED)
        val mark = ReadingAnnotation(id = ANN_ID, workID = WORK_ID, createdAt = ANNOTATION_CREATED)
        val queue = io.github.cidy02.kudos.core.model.ReadingQueue(id = QUEUE_ID, name = "Queue", dateCreated = ANNOTATION_CREATED)
        val member = io.github.cidy02.kudos.core.model.ReadingQueueMembership(id = MEMBER_ID, queueID = QUEUE_ID, workID = WORK_ID, queuedAt = ANNOTATION_CREATED)
        database.workDao().upsert(work.toEntity())
        database.annotationDao().upsert(mark.toEntity())
        database.readingQueueDao().upsertQueue(queue.toEntity())
        database.readingQueueDao().upsertMembership(member.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val remote = KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = CLOCK.toString(),
            tombstones = listOf(ANN_ID to SyncTombstoneRecordType.READING_ANNOTATION, MEMBER_ID to SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP).map { (id, kind) ->
                TombstoneSigning.sign(io.github.cidy02.kudos.core.model.SyncTombstone(recordID = id, recordTypeRaw = kind, createdAt = CLOCK)).toBackupTombstone()
            }))
        val planned = io.github.cidy02.kudos.backup.BackupMergeService.merge(captured, remote, now = CLOCK)
        database.annotationDao().upsert(mark.copy(note = "edited", lastModifiedAt = CLOCK.plusSeconds(1)).toEntity())
        database.readingQueueDao().upsertMembership(member.copy(note = "edited", lastModifiedAt = CLOCK.plusSeconds(1)).toEntity())
        backupRepository.applyMergeResult(planned)
        assertEquals("edited", database.annotationDao().getById(ANN_ID)!!.note)
        assertEquals("edited", database.readingQueueDao().getMembershipForWork(QUEUE_ID, WORK_ID)!!.note)
    }

    @Test
    fun displacedNoteStaysHiddenAndExportableBeyondTheWorkRecoveryWindow() = runTest {
        val pack = packageWithWorkAndAnnotation()
        val archived = pack.manifest.annotations.single()
        database.workDao().upsert(SavedWork(id = WORK_ID, title = "Work", author = "Writer", dateAdded = ANNOTATION_CREATED).toEntity())
        database.annotationDao().upsert(ReadingAnnotation(id = ANN_ID, workID = WORK_ID, kindRaw = "highlight",
            note = "displaced", locatorString = "original anchor", createdAt = ANNOTATION_CREATED,
            lastModifiedAt = ANNOTATION_CREATED).toEntity())
        backupRepository.importPackage(pack.copy(manifest = pack.manifest.copy(annotations = listOf(
            archived.copy(note = "new", lastModifiedAt = CLOCK.toString())
        ))))
        assertEquals("new", annotationRepository.observeForWork(WORK_ID).first().single().note)
        val parked = database.annotationDao().getAll().single { it.id != ANN_ID }
        assertEquals("displaced", parked.note)
        assertTrue(parked.isPendingDeletion)
        val root = Files.createTempDirectory("kudos-ann-sweep")
        try {
            val workRepository = io.github.cidy02.kudos.works.WorkRepository(database, WorkFileStore(root),
                clock = { CLOCK.plus(java.time.Duration.ofDays(91)) })
            workRepository.sweepExpiredSoftDeletes()
            assertEquals(parked, database.annotationDao().getById(parked.id))
            assertEquals("displaced", backupRepository.captureLibrarySnapshot().annotations.single { it.id == parked.id }.note)
        } finally {
            root.toFile().deleteRecursively()
        }
    }

    @Test
    fun searchResultBookmarkUsesReaderBookmarkRecordAndCompatiblePassageLocator() = runTest {
        database.workDao().upsert(SavedWork(id = WORK_ID, title = "Work", author = "Author").toEntity())
        val locator = org.readium.r2.shared.publication.Locator.fromJSON(
            org.json.JSONObject(
                """{"href":"ch5.xhtml","type":"application/xhtml+xml",
                    "locations":{"progression":0.4,"totalProgression":0.6},
                    "text":{"before":"A ","highlight":"match","after":" here."}}"""
            )
        )!!
        val envelope = checkNotNull(ReaderLocatorCodec.encodeEnvelope(locator.toJSON().toString()))
        // Both the reader's own action and the result action call addBookmark.
        val bookmark = annotationRepository.addBookmark(
            workId = WORK_ID,
            locatorString = envelope,
            progression = 0.6,
            spineIndex = 4,
            chapterTitle = "Chapter 5"
        )
        val saved = database.annotationDao().getById(bookmark.id)!!
        assertEquals("bookmark", saved.kindRaw)
        assertEquals(WORK_ID, saved.workID)
        assertEquals(4, saved.spineIndex)
        assertEquals(0.6, saved.progression, 0.0)
        assertEquals("Chapter 5", saved.chapterTitle)
        assertEquals(envelope, saved.locatorString)
        assertEquals("", saved.selectedText)
        val restored = io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
            .locatorFromJson(saved.locatorString)!!
        assertEquals(locator.href, restored.href)
        assertEquals("match", restored.text.highlight)
        assertEquals(0.4, restored.locations.progression!!, 0.0)

        // iOS addBookmark(at:): the same result bookmarked again gives back the first.
        val again = annotationRepository.addBookmark(WORK_ID, envelope, 0.6, 4, "Chapter 5")
        assertEquals(bookmark.id, again.id)
        assertEquals(1, annotationRepository.observeForWork(WORK_ID).first().size)
        // A deleted bookmark does not stand in the way of a new one at the same place.
        annotationRepository.deleteAnnotation(bookmark.id)
        val fresh = annotationRepository.addBookmark(WORK_ID, envelope, 0.6, 4, "Chapter 5")
        assertNotEquals(bookmark.id, fresh.id)
    }

    /**
     * iOS `ReadingAnnotationMatching.isSamePassage`: only the same stored locator is the same
     * passage. The same words a few lines down are a second highlight (audit A5-4).
     */
    @Test
    fun theSameWordsFurtherDownAreASecondHighlightNotTheFirstMoved() = runTest {
        database.workDao().upsert(SavedWork(id = WORK_ID, title = "Work", author = "Author", dateAdded = Instant.parse("2026-01-01T00:00:00Z")).toEntity())
        val first = annotationRepository.addOrRecolorHighlight(
            workId = WORK_ID, locatorString = "locator-a", selectedText = "Harry", color = "yellow",
            note = "the first", progression = 0.10, spineIndex = 2
        )
        val second = annotationRepository.addOrRecolorHighlight(
            workId = WORK_ID, locatorString = "locator-b", selectedText = "Harry", color = "pink",
            progression = 0.12, spineIndex = 2
        )
        assertNotEquals(first.id, second.id)
        val stored = annotationRepository.observeForWork(WORK_ID).first().associateBy { it.id }
        assertEquals(2, stored.size)
        assertEquals("locator-a", stored.getValue(first.id).locatorString)
        assertEquals("yellow", stored.getValue(first.id).colorRaw)
        assertEquals("the first", stored.getValue(first.id).note)
        assertEquals("", stored.getValue(second.id).note)
        // The very same selection again recolours the mark it already has.
        val again = annotationRepository.addOrRecolorHighlight(
            workId = WORK_ID, locatorString = "locator-a", selectedText = "Harry", color = "green",
            progression = 0.10, spineIndex = 2
        )
        assertEquals(first.id, again.id)
        assertEquals("the first", again.note)
        assertEquals(2, annotationRepository.observeForWork(WORK_ID).first().size)
    }

    @Test
    fun deleteAnnotationMintsTombstoneAndFolderSyncDoesNotResurrect() = runTest {
        database.workDao().upsert(
            SavedWork(
                id = WORK_ID,
                title = "Work",
                author = "Author",
                sourceUrl = "https://archiveofourown.org/works/4242",
                dateAdded = ANNOTATION_CREATED,
                lastModifiedAt = ANNOTATION_CREATED,
                isSaved = true
            ).toEntity()
        )
        database.annotationDao().upsert(
            ReadingAnnotation(
                id = ANN_ID,
                workID = WORK_ID,
                kindRaw = "highlight",
                colorRaw = "yellow",
                locatorString = """{"href":"ch1"}""",
                selectedText = "deleted later",
                note = "keep me gone",
                createdAt = ANNOTATION_CREATED,
                lastModifiedAt = ANNOTATION_CREATED
            ).toEntity()
        )

        annotationRepository.deleteAnnotation(ANN_ID)

        assertNull(
            "deleteAnnotation must remove the highlight",
            database.annotationDao().getById(ANN_ID)
        )

        val summary = backupRepository.importPackage(
            packageWithWorkAndAnnotation(),
            BackupImportMode.RECONCILE
        )

        assertNull(
            "folder-sync RECONCILE must not resurrect a locally deleted highlight",
            database.annotationDao().getById(ANN_ID)
        )
        assertEquals(
            "deleted highlight must be suppressed by the minted tombstone",
            1,
            summary.annotationsSuppressed
        )
        val minted = database.syncTombstoneDao().getAll().filter {
            it.recordTypeRaw == SyncTombstoneRecordType.READING_ANNOTATION &&
                it.recordID == ANN_ID
        }
        assertEquals(
            "deleteAnnotation must mint a readingAnnotation tombstone",
            1,
            minted.size
        )
        assertEquals(TOMBSTONE_ID, minted.single().id)
        assertEquals(CLOCK, minted.single().createdAt)
        assertEquals(CLOCK, minted.single().lastModifiedAt)
        assertTrue(minted.single().signature.isNotEmpty())
    }

    private fun packageWithWorkAndAnnotation(): KudosBackupPackage {
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-06-01T00:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "android",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(
                    BackupWork(
                        id = WORK_ID,
                        title = "Work",
                        author = "Author",
                        sourceURL = "https://archiveofourown.org/works/4242",
                        dateAdded = "2026-01-01T00:00:00Z",
                        isSaved = true,
                        hasEPUB = true,
                        lastModifiedAt = "2026-01-01T00:00:00Z",
                        ao3WorkID = 4242
                    )
                ),
                annotations = listOf(
                    BackupAnnotation(
                        id = ANN_ID,
                        workID = WORK_ID,
                        kindRaw = "highlight",
                        colorRaw = "yellow",
                        locatorString = """{"href":"ch1"}""",
                        selectedText = "deleted later",
                        note = "keep me gone",
                        createdAt = "2026-01-01T00:00:00Z",
                        lastModifiedAt = "2026-01-01T00:00:00Z"
                    )
                ),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = mapOf(WORK_ID to "epub".toByteArray())
        )
    }

    companion object {
        const val QUEUE_ID = "22222222-2222-4222-8222-222222222222"
        const val MEMBER_ID = "33333333-3333-4333-8333-333333333333"
        const val LINK_ID = "44444444-4444-4444-8444-444444444444"
        private val CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private val ANNOTATION_CREATED: Instant = Instant.parse("2026-01-01T00:00:00Z")
        private const val WORK_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        private const val ANN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
    }
}
