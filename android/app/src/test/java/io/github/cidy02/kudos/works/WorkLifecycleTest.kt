package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupWork
import io.github.cidy02.kudos.backup.toBackupWork
import io.github.cidy02.kudos.backup.toSavedWork
import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3BinaryResponse
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import io.github.cidy02.kudos.library.LibraryHistoryGrouping
import io.github.cidy02.kudos.library.ReadingAbandonment
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
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

class WorkMetadataMergerTest {
    @Test
    fun workPageDatesAndStatusSurviveSavingAndBlankRefreshes() {
        val summary = sampleSummary().copy(publishedDate = "listing published", updatedDate = "listing updated",
            isComplete = false)
        val canonical = AO3WorkMetadata(datePublished = "01 Jan 2026", dateUpdated = "02 Jan 2026", isComplete = true)
        val merger = WorkMetadataMerger()
        val saved = merger.merge(summary, canonical, null, markSaved = true)
        assertEquals("01 Jan 2026", saved.datePublished)
        assertEquals("02 Jan 2026", saved.dateUpdated)
        assertTrue(saved.isComplete)
        val blank = merger.merge(null, AO3WorkMetadata(), saved, markSaved = true)
        assertEquals(saved.datePublished, blank.datePublished)
        assertEquals(saved.dateUpdated, blank.dateUpdated)
        assertTrue(blank.isComplete)
        val listingOnly = merger.merge(summary, null, null, markSaved = true)
        assertEquals("listing published", listingOnly.datePublished)
        assertEquals("listing updated", listingOnly.dateUpdated)
        assertFalse(listingOnly.isComplete)
    }

    @Test
    fun preservesUserLocalStateAndDoesNotEraseWithBlanks() {
        val existing = SavedWork(
            id = workUuid,
            title = "Old title",
            author = "Old author",
            summary = "Existing summary",
            sourceUrl = "https://archiveofourown.org/works/123",
            dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
            isFavorite = true,
            isFinished = true,
            hasEpub = true,
            lastSpineIndex = 3,
            lastScrollFraction = 0.5,
            readiumLocator = "locator"
        )
        val summary = sampleSummary().copy(title = "", summary = "", kudos = 9)
        val metadata = AO3WorkMetadata(
            fandoms = listOf("Fandom"),
            relationships = listOf("A/B"),
            words = 1200,
            chapters = "2/2"
        )

        val merged = WorkMetadataMerger().merge(summary, metadata, existing, markSaved = true)

        assertEquals("Old title", merged.title)
        assertEquals("Existing summary", merged.summary)
        assertTrue(merged.isFavorite)
        assertTrue(merged.isFinished)
        assertEquals(3, merged.lastSpineIndex)
        assertEquals(0.5, merged.lastScrollFraction, 0.0)
        assertEquals("locator", merged.readiumLocator)
        assertEquals(listOf("Fandom"), merged.workFandoms)
        assertEquals(listOf("A/B"), merged.workRelationships)
        assertTrue(merged.workTagsFetched)
        assertEquals(1200, merged.wordCount)
        assertEquals("2/2", merged.chapters)
        assertEquals(9, merged.kudos)
    }

    @Test
    fun appliesOpportunisticKudosSignalWithoutClobberingTrueToFalse() {
        val existingWithKudos = SavedWork(
            id = workUuid,
            title = "Title",
            author = "Author",
            summary = "Summary",
            sourceUrl = "https://archiveofourown.org/works/123",
            dateAdded = Instant.now(),
            hasGivenKudos = true
        )
        val metadataWithoutKudos = AO3WorkMetadata(kudosGivenByCurrentUser = false)
        val merged1 = WorkMetadataMerger().merge(
            summary = null,
            canonical = metadataWithoutKudos,
            existing = existingWithKudos,
            markSaved = false
        )
        assertTrue("Monotonic signal must not be cleared", merged1.hasGivenKudos)

        val existingWithoutKudos = existingWithKudos.copy(hasGivenKudos = false)
        val metadataWithKudos = AO3WorkMetadata(kudosGivenByCurrentUser = true)
        val merged2 = WorkMetadataMerger().merge(
            summary = null,
            canonical = metadataWithKudos,
            existing = existingWithoutKudos,
            markSaved = false
        )
        assertTrue("Signal must be applied when detected", merged2.hasGivenKudos)
    }

    // The three cases below pin the revival behaviour added to fix a real bug found in
    // review: importing or saving a work that matches a soft-deleted (Recently Deleted)
    // row updated its fields but left `isDeleted` untouched — the download reported
    // success, yet the work stayed hidden and on course to be purged for good when its
    // 90-day window ran out regardless. `WorkIdentityIndex.findExisting` matches
    // soft-deleted rows by design (so re-saving the same work is recognised rather than
    // duplicated); this merger is what has to undo the soft delete when that happens,
    // mirroring Apple `PreservedWorkService.restore`.

    @Test
    fun mergingASoftDeletedMatchRevivesIt() {
        val softDeleted = SavedWork(
            id = workUuid,
            title = "Old Work",
            author = "Someone",
            sourceUrl = "https://archiveofourown.org/works/4242",
            hasEpub = true,
            isDeleted = true,
            deletedAt = Instant.parse("2026-07-01T00:00:00Z"),
            permanentDeletionScheduledAt = Instant.parse("2026-09-29T00:00:00Z")
        )

        val merged = WorkMetadataMerger().merge(
            summary = null,
            canonical = null,
            existing = softDeleted,
            markSaved = true
        )

        assertFalse("a re-saved work must leave Recently Deleted", merged.isDeleted)
        assertNull(merged.deletedAt)
        assertNull(merged.permanentDeletionScheduledAt)
    }

    @Test
    fun mergingAnActiveMatchLeavesItsDeletionFieldsAlone() {
        // The revival path must not be a no-op-turned-into-a-bug for the ordinary
        // case: an active (never-deleted) work merging in new metadata just stays active.
        val active = sampleSavedWork().copy(isDeleted = false, deletedAt = null)
        val merged = WorkMetadataMerger().merge(summary = null, canonical = null, existing = active, markSaved = true)
        assertFalse(merged.isDeleted)
        assertNull(merged.deletedAt)
    }

    @Test
    fun mergingWithNoExistingMatchCreatesAnOrdinaryNewWork() {
        // No `existing` at all (a genuinely new work) must not somehow read as a
        // "revival" and misbehave — there is nothing to revive.
        val merged = WorkMetadataMerger().merge(summary = null, canonical = null, existing = null, markSaved = true)
        assertFalse(merged.isDeleted)
    }

    // Queue-only semantics (T-89): queuing a not-yet-saved work must not silently
    // save it — mirrors iOS SavedWork.isQueuedForLater staying separate from isSaved.

    @Test
    fun queueingANewWorkMarksItQueuedOnlyNotSaved() {
        val merged = WorkMetadataMerger().merge(
            summary = sampleSummary(),
            canonical = null,
            existing = null,
            markSaved = false,
            isQueuedForLater = true
        )

        assertFalse("a queue-only add must not mark isSaved", merged.isSaved)
        assertTrue(merged.isQueuedForLater)
        assertTrue("queued, not saved, not favorite -> queue-only", merged.isQueueOnlyWork)
    }

    @Test
    fun queueingAnAlreadySavedWorkKeepsItSaved() {
        val alreadySaved = sampleSavedWork().copy(isSaved = true)

        val merged = WorkMetadataMerger().merge(
            summary = sampleSummary(),
            canonical = null,
            existing = alreadySaved,
            markSaved = false,
            isQueuedForLater = true
        )

        assertTrue("an already-saved work must stay saved when also queued", merged.isSaved)
        assertTrue(merged.isQueuedForLater)
        assertFalse("saved works are never queue-only", merged.isQueueOnlyWork)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkLifecycleRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository
    /** Mutable so purge tests can advance past the 90-day recovery window. */
    private var clockNow: Instant = Instant.parse("2026-06-26T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-work-tests"))
        clockNow = Instant.parse("2026-06-26T12:00:00Z")
        repository = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" }
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    /** PreservedWorkTests.resolveLocalWorkRevivesASoftDeletedWorkWithoutMaskingAMissingEPUB. */
    @Test
    fun resolveLocalWorkRevivesASoftDeletedWorkWithoutMaskingAMissingEPUB() = runTest {
        val original = repository.upsert(sampleSavedWork().copy(hasEpub = false, readiumLocator = "reader's place"))
        repository.softDelete(original.id)
        val resolved = repository.resolveLocalWork(original.id)!!
        assertEquals(original.id, resolved.id)
        assertFalse(resolved.isDeleted)
        assertNull(resolved.deletedAt)
        assertNull(resolved.permanentDeletionScheduledAt)
        assertFalse(resolved.hasEpub)
        assertFalse(fileStore.workEpubExists(resolved.id))
        assertEquals("reader's place", resolved.readiumLocator)
        assertTrue(database.syncTombstoneDao().getByRecord(resolved.id, SyncTombstoneRecordType.SAVED_WORK).isEmpty())
        assertEquals(1, database.workDao().getAllIncludingDeleted().size)
    }

    /** CollectionWorkPickerTests.addStampsBothSidesModified, through the real membership writer. */
    @Test
    fun addStampsBothSidesModified() = runTest {
        repository.upsert(sampleSavedWork())
        val collection = repository.createCollection("Shelf")
        clockNow = clockNow.plusSeconds(30)
        repository.addWorkToCollection(workUuid, collection.id)
        assertEquals(clockNow, repository.getWork(workUuid)!!.lastModifiedAt)
        assertEquals(clockNow, repository.getCollection(collection.id)!!.lastModifiedAt)
        assertEquals(clockNow, repository.getCollection(collection.id)!!.lastMembershipChangedAt)
        val chosenAt = clockNow
        clockNow = clockNow.plusSeconds(30)
        repository.addWorkToCollection(workUuid, collection.id)
        assertEquals(chosenAt, repository.getCollection(collection.id)!!.lastMembershipChangedAt)
        repository.removeFromCollection(workUuid, collection.id)
        assertEquals(clockNow, repository.getCollection(collection.id)!!.lastMembershipChangedAt)
    }

    /** CollectionMembershipDeletionTests.renamingACollectionDoesNotOverrideARemovalElsewhere. */
    @Test
    fun renamingACollectionDoesNotOverrideARemovalElsewhere() = runTest {
        val work = repository.upsert(sampleSavedWork())
        val collection = repository.createCollection("Shelf")
        repository.addWorkToCollection(work.id, collection.id)
        val chosenAt = clockNow
        val removedAt = chosenAt.plusSeconds(100)
        clockNow = chosenAt.plusSeconds(9_000)
        repository.renameCollection(collection.id, "Comfort rereads")
        val local = repository.getCollection(collection.id)!!
        assertEquals(chosenAt, local.lastMembershipChangedAt)
        assertEquals(clockNow, local.lastModifiedAt)
        val tombstone = SyncTombstone(
            recordID = io.github.cidy02.kudos.core.model.collectionMembershipRecordId(collection.id, work.id),
            recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP,
            createdAt = removedAt, lastModifiedAt = removedAt
        )
        val archived = io.github.cidy02.kudos.backup.BackupCollection(
            id = collection.id, name = "Shelf", dateAdded = chosenAt.toString(),
            lastModifiedAt = chosenAt.toString(), workIDs = emptyList()
        )
        val result = io.github.cidy02.kudos.backup.BackupMergeService.merge(
            current = io.github.cidy02.kudos.backup.BackupLibrarySnapshot(
                works = listOf(work), collections = listOf(local), tombstones = listOf(tombstone)
            ),
            backup = io.github.cidy02.kudos.backup.KudosBackupPackage(
                io.github.cidy02.kudos.backup.KudosBackupManifest(8, clockNow.toString(), collections = listOf(archived))
            ),
            mode = io.github.cidy02.kudos.backup.BackupImportMode.MERGE,
            now = clockNow
        )
        assertTrue(result.snapshot.collections.single().workIds.isEmpty())
    }

    /** CollectionWorkPickerTests' candidate rules, including an unkept history record. */
    @Test
    fun collectionCandidatesIncludeUnkeptHistoryButExcludeMembersQueueOnlyAndDeleted() = runTest {
        val history = sampleSavedWork().copy(isSaved = false, isFavorite = false, lastReadDate = clockNow)
        val member = history.copy(id = "22222222-2222-4222-8222-222222222222")
        val queued = history.copy(id = "33333333-3333-4333-8333-333333333333", isQueuedForLater = true)
        val deleted = history.copy(id = "44444444-4444-4444-8444-444444444444", isDeleted = true)
        listOf(history, member, queued, deleted).forEach { repository.upsert(it) }
        val all = repository.observeLibraryWorks().first()
        assertEquals(listOf(history.id), WorkRepository.collectionCandidates(all, setOf(member.id)).map { it.id })
        assertEquals(listOf(history.id), WorkRepository.collectionCandidates(listOf(history, deleted), emptySet()).map { it.id })
    }

    /** PreservedWorkTests.deleteConfirmationMessageEscalatesWhenAO3Unavailable. */
    @Test
    fun deleteConfirmationMessageEscalatesWhenAO3Unavailable() {
        val available = sampleSavedWork()
        val unavailable = available.copy(ao3Unavailable = true)
        assertTrue(io.github.cidy02.kudos.ui.components.workDeletionMessage(listOf(available)).contains("Recently Deleted"))
        assertTrue(io.github.cidy02.kudos.ui.components.workDeletionMessage(listOf(unavailable)).contains("no longer available"))
        assertTrue(io.github.cidy02.kudos.ui.components.workDeletionMessage(listOf(available, unavailable)).contains("can't download"))
    }

    /** Swift ReadingLogTests.moveBackToInProgressStoresTheOverrideAndRebuckets. */
    @Test
    fun moveBackToInProgressStoresTheOverrideAndRebuckets() = runTest {
        val dusty = repository.upsert(sampleSavedWork().copy(
            hasEpub = true, // the sample is a row without a file, which is never "in progress"
            lastReadDate = clockNow.minusSeconds(30 * 86_400L),
            readiumLocator = """{"locations":{"totalProgression":0.4}}""",
            lastModifiedAt = clockNow.minusSeconds(10),
            progressModifiedAt = clockNow.minusSeconds(20)
        ))
        assertTrue(ReadingAbandonment.isAbandoned(dusty, clockNow))
        val kept = repository.keepInProgress(dusty.id)!!
        // What the Library's list is given after the write. (A wait on Room's invalidation
        // under the test's virtual clock times out at once: Room answers on a real thread.)
        val listed = repository.observeLibraryWorks().first().single { it.id == dusty.id }
        assertEquals(kept, listed)
        assertTrue(kept.keepInProgressOverride)
        assertEquals(clockNow, kept.lastModifiedAt)
        assertTrue(kept.effectiveLastModifiedAt > dusty.effectiveLastModifiedAt)
        assertEquals(dusty.progressModifiedAt, kept.progressModifiedAt)
        assertEquals(dusty.lastReadDate, kept.lastReadDate)
        assertEquals(dusty.readiumLocator, kept.readiumLocator)
        assertFalse(ReadingAbandonment.isAbandoned(kept, clockNow))
        assertFalse(ReadingAbandonment.isAbandoned(kept, clockNow.plusSeconds(365 * 86_400L)))
        val groups = LibraryHistoryGrouping.groups(LibraryHistoryGrouping.State, listOf(kept), now = clockNow,
            isAbandoned = { ReadingAbandonment.isAbandoned(it, clockNow) })
        assertEquals(listOf("In progress"), groups.map { it.title })
        // Exercise the real existing BackupMappers through JSON export/import.
        val encoded = BackupJson.encodeToString(kept.toBackupWork())
        val restored = BackupJson.decodeFromString<BackupWork>(encoded).toSavedWork(hasEpub = true)
        assertTrue(restored.keepInProgressOverride)
        assertEquals(kept.lastModifiedAt, restored.lastModifiedAt)
        assertFalse(ReadingAbandonment.isAbandoned(restored, clockNow))
    }

    @Test
    fun workRepositoryInsertUpdateAndToggles() = runTest {
        repository.upsert(sampleSavedWork())

        assertEquals("Example", repository.getWork(workUuid)?.title)
        assertTrue(repository.toggleFavorite(workUuid)!!.isFavorite)
        assertTrue(repository.toggleFinished(workUuid)!!.isFinished)
    }

    @Test
    fun editingDownloadedDateStampsLastModifiedAt() = runTest {
        repository.upsert(sampleSavedWork())
        val downloadedAt = clockNow.minusSeconds(86_400)

        val updated = repository.updateDownloadedAt(workUuid, downloadedAt)!!

        assertEquals(downloadedAt, updated.downloadedAt)
        assertEquals(clockNow, updated.lastModifiedAt)
    }

    @Test
    fun deleteLocalEpubPreservesSavedWork() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val updated = repository.deleteLocalEpub(workUuid)

        assertEquals(workUuid, updated?.id)
        assertFalse(updated!!.hasEpub)
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun removeFromLibraryDeletesRecordAndFile() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        repository.removeFromLibrary(workUuid)

        assertNull(repository.getWork(workUuid))
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun softDeleteSetsFieldsKeepsEpubAndRecordsTombstone() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val deleted = repository.softDelete(workUuid)

        assertNotNull(deleted)
        assertTrue(deleted!!.isDeleted)
        assertEquals(Instant.parse("2026-06-26T12:00:00Z"), deleted.deletedAt)
        assertEquals(
            Instant.parse("2026-06-26T12:00:00Z").plus(WorkRepository.RECOVERY_WINDOW),
            deleted.permanentDeletionScheduledAt
        )
        assertTrue(fileStore.workEpubExists(workUuid))
        // Soft-deleted works leave the active library.
        assertTrue(repository.observeSavedWorks().first().none { it.id == workUuid })
        assertEquals(listOf(workUuid), repository.listRecentlyDeleted().map { it.id })
        val tombstones = database.syncTombstoneDao().getByRecord(
            workUuid,
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK
        )
        assertEquals(1, tombstones.size)
        assertEquals(123, tombstones.single().ao3WorkID)
        assertEquals("workDeleted", tombstones.single().deletionReason)
    }

    @Test
    fun restoreFromRecentlyDeletedClearsFieldsAndRetractsTombstone() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)
        repository.softDelete(workUuid)

        val restored = repository.restoreFromRecentlyDeleted(workUuid)

        assertNotNull(restored)
        assertFalse(restored!!.isDeleted)
        assertNull(restored.deletedAt)
        assertNull(restored.permanentDeletionScheduledAt)
        assertTrue(fileStore.workEpubExists(workUuid))
        assertEquals(listOf(workUuid), repository.observeSavedWorks().first().map { it.id })
        assertTrue(repository.listRecentlyDeleted().isEmpty())
        assertTrue(
            database.syncTombstoneDao().getByRecord(
                workUuid,
                SyncTombstoneRecordType.SAVED_WORK
            ).isEmpty()
        )
    }

    @Test
    fun retractWorkTombstoneMatchesAo3OrCanonicalUrlNotOnlyRecordId() = runTest {
        val otherId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = "33333333-3333-4333-8333-333333333333",
                recordID = otherId,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = clockNow,
                lastModifiedAt = clockNow,
                sourceURL = "https://archiveofourown.org/works/123",
                ao3WorkID = 123
            ).toEntity()
        )

        repository.retractWorkTombstone(
            recordId = workUuid,
            ao3WorkId = 123,
            sourceUrl = "https://archiveofourown.org/works/123/chapters/9"
        )

        assertTrue(
            "retract by ao3 / URL must drop the savedWork tombstone",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun hardDeleteRemovesRecordFileAndKeepsTombstone() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)
        repository.softDelete(workUuid)

        repository.hardDelete(workUuid)

        assertNull(repository.getWork(workUuid))
        assertFalse(fileStore.workEpubExists(workUuid))
        assertTrue(repository.listRecentlyDeleted().isEmpty())
        // softDelete + hardDelete each record a tombstone (Apple always re-records).
        assertTrue(
            database.syncTombstoneDao().getByRecord(
                workUuid,
                io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK
            ).isNotEmpty()
        )
    }

    /** A57, iOS `permanentDeletionRemovesThePreservedOriginal`. */
    @Test
    fun deleteForeverRemovesTheImportedOriginalToo() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)
        fileStore.writeOriginal(workUuid, "txt", "Chapter 1".toByteArray())
        assertNotNull(fileStore.originalFile(workUuid))
        repository.softDelete(workUuid)

        repository.hardDelete(workUuid, onlyIfStillDeleted = true)

        assertNull(fileStore.originalFile(workUuid))
    }

    /** A56, iOS `deletePermanentlyLeavesALiveWorkCollectionAndQueueAlone`. */
    @Test
    fun aStaleDeleteForeverLeavesAWorkRestoredMeanwhileAlone() = runTest {
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        fileStore.writeWorkEpub(workUuid, epubBytes)
        repository.softDelete(workUuid)
        repository.restoreFromRecentlyDeleted(workUuid) // elsewhere, while the confirmation was open

        repository.hardDelete(workUuid, onlyIfStillDeleted = true) // as Recently Deleted calls it

        assertNotNull(repository.getWork(workUuid))
        assertTrue(fileStore.workEpubExists(workUuid))
    }

    /** T-245 item G: nothing that belonged to the work survives it untombstoned. */
    @Test
    fun hardDeleteTombstonesAndRemovesMembershipsAndAnnotations() = runTest {
        val now = Instant.parse("2026-10-02T12:00:00Z")
        // The shared fixture's fixed UUID would make each tombstone overwrite the last.
        var next = 0
        val repository = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { clockNow },
            uuidFactory = { "00000000-0000-0000-0000-%012d".format(++next) }
        )
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        database.readingQueueDao().upsertQueue(
            io.github.cidy02.kudos.data.local.entity.ReadingQueueEntity(
                id = "q-1", name = "Q", kindRaw = "custom", sortOrder = 0, dateCreated = now, dateUpdated = now
            )
        )
        database.readingQueueDao().upsertMembership(
            io.github.cidy02.kudos.data.local.entity.ReadingQueueMembershipEntity(
                id = "m-1", queueID = "q-1", workID = workUuid, queuedAt = now
            )
        )
        database.annotationDao().upsert(
            io.github.cidy02.kudos.data.local.entity.AnnotationEntity(
                id = "A-1", workID = workUuid, kindRaw = "highlight", colorRaw = "yellow",
                locatorString = "{}", selectedText = "x", note = "", progression = 0.1,
                spineIndex = 0, chapterTitle = "", createdAt = now
            )
        )

        repository.hardDelete(workUuid)

        assertTrue(database.readingQueueDao().getMembershipsForWork(workUuid).isEmpty())
        assertTrue(database.annotationDao().getAllForWork(workUuid).isEmpty())
        val tombstones = database.syncTombstoneDao().getAll()
        assertTrue(tombstones.any { it.recordID == "m-1" && it.recordTypeRaw == SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP })
        assertTrue(tombstones.any { it.recordID == "a-1" && it.recordTypeRaw == SyncTombstoneRecordType.READING_ANNOTATION })
    }

    @Test
    fun sweepExpiredSoftDeletesOnlyRemovesPastSchedule() = runTest {
        val expiredId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        val pendingId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        val now = Instant.parse("2026-06-26T12:00:00Z")
        repository.upsert(sampleSavedWork(expiredId).copy(title = "Long Gone", hasEpub = true))
        repository.upsert(sampleSavedWork(pendingId).copy(title = "Still Pending"))
        fileStore.writeWorkEpub(expiredId, epubBytes)

        // Soft-delete both at "now"; then push expired past the window.
        repository.softDelete(expiredId)
        repository.softDelete(pendingId)
        val expired = repository.getWork(expiredId)!!.copy(
            permanentDeletionScheduledAt = now.minusSeconds(1)
        )
        repository.upsert(expired)

        val removed = repository.sweepExpiredSoftDeletes()

        assertEquals(1, removed)
        assertNull(repository.getWork(expiredId))
        assertFalse(fileStore.workEpubExists(expiredId))
        assertNotNull(repository.getWork(pendingId))
        assertTrue(repository.getWork(pendingId)!!.isDeleted)
        assertEquals(listOf(pendingId), repository.listRecentlyDeleted().map { it.id })
    }

    @Test
    fun sweepExpiredSoftDeletesUsesInjectableClockAtExactBoundary() = runTest {
        val boundaryId = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        val futureId = "dddddddd-dddd-dddd-dddd-dddddddddddd"
        repository.upsert(sampleSavedWork(boundaryId).copy(title = "Hits Window", hasEpub = true))
        repository.upsert(sampleSavedWork(futureId).copy(title = "Still Inside Window"))
        fileStore.writeWorkEpub(boundaryId, epubBytes)

        // Soft-delete at t0 → scheduledAt = t0 + 90d.
        repository.softDelete(boundaryId)
        // Second work soft-deleted one second later so its schedule is after the boundary.
        clockNow = clockNow.plusSeconds(1)
        repository.softDelete(futureId)

        // Advance clock to exact permanentDeletionScheduledAt of boundary work (t0 + 90d).
        // Query is `<= now`, so exact equality must purge.
        clockNow = Instant.parse("2026-06-26T12:00:00Z").plus(WorkRepository.RECOVERY_WINDOW)

        val removed = repository.sweepExpiredSoftDeletes()

        assertEquals(1, removed)
        assertNull(repository.getWork(boundaryId))
        assertFalse(fileStore.workEpubExists(boundaryId))
        assertNotNull(repository.getWork(futureId))
        assertTrue(repository.getWork(futureId)!!.isDeleted)
        // One second before future work's scheduled time — still recoverable.
        assertEquals(
            clockNow.plusSeconds(1),
            repository.getWork(futureId)!!.permanentDeletionScheduledAt
        )
    }

    @Test
    fun userTagsMergeByTrimmedNameAndAvoidDuplicates() = runTest {
        repository.upsert(sampleSavedWork())

        repository.addUserTag(workUuid, " Comfort ")
        val tags = repository.addUserTag(workUuid, "comfort")

        assertEquals(1, tags.size)
        assertEquals("Comfort", tags.first().name)
    }

    @Test
    fun collectionsMembershipCanBeAddedAndRemoved() = runTest {
        repository.upsert(sampleSavedWork())

        val added = repository.addToCollection(workUuid, "Weekend")
        val removed = repository.removeFromCollection(workUuid, added.first().id)

        assertEquals("Weekend", added.first().name)
        assertTrue(removed.isEmpty())
    }

    @Test
    fun createCollectionCreatesEmptyShelfAndDeleteLeavesWorks() = runTest {
        repository.upsert(sampleSavedWork())

        val shelf = repository.createCollection("Classics")
        assertEquals("Classics", shelf.name)
        assertTrue(shelf.workIds.isEmpty())
        assertEquals(1, repository.allCollections().size)

        // Case-insensitive match reuses the shelf instead of duplicating.
        val again = repository.createCollection(" classics ")
        assertEquals(shelf.id, again.id)
        assertEquals(1, repository.allCollections().size)

        repository.addToCollection(workUuid, "Classics")
        val works = repository.worksForCollection(shelf.id)
        assertEquals(listOf(workUuid), works.map { it.id })

        repository.softDeleteCollection(shelf.id)
        assertTrue(repository.allCollections().isEmpty())
        // Work itself remains in the library.
        assertNotNull(repository.getWork(workUuid))
        assertTrue(repository.collectionsForWork(workUuid).isEmpty())
    }

    @Test
    fun deletedCollectionIsRecoverableForNinetyDays() = runTest {
        val shelf = repository.createCollection("Classics")
        repository.softDeleteCollection(shelf.id)

        val deleted = repository.listRecentlyDeletedCollections()
        assertEquals(1, deleted.size)
        assertEquals(shelf.id, deleted.single().id)
        assertNotNull(deleted.single().permanentDeletionScheduledAt)

        val restored = repository.restoreCollectionFromRecentlyDeleted(shelf.id)
        assertNotNull(restored)
        assertEquals(false, restored?.isDeleted)
        assertEquals(1, repository.allCollections().size)
        assertTrue(repository.listRecentlyDeletedCollections().isEmpty())
    }

    @Test
    fun hardDeletingACollectionRemovesItPermanentlyAndRecordsATombstone() = runTest {
        val shelf = repository.createCollection("Classics")
        repository.hardDeleteCollection(shelf.id)

        assertNull(repository.getCollection(shelf.id))
        val tombstone = database.syncTombstoneDao().getAll()
            .firstOrNull { it.recordID == shelf.id }
        assertNotNull(tombstone)
        assertEquals(
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.WORK_COLLECTION,
            tombstone?.recordTypeRaw
        )
    }

    @Test
    fun softDeletingAndRestoringACollectionPreservesItsWorkMemberships() = runTest {
        // Regression test: CollectionDao.upsert used to be @Insert(REPLACE), which is a
        // DELETE+INSERT under the hood and silently cascade-wiped collection_work_cross_refs
        // via the FK ON DELETE CASCADE — every touch (rename, soft-delete, restore) emptied
        // the collection. Same bug class already fixed once for WorkDao.upsert.
        repository.upsert(sampleSavedWork())
        val shelf = repository.createCollection("Classics")
        repository.addToCollection(workUuid, "Classics")
        assertEquals(listOf(workUuid), repository.worksForCollection(shelf.id).map { it.id })

        repository.softDeleteCollection(shelf.id)
        repository.restoreCollectionFromRecentlyDeleted(shelf.id)

        assertEquals(listOf(workUuid), repository.worksForCollection(shelf.id).map { it.id })
    }

    @Test
    fun renameCollectionUpdatesNameInPlaceAndPreservesMemberships() = runTest {
        repository.upsert(sampleSavedWork())
        val shelf = repository.createCollection("Classics")
        repository.addWorkToCollection(workUuid, shelf.id)
        assertEquals(listOf(workUuid), repository.worksForCollection(shelf.id).map { it.id })

        val renamed = repository.renameCollection(shelf.id, "  Favorites  ")
        assertNotNull(renamed)
        assertEquals(shelf.id, renamed?.id)
        assertEquals("Favorites", renamed?.name)
        // Same row id — memberships and history stay put (not delete+recreate).
        assertEquals(listOf(workUuid), repository.worksForCollection(shelf.id).map { it.id })
        assertEquals("Favorites", repository.getCollection(shelf.id)?.name)
        assertEquals(1, repository.allCollections().size)
    }

    @Test
    fun addWorkToCollectionTogglesMembershipById() = runTest {
        repository.upsert(sampleSavedWork())
        val shelf = repository.createCollection("Weekend")
        val added = repository.addWorkToCollection(workUuid, shelf.id)
        assertEquals(1, added.size)
        assertEquals(shelf.id, added.single().id)

        val removed = repository.removeFromCollection(workUuid, shelf.id)
        assertTrue(removed.isEmpty())
        assertTrue(repository.worksForCollection(shelf.id).isEmpty())
    }

    @Test
    fun libraryRepositoryListsSavedWorksOnly() = runTest {
        repository.upsert(sampleSavedWork())
        repository.upsert(sampleSavedWork("33333333-3333-3333-3333-333333333333").copy(isSaved = false))
        val library = io.github.cidy02.kudos.library.LibraryRepository(repository)

        val works = library.observeSavedWorks().first()

        assertEquals(listOf(workUuid), works.map { it.id })
    }

    /** iOS PersistenceSync: any work whose file is gone stops offering it, queued or not (A75 #4). */
    @Test
    fun launchRepairClearsAMissingFileOnAnUnqueuedWorkAndMarksAPreservedCopyMissing() = runTest {
        repository.upsert(sampleSavedWork("11111111-1111-4111-8111-111111111111").copy(hasEpub = true))
        repository.upsert(sampleSavedWork("22222222-2222-4222-8222-222222222222").copy(
            hasEpub = true, epubPreservationStatusRaw = "preserved"))
        repository.upsert(sampleSavedWork("33333333-3333-4333-8333-333333333333").copy(hasEpub = true))
        fileStore.writeWorkEpub("33333333-3333-4333-8333-333333333333", byteArrayOf(1, 2, 3))

        assertEquals(2, repository.repairMissingEpubFlags())
        assertFalse(repository.getWork("11111111-1111-4111-8111-111111111111")!!.hasEpub)
        val preserved = repository.getWork("22222222-2222-4222-8222-222222222222")!!
        assertFalse(preserved.hasEpub)
        assertEquals("missingFile", preserved.epubPreservationStatusRaw)
        assertTrue(repository.getWork("33333333-3333-4333-8333-333333333333")!!.hasEpub)
        assertEquals(0, repository.repairMissingEpubFlags())
    }

    @Test
    fun markFinishedHoldsEpubWhenUnprotected() = runTest {
        repository.upsert(
            sampleSavedWork().copy(isSaved = false, isFavorite = false, hasEpub = true, isFinished = false)
        )
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val finished = repository.setFinished(workUuid, true)

        assertTrue(finished!!.isFinished)
        assertTrue(finished.hasEpub)
        assertEquals(clockNow, finished.freedAt)
        assertTrue(fileStore.workEpubExists(workUuid))

        clockNow = clockNow.plus(java.time.Duration.ofDays(59))
        assertEquals(0, repository.sweepHeldCopies())
        assertTrue(repository.getWork(workUuid)!!.hasEpub)

        clockNow = clockNow.plus(java.time.Duration.ofDays(2))
        assertEquals(1, repository.sweepHeldCopies())
        assertFalse(repository.getWork(workUuid)!!.hasEpub)
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun markFinishedKeepsEpubWhenProtected() = runTest {
        repository.upsert(sampleSavedWork().copy(isSaved = true, hasEpub = true, isFinished = false))
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val finished = repository.setFinished(workUuid, true)

        assertTrue(finished!!.isFinished)
        assertTrue(finished.hasEpub)
        assertTrue(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun freeUpSpaceAlsoFreesLegacyFinishedCopiesWithoutAHoldStamp() = runTest {
        repository.upsert(
            sampleSavedWork().copy(
                isSaved = false,
                isFavorite = false,
                hasEpub = true,
                isFinished = true,
                freedAt = null
            )
        )
        fileStore.writeWorkEpub(workUuid, epubBytes)

        assertEquals(1, repository.freeFinishedCopies())
        assertFalse(repository.getWork(workUuid)!!.hasEpub)
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun restoreHeldCopyKeepsItAndRemoveDownloadOnlyUnkeeps() = runTest {
        repository.upsert(
            sampleSavedWork().copy(isSaved = false, hasEpub = true, isFinished = false)
        )
        fileStore.writeWorkEpub(workUuid, epubBytes)
        repository.setFinished(workUuid, true)

        val restored = repository.restoreHeldCopy(workUuid)!!
        assertTrue(restored.isSaved)
        assertTrue(restored.isDownloaded)
        assertNull(restored.freedAt)

        val unkept = repository.setSaved(workUuid, false)!!
        assertFalse(unkept.isSaved)
        assertTrue(unkept.hasEpub)
        assertTrue(fileStore.workEpubExists(workUuid))

        val freed = repository.freeHeldCopy(workUuid)!!
        assertFalse(freed.hasEpub)
        assertFalse(fileStore.workEpubExists(workUuid))
    }

    @Test
    fun keepOfflineQueueDrivesDownloadedQueryAndClearsHold() = runTest {
        repository.upsert(
            sampleSavedWork().copy(isSaved = false, hasEpub = true, isFinished = true, freedAt = clockNow)
        )
        val queues = io.github.cidy02.kudos.library.ReadingQueueRepository(
            database,
            clock = { clockNow },
        )
        val queue = queues.createQueue("Weekend")

        queues.addWork(queue.id, workUuid)

        val kept = repository.getWork(workUuid)!!
        assertTrue(kept.isKeptOffline)
        assertEquals("Weekend", kept.keptOfflineBy)
        assertTrue(kept.isDownloaded)
        assertNull(kept.freedAt)
    }

    @Test
    fun collectionNilDoesNotKeepButOnDoesAndClearsHold() = runTest {
        repository.upsert(
            sampleSavedWork().copy(isSaved = false, hasEpub = true, isFinished = true, freedAt = clockNow)
        )
        val collection = repository.createCollection("Weekend")
        repository.addWorkToCollection(workUuid, collection.id)

        assertFalse(repository.getWork(workUuid)!!.isKeptOffline)

        val entity = database.collectionDao().getById(collection.id)!!
        database.collectionDao().upsert(entity.copy(keepsWorksOffline = true))
        repository.addWorkToCollection(workUuid, collection.id)

        val kept = repository.getWork(workUuid)!!
        assertTrue(kept.isKeptOffline)
        assertEquals("Weekend", kept.keptOfflineBy)
        assertNull(kept.freedAt)
    }

    @Test
    fun queueReconciliationKeepsRealCopiesWithAndWithoutAFileProbe() = runTest {
        val bytes = javaClass.getResourceAsStream("/epub/sample-source-less.epub").use { requireNotNull(it).readBytes() }
        for (withProbe in listOf(false, true)) {
            val work = repository.upsert(sampleSavedWork(java.util.UUID.randomUUID().toString()).copy(
                isSaved = false, hasEpub = true, isFinished = true,
                freedAt = clockNow.minusSeconds(90L * 86_400), readiumLocator = "kept place"
            ))
            fileStore.writeWorkEpub(work.id, bytes)
            val queues = if (withProbe) {
                io.github.cidy02.kudos.library.ReadingQueueRepository(
                    database, clock = { clockNow }, epubOnDisk = fileStore::workEpubExists
                )
            } else {
                io.github.cidy02.kudos.library.ReadingQueueRepository(database, clock = { clockNow })
            }
            val keep = queues.createQueue("Keep $withProbe")
            val loose = queues.createQueue("Loose $withProbe", keepsWorksOffline = false)
            val membership = queues.addWork(keep.id, work.id, enqueueMissingEpub = false)
            assertTrue(repository.getWork(work.id)!!.isDownloaded)
            assertNull(repository.getWork(work.id)!!.freedAt)

            // Repeat add must release a stale hold too, without duplicating membership.
            repository.upsert(repository.getWork(work.id)!!.copy(freedAt = work.freedAt))
            assertEquals(membership.id, queues.addWork(keep.id, work.id, enqueueMissingEpub = false).id)
            assertNull(repository.getWork(work.id)!!.freedAt)
            queues.normalizeAllQueuedWorks()
            assertEquals(0, repository.sweepHeldCopies(everything = true))
            assertTrue(repository.getWork(work.id)!!.isDownloaded)

            queues.addWork(loose.id, work.id, enqueueMissingEpub = false)
            queues.hardDeleteQueue(keep.id)
            queues.removeWork(loose.id, work.id)
            val remaining = repository.getWork(work.id)!!
            assertTrue(remaining.hasEpub)
            assertFalse(remaining.isDeleted)
            assertFalse(remaining.isQueuedForLater)
            assertEquals("kept place", remaining.readiumLocator)
            assertTrue(bytes.contentEquals(Files.readAllBytes(fileStore.workEpubPath(work.id))))
        }
    }

    @Test
    fun readdingACollectionKeeperPreservesItsRealCopyAndMembershipClock() = runTest {
        val bytes = javaClass.getResourceAsStream("/epub/sample-source-less.epub").use { requireNotNull(it).readBytes() }
        val work = repository.upsert(sampleSavedWork().copy(isSaved = false, hasEpub = true,
            isFinished = true, freedAt = clockNow.minusSeconds(90L * 86_400)))
        fileStore.writeWorkEpub(work.id, bytes)
        val collection = repository.createCollection("Keep later")
        repository.addWorkToCollection(work.id, collection.id)
        val chosenAt = repository.getCollection(collection.id)!!.lastMembershipChangedAt
        assertEquals(work.freedAt, repository.getWork(work.id)!!.freedAt)
        val entity = database.collectionDao().getById(collection.id)!!
        database.collectionDao().upsert(entity.copy(keepsWorksOffline = true))
        clockNow = clockNow.plusSeconds(30)

        repository.addWorkToCollection(work.id, collection.id)

        assertNull(repository.getWork(work.id)!!.freedAt)
        assertEquals(clockNow, repository.getWork(work.id)!!.lastModifiedAt)
        assertEquals(chosenAt, repository.getCollection(collection.id)!!.lastMembershipChangedAt)
        assertEquals(0, repository.sweepHeldCopies(everything = true))
        assertTrue(repository.getWork(work.id)!!.isDownloaded)
        assertTrue(bytes.contentEquals(Files.readAllBytes(fileStore.workEpubPath(work.id))))
    }

    /**
     * iOS `PrivacyDataView.freedHistory`. Clear reading history used to take every finished
     * work, saved and downloaded ones included, under a message promising otherwise (audit A14).
     */
    @Test
    fun clearReadingHistoryTakesOnlyWorksThatRemainInTheHistoryAlone() = runTest {
        fun work(n: Int) = sampleSavedWork("${n}${n}${n}${n}${n}${n}${n}${n}-1111-1111-1111-111111111111")
            .copy(isFinished = true, isSaved = false, hasEpub = false)
        val historyOnly = repository.upsert(work(1))
        val kept = listOf(
            repository.upsert(work(2).copy(isSaved = true)),
            repository.upsert(work(3).copy(isFavorite = true)),
            repository.upsert(work(4).copy(hasEpub = true)),
            repository.upsert(work(5).copy(sourceUrl = "")), // imported: nowhere to get it again
            repository.upsert(work(6).copy(ao3Unavailable = true)), // gone from AO3: the last record of it
            repository.upsert(work(7).copy(isQueuedForLater = true))
        )
        repository.upsert(work(8).copy(isDeleted = true))

        assertEquals(listOf(historyOnly.id), repository.observeHistoryOnlyWorks().first().map { it.id })
        assertEquals(1, repository.softDeleteHistoryOnly())

        val deleted = repository.listRecentlyDeleted().map { it.id }
        assertTrue(historyOnly.id in deleted)
        for (work in kept) {
            assertFalse("${work.id} was promised to stay", repository.getWork(work.id)!!.isDeleted)
        }
        assertTrue(repository.observeHistoryOnlyWorks().first().isEmpty())
    }

    /** iOS `LocalDataClearing.clearReadingPositions`: the place goes, the work and its shelf order stay. */
    @Test
    fun clearReadingPositionsForgetsThePlaceAndKeepsTheWorkAndItsShelfDate() = runTest {
        val read = Instant.parse("2026-07-01T10:00:00Z")
        val a = repository.upsert(sampleSavedWork("aaaaaaaa-1111-1111-1111-111111111111")
            .copy(readiumLocator = "locator", lastSpineIndex = 3, lastScrollFraction = 0.4, lastReadDate = read))
        val b = repository.upsert(sampleSavedWork("bbbbbbbb-1111-1111-1111-111111111111")
            .copy(legacyReaderProgress = 0.5, lastReadDate = read))
        val untouched = repository.upsert(sampleSavedWork("cccccccc-1111-1111-1111-111111111111"))

        assertEquals(setOf(a.id, b.id), repository.observePositionedWorks().first().map { it.id }.toSet())
        assertEquals(2, repository.clearReadingPositions())

        for (id in listOf(a.id, b.id)) {
            val work = repository.getWork(id)!!
            assertTrue(work.readiumLocator.isNullOrEmpty())
            assertEquals(0, work.lastSpineIndex)
            assertEquals(0.0, work.lastScrollFraction, 0.0)
            assertNull(work.legacyReaderProgress)
            assertEquals(read, work.lastReadDate)
            assertNotNull(work.progressModifiedAt)
            assertFalse(work.isDeleted)
        }
        assertEquals(untouched.lastModifiedAt, repository.getWork(untouched.id)!!.lastModifiedAt)
        assertTrue(repository.observePositionedWorks().first().isEmpty())
    }

    /** A page saved while the launch rebuild is between its batches survives. */
    @Test
    fun searchRebuildKeepsAPlaceWrittenBetweenBatches() = runTest {
        val seeded = repository.upsert(sampleSavedWork().copy(lastSpineIndex = 1, isFavorite = false))
        database.workDao().upsert(
            database.workDao().getById(seeded.id)!!.copy(searchIndexVersion = 0, searchText = "")
        )
        val rebuilding = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" },
            beforeIndexingStaleWork = { id ->
                val row = database.workDao().getById(id)!!
                database.workDao().upsert(row.copy(lastSpineIndex = 9, isFavorite = true))
            }
        )
        assertEquals(1, rebuilding.rebuildSearchIndexIfNeeded())
        val after = database.workDao().getById(seeded.id)!!
        assertEquals(9, after.lastSpineIndex)
        assertTrue(after.isFavorite)
        assertEquals(WorkSearchIndex.CURRENT_VERSION, after.searchIndexVersion)
        assertTrue(after.searchText.contains("example"))
    }

    /** Deleting the file must not write back the row from before the delete. */
    @Test
    fun deleteLocalEpubKeepsAPlaceWrittenDuringTheFileDelete() = runTest {
        val id = "33333333-3333-4333-8333-333333333333"
        val hooked = object : WorkFileStore(fileStore.worksDirectory.parent) {
            override suspend fun deleteWorkEpub(workId: String): Boolean {
                val row = database.workDao().getById(workId)!!
                database.workDao().upsert(row.copy(lastSpineIndex = 9, isFavorite = true))
                return super.deleteWorkEpub(workId)
            }
        }
        repository = WorkRepository(
            database, hooked, clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" }
        )
        repository.upsert(sampleSavedWork(id).copy(lastSpineIndex = 1, isFavorite = false, hasEpub = true))
        hooked.writeWorkEpub(id, epubBytes)
        val deleted = repository.deleteLocalEpub(id)!!
        assertEquals(9, deleted.lastSpineIndex)
        assertTrue(deleted.isFavorite)
        assertFalse(deleted.hasEpub)
        assertFalse(deleted.remoteEpubPending)
        assertNull(deleted.freedAt)
    }

    /** The held-copy sweep must not write back the list it loaded at the start. */
    @Test
    fun sweepHeldCopiesKeepsAPlaceWrittenWhileAnEarlierCopyIsFreed() = runTest {
        val freeableId = "33333333-3333-4333-8333-333333333333"
        val keptId = "44444444-4444-4444-8444-444444444444"
        val hooked = object : WorkFileStore(fileStore.worksDirectory.parent) {
            override suspend fun deleteWorkEpub(workId: String): Boolean {
                if (workId == freeableId) {
                    val kept = database.workDao().getById(keptId)!!
                    database.workDao().upsert(kept.copy(lastSpineIndex = 9, isFavorite = true))
                }
                return super.deleteWorkEpub(workId)
            }
        }
        repository = WorkRepository(
            database, hooked, clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" }
        )
        repository.upsert(
            sampleSavedWork(freeableId).copy(
                isSaved = false,
                isFavorite = false,
                isFinished = true,
                hasEpub = true,
                freedAt = clockNow.minus(Duration.ofDays(61))
            )
        )
        hooked.writeWorkEpub(freeableId, epubBytes)
        repository.upsert(
            sampleSavedWork(keptId).copy(
                isSaved = true,
                isFavorite = false,
                lastSpineIndex = 1,
                hasEpub = true,
                freedAt = clockNow.minus(Duration.ofDays(1))
            )
        )
        repository.sweepHeldCopies()
        val kept = database.workDao().getById(keptId)!!
        assertEquals(9, kept.lastSpineIndex)
        assertTrue(kept.isFavorite)
        assertNull(kept.freedAt)
        val freed = database.workDao().getById(freeableId)!!
        assertFalse(freed.hasEpub)
    }

    /**
     * The copies were taken at launch. A title written before the save must be
     * what the stored search text says. Saving the launch copy stamps the old title.
     */
    @Test
    fun searchRebuildWritesTheTitleTheRowHasAtSaveTime() = runTest {
        val ids = listOf(
            "77777777-7777-4777-8777-777777777777",
            "88888888-8888-4888-8888-888888888888"
        )
        ids.forEach { id ->
            val seeded = repository.upsert(sampleSavedWork(id).copy(title = "Old Title"))
            database.workDao().upsert(
                database.workDao().getById(seeded.id)!!.copy(searchIndexVersion = 0, searchText = "")
            )
        }
        val rebuilding = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" },
            beforeIndexingStaleWork = { id ->
                val row = database.workDao().getById(id)!!
                database.workDao().upsert(row.copy(title = "Fresh Title $id"))
            }
        )
        assertEquals(2, rebuilding.rebuildSearchIndexIfNeeded())
        ids.forEach { id ->
            val after = database.workDao().getById(id)!!
            assertEquals("Fresh Title $id", after.title)
            assertEquals(WorkSearchIndex.CURRENT_VERSION, after.searchIndexVersion)
            assertTrue(after.searchText.contains("fresh title"))
            assertTrue(after.searchText.contains(id))
            assertFalse(after.searchText.contains("old title"))
        }
    }

    /**
     * Both copies are past the hold window. Releasing the later one while the
     * earlier file is deleted must leave the later file. Deciding from the list
     * loaded at the start still deletes it.
     */
    @Test
    fun sweepHeldCopiesKeepsAFileWhoseHoldWasReleasedWhileAnEarlierCopyIsFreed() = runTest {
        val earlierId = "55555555-5555-4555-8555-555555555555"
        val laterId = "66666666-6666-4666-8666-666666666666"
        val earlierFreedAt = clockNow.minus(Duration.ofDays(61))
        val hooked = object : WorkFileStore(fileStore.worksDirectory.parent) {
            override suspend fun deleteWorkEpub(workId: String): Boolean {
                if (workId == earlierId) {
                    val later = database.workDao().getById(laterId)!!
                    database.workDao().upsert(later.copy(freedAt = null))
                }
                return super.deleteWorkEpub(workId)
            }
        }
        repository = WorkRepository(
            database, hooked, clock = { clockNow },
            uuidFactory = { "22222222-2222-2222-2222-222222222222" }
        )
        val unprotected = sampleSavedWork().copy(
            isSaved = false,
            isFavorite = false,
            isFinished = true,
            hasEpub = true
        )
        repository.upsert(unprotected.copy(id = earlierId, freedAt = earlierFreedAt))
        hooked.writeWorkEpub(earlierId, epubBytes)
        repository.upsert(
            unprotected.copy(id = laterId, freedAt = earlierFreedAt.plus(Duration.ofHours(1)))
        )
        hooked.writeWorkEpub(laterId, epubBytes)

        assertEquals(1, repository.sweepHeldCopies())

        assertFalse(hooked.workEpubExists(earlierId))
        assertFalse(database.workDao().getById(earlierId)!!.hasEpub)
        assertTrue(hooked.workEpubExists(laterId))
        val later = database.workDao().getById(laterId)!!
        assertTrue(later.hasEpub)
        assertNull(later.freedAt)
    }
}


@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkImporterLifecycleTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository
    private val capturedNow = Instant.parse("2026-10-03T12:34:56Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-import-tests"))
        repository = WorkRepository(database, fileStore, clock = { capturedNow })
    }

    @After
    fun tearDown() {
        database.close()
    }

    /** PreservedWorkTests.userEPUBImportRevivesRecentlyDeletedDuplicate (source-less fixture). */
    @Test
    fun userEPUBImportRevivesRecentlyDeletedDuplicate() = runTest {
        val bytes = javaClass.getResourceAsStream("/epub/sample-source-less.epub").use { requireNotNull(it).readBytes() }
        assertEquals("", EpubImportMetadata.inspect(bytes).sourceUrl)
        val importer = importer(AO3Result.Failure(AO3Error.Network("offline")), AO3Result.Failure(AO3Error.Network("offline")))
        val first = (importer.importLocalEpub("first.epub", bytes) as WorkImportResult.Success).work
        repository.upsert(first.copy(readiumLocator = "kept locator", isFavorite = true))
        repository.softDelete(first.id)

        val revived = (importer.importLocalEpub("renamed.epub", bytes) as WorkImportResult.Success).work
        assertEquals(first.id, revived.id)
        assertFalse(revived.isDeleted)
        assertNull(revived.deletedAt)
        assertNull(revived.permanentDeletionScheduledAt)
        assertEquals("kept locator", revived.readiumLocator)
        assertTrue(revived.isFavorite)
        assertEquals(first.downloadedAt, revived.downloadedAt)
        assertTrue(fileStore.workEpubExists(first.id))
        assertTrue(database.syncTombstoneDao().getByRecord(first.id, SyncTombstoneRecordType.SAVED_WORK).isEmpty())
        assertEquals(1, database.workDao().getAllIncludingDeleted().size)
    }

    /** PreservedWorkTests.addToSavedForLaterRevivesRecentlyDeletedWork's offline assertion. */
    @Test
    fun requeuedWorkStaysRevivedWhenPreservationFailsOffline() = runTest {
        val original = repository.upsert(sampleSavedWork().copy(hasEpub = false))
        repository.softDelete(original.id)
        val queues = io.github.cidy02.kudos.library.ReadingQueueRepository(database, epubOnDisk = fileStore::workEpubExists)
        queues.addToSavedForLater(original.id, enqueueMissingEpub = false)
        val offline = AO3Result.Failure(AO3Error.Network("offline"))
        val result = importer(offline, offline).preserveQueuedWork(repository.getWork(original.id)!!)
        assertTrue(result is WorkImportResult.Failure)
        val revived = repository.getWork(original.id)!!
        assertFalse(revived.isDeleted)
        assertNull(revived.deletedAt)
        assertNull(revived.permanentDeletionScheduledAt)
        assertTrue(revived.isQueuedForLater)
        assertFalse(revived.hasEpub)
        assertEquals("failed", revived.epubPreservationStatusRaw)
        assertTrue(queues.isInSavedForLater(original.id))
        assertTrue(database.syncTombstoneDao().getByRecord(original.id, SyncTombstoneRecordType.SAVED_WORK).isEmpty())
        assertEquals(1, database.workDao().getAllIncludingDeleted().size)
    }

    /** ReadingQueueTests.removeLastQueueMembershipDoesNotDeleteWorkByDefault's actual-file assertion. */
    @Test
    fun removingLastQueueMembershipKeepsTheActualEpubAndPlace() = runTest {
        val bytes = javaClass.getResourceAsStream("/epub/sample-source-less.epub").use { requireNotNull(it).readBytes() }
        val work = repository.upsert(sampleSavedWork().copy(isSaved = false, hasEpub = true, readiumLocator = "kept place"))
        fileStore.writeWorkEpub(work.id, bytes)
        val queues = io.github.cidy02.kudos.library.ReadingQueueRepository(database, epubOnDisk = fileStore::workEpubExists)
        val queue = queues.createQueue("Reading")
        queues.addWork(queue.id, work.id, enqueueMissingEpub = false)
        queues.removeWork(queue.id, work.id)
        val remaining = repository.getWork(work.id)!!
        assertFalse(remaining.isDeleted)
        assertFalse(remaining.isQueuedForLater)
        assertNull(remaining.permanentDeletionScheduledAt)
        assertEquals("kept place", remaining.readiumLocator)
        assertTrue(fileStore.workEpubExists(work.id))
        assertTrue(bytes.contentEquals(Files.readAllBytes(fileStore.workEpubPath(work.id))))
    }

    @Test
    fun directRedownloadRevivesBeforeAnOfflineFailure() = runTest {
        val existing = repository.upsert(sampleSavedWork().copy(hasEpub = false))
        repository.softDelete(existing.id)
        val offline = AO3Result.Failure(AO3Error.Network("offline"))
        val result = importer(offline, offline).downloadExisting(repository.getWork(existing.id)!!)
        assertTrue(result is WorkImportResult.Failure)
        val revived = repository.getWork(existing.id)!!
        assertFalse(revived.isDeleted)
        assertNull(revived.permanentDeletionScheduledAt)
        assertFalse(revived.hasEpub)
        assertTrue(database.syncTombstoneDao().getByRecord(existing.id, SyncTombstoneRecordType.SAVED_WORK).isEmpty())
    }

    @Test
    fun sourceLessImportDoesNotCollapseDifferentTitlesOrFileSizes() = runTest {
        val importer = importer(AO3Result.Failure(AO3Error.NotFound), AO3Result.Failure(AO3Error.NotFound))
        fun epub(title: String, text: String) = io.github.cidy02.kudos.works.converters.EpubBuilder.buildEpub(title, "<p>$text</p>")
        val originalBytes = epub("First", "A chapter")
        val first = (importer.importLocalEpub("first.epub", originalBytes) as WorkImportResult.Success).work
        val renamed = (importer.importLocalEpub("renamed.epub", epub("Second", "A chapter")) as WorkImportResult.Success).work
        assertTrue(first.id != renamed.id)
        val changedBytes = epub("First", "An entirely different and much longer chapter, with other words and content.")
        assertTrue(originalBytes.size != changedBytes.size)
        val changed = (importer.importLocalEpub("changed.epub", changedBytes) as WorkImportResult.Success).work
        assertTrue(first.id != changed.id)
        assertEquals(3, database.workDao().getAllIncludingDeleted().size)
    }

    /** PreservedWorkTests.importEPUBMergesAcrossAO3URLVariants. */
    @Test
    fun importEPUBMergesAcrossAO3URLVariants() = runTest {
        val existing = repository.upsert(sampleSavedWork().copy(
            sourceUrl = "https://archiveofourown.org/downloads/123/story.epub",
            ao3WorkID = null,
            readiumLocator = "kept locator"
        ))
        val imported = (importer(AO3Result.Failure(AO3Error.NotFound), AO3Result.Success(epubBytes))
            .download(sampleSummary()) as WorkImportResult.Success).work
        assertEquals(existing.id, imported.id)
        assertEquals("kept locator", imported.readiumLocator)
        assertEquals(1, database.workDao().getAllIncludingDeleted().size)
        assertTrue(fileStore.workEpubExists(existing.id))
    }

    @Test
    fun saveOnlyCreatesMetadataRecordWithoutEpub() = runTest {
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(fandoms = listOf("Fandom"), words = 99)),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.saveMetadataOnly(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.isSaved)
        assertFalse(work.hasEpub)
        assertEquals(listOf("Fandom"), work.workFandoms)
        assertTrue(work.workTagsFetched)
    }

    @Test
    fun keepingAWorkThatIsAlreadyHereGivesItANewerClock() = runTest {
        // A merge takes the newer snapshot's kept flag. A work kept through this path used
        // to keep its old clock, so the copy in the sync folder, not kept and no older, took
        // the flag back at the next sync.
        val before = Instant.parse("2026-09-01T00:00:00Z")
        repository.upsert(sampleSavedWork().copy(isSaved = false, lastModifiedAt = before))
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val kept = (importer.saveMetadataOnly(sampleSummary()) as WorkImportResult.Success).work
        assertTrue(kept.isSaved)
        assertEquals(capturedNow, kept.lastModifiedAt)

        // Saved again with nothing changed, the clock stays where it is.
        repository.upsert(kept.copy(lastModifiedAt = before))
        val again = (importer.saveMetadataOnly(sampleSummary()) as WorkImportResult.Success).work
        assertEquals(before, again.lastModifiedAt)
    }

    @Test
    fun downloadSuccessSetsHasEpubOnlyAfterFileExists() = runTest {
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.download(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.hasEpub)
        assertEquals(capturedNow, work.downloadedAt)
        assertTrue(fileStore.workEpubExists(work.id))
    }

    /** A page read or a Finished mark set while the EPUB comes down is kept. */
    @Test
    fun aPlaceReadWhileTheEpubDownloadsIsKept() = runTest {
        val existing = repository.upsert(sampleSavedWork().copy(sourceUrl = "https://archiveofourown.org/works/123"))
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes),
            onDownload = {
                repository.upsert(repository.getWork(existing.id)!!.copy(readiumLocator = "read-meanwhile", isFinished = true))
            }
        )

        val work = (importer.downloadExisting(repository.getWork(existing.id)!!) as WorkImportResult.Success).work

        assertEquals("read-meanwhile", work.readiumLocator)
        assertTrue(work.isFinished)
        assertTrue(work.hasEpub)
    }

    @Test
    fun redownloadKeepsTheCapturedDownloadDate() = runTest {
        val originalDate = capturedNow.minusSeconds(86_400)
        val existing = sampleSavedWork().copy(
            sourceUrl = "https://archiveofourown.org/works/123",
            downloadedAt = originalDate
        )
        repository.upsert(existing)
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.downloadExisting(existing)

        assertEquals(originalDate, (result as WorkImportResult.Success).work.downloadedAt)
    }

    @Test
    fun downloadPreservesExistingFinishedState() = runTest {
        repository.upsert(sampleSavedWork().copy(isFinished = true, isFavorite = true))
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.download(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.hasEpub)
        assertTrue(work.isFinished)
        assertTrue(work.isFavorite)
    }

    @Test
    fun downloadingAWorkThatMatchesARecentlyDeletedRowRevivesIt() = runTest {
        // End-to-end version of WorkMetadataMergerTest's revival cases — through the
        // real WorkImporter and a real in-memory Room DB, exercising the exact path a
        // user hits: delete a work, then download the same AO3 work again (directly,
        // or as part of a series). Before the fix, this reported success while the
        // work stayed hidden in Recently Deleted, still counting down to permanent
        // removal.
        repository.upsert(sampleSavedWork().copy(hasEpub = true))
        repository.softDelete(workUuid)
        assertTrue(repository.getWork(workUuid)!!.isDeleted)

        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )
        val result = importer.download(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertFalse("re-downloading a soft-deleted work must revive it", work.isDeleted)
        assertNull(work.deletedAt)
        assertNull(work.permanentDeletionScheduledAt)
        assertTrue(repository.observeSavedWorks().first().any { it.id == workUuid })
        // WorkMetadataMerger clears the soft-delete fields but has no repository
        // access to retract the tombstone itself — WorkImporter must do that after
        // the merge, or a later backup merge would treat the stale tombstone as
        // authoritative and silently re-hide the just-revived work on another device.
        assertTrue(
            "reviving via download must retract the sync tombstone",
            database.syncTombstoneDao().getByRecord(
                workUuid,
                io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK
            ).isEmpty()
        )
    }

    @Test
    fun savingMetadataOnlyForARecentlyDeletedRowRevivesItAndRetractsTombstone() = runTest {
        // Same bug class as the download-revival case above, for the "Save" (no EPUB)
        // path: WorkMetadataMerger clears the soft-delete fields on its own, but only
        // WorkImporter can retract the sync tombstone, since the merger is a pure
        // function with no repository access.
        repository.upsert(sampleSavedWork())
        repository.softDelete(workUuid)
        assertTrue(repository.getWork(workUuid)!!.isDeleted)

        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Failure(AO3Error.NotFound)
        )
        val result = importer.saveMetadataOnly(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertFalse("re-saving a soft-deleted work must revive it", work.isDeleted)
        assertNull(work.deletedAt)
        assertNull(work.permanentDeletionScheduledAt)
        assertTrue(
            database.syncTombstoneDao().getByRecord(
                workUuid,
                io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK
            ).isEmpty()
        )
    }

    @Test
    fun downloadExistingOnAQueueOnlyWorkDoesNotSilentlyMarkItSaved() = runTest {
        // Regression test for a real bug found in review: persistDownloadedEpub used
        // to hardcode isSaved=true, so a queue-only work's EPUB-preserve download
        // (WorkDetailScreen.preserveEpubForQueue -> DownloadQueue -> downloadExisting)
        // would silently undo T-89's whole point the moment the download finished.
        val queueOnly = sampleSavedWork().copy(isSaved = false, isQueuedForLater = true, hasEpub = false)
        repository.upsert(queueOnly)
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.downloadExisting(queueOnly)

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.hasEpub)
        assertFalse("EPUB-preserve download must not mark a queue-only work isSaved", work.isSaved)
        assertTrue(
            "still excluded from the saved-works library query after the download completes",
            repository.observeSavedWorks().first().none { it.id == work.id }
        )
    }

    @Test
    fun downloadFailureDoesNotSetHasEpub() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.Server(503))
        )

        val result = importer.download(sampleSummary())

        val failure = result as WorkImportResult.Failure
        assertEquals(AO3Error.Server(503), failure.error)
        assertFalse(failure.work!!.hasEpub)
        assertFalse(fileStore.workEpubExists(failure.work.id))
    }

    @Test
    fun importLocalEpubPersistsSavedWorkWithBlankSourceUrl() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.importLocalEpub(
            displayName = "My Favorite Fic.epub",
            bytes = epubBytes
        )

        val work = (result as WorkImportResult.Success).work
        assertEquals("My Favorite Fic", work.title)
        assertEquals("", work.author)
        assertEquals("", work.sourceUrl)
        assertTrue(work.hasEpub)
        assertTrue(work.isSaved)
        assertEquals(capturedNow, work.downloadedAt)
        assertTrue(fileStore.workEpubExists(work.id))
        val stored = repository.getWork(work.id)
        assertNotNull(stored)
        assertEquals(work.id, stored!!.id)
        assertEquals(work.title, stored.title)
        assertEquals("", stored.sourceUrl)
        assertTrue(stored.hasEpub)
        assertTrue(stored.isSaved)
    }

    @Test
    fun importedEpubReadsOpfMetadata() {
        val metadata = EpubImportMetadata.inspect(syntheticAo3Epub(includePrefaceMetadata = false))

        assertEquals("OPF Title", metadata.title)
        assertEquals("OPF Author", metadata.author)
        assertEquals("<p>OPF Summary</p>", metadata.summary)
        assertEquals("https://archiveofourown.org/works/424242", metadata.sourceUrl)
        assertEquals("Teen And Up Audiences", metadata.rating)
        assertEquals("English", metadata.language)
        assertEquals("2020-01-01", metadata.publishedDate)
        assertEquals("2021-02-03", metadata.updatedDate)
        assertEquals("Series Name", metadata.seriesTitle)
        assertEquals(2, metadata.seriesIndex)
        assertEquals(1_234, metadata.wordCount)
        assertEquals(2, metadata.localChapterCount)
        assertTrue(metadata.subjects.contains("Subject fallback"))
    }

    @Test
    fun importedEpubScansAo3PrefaceMetadata() {
        val metadata = EpubImportMetadata.inspect(syntheticAo3Epub())

        assertEquals("https://archiveofourown.org/works/424242", metadata.sourceUrl)
        assertEquals("Explicit", metadata.rating)
        assertEquals("2022-03-04", metadata.publishedDate)
        assertEquals("2023-05-06", metadata.updatedDate)
        assertEquals(2_345, metadata.wordCount)
        assertEquals("2/3", metadata.chapters)
        assertEquals(10, metadata.kudos)
        assertEquals(4, metadata.comments)
        assertEquals(100, metadata.hits)
        assertEquals(true, metadata.isComplete)
        assertEquals(listOf("New Fandom"), metadata.fandoms)
        assertEquals(listOf("A/B"), metadata.relationships)
        assertEquals(listOf("Alice"), metadata.characters)
        assertEquals(listOf("Fluff"), metadata.freeforms)
        assertEquals(listOf("No Archive Warnings Apply"), metadata.warnings)
        assertEquals(listOf("F/F"), metadata.categories)
    }

    @Test
    fun websiteEpubImportsItsMetadataAndReusesLocalIdentity() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Success(syntheticAo3Epub())
        )
        val url = "https://archiveofourown.org/downloads/424242/book.epub?updated=1"
        val first = (importer.importWebEpub(url) as WorkImportResult.Success).work
        repository.upsert(first.copy(isFavorite = true, readiumLocator = "kept position"))
        val again = (importer.importWebEpub(url) as WorkImportResult.Success).work
        assertEquals(first.id, again.id)
        assertEquals(424242, again.ao3WorkID)
        assertTrue(again.hasEpub && again.isSaved && again.isFavorite)
        assertEquals("kept position", again.readiumLocator)
        assertTrue(fileStore.workEpubExists(again.id))
        assertEquals(1, repository.listSavedWorks().size)
        assertTrue(importer.importWebEpub("https://example.com/book.epub") is WorkImportResult.Failure)
    }

    @Test
    fun duplicateEpubImportFillsMissingMetadataWithoutOverwritingAndRestores() = runTest {
        repository.upsert(
            SavedWork(
                id = workUuid,
                title = "Reader title",
                author = "Reader author",
                sourceUrl = "https://archiveofourown.org/works/424242",
                rating = "Mature",
                wordCount = 999,
                workFandoms = listOf("Old Fandom"),
                isSaved = true,
                hasEpub = false
            )
        )
        repository.softDelete(workUuid)
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.importLocalEpub("different-name.epub", syntheticAo3Epub())

        val work = (result as WorkImportResult.Success).work
        assertEquals(workUuid, work.id)
        assertEquals("Reader title", work.title)
        assertEquals("Reader author", work.author)
        assertEquals("<p>OPF Summary</p>", work.summary)
        assertEquals("Mature", work.rating)
        assertEquals(999, work.wordCount)
        assertEquals(listOf("Old Fandom", "New Fandom"), work.workFandoms)
        assertEquals(424242, work.ao3WorkID)
        assertFalse(work.isDeleted)
        assertTrue(work.hasEpub)
        assertEquals(capturedNow, work.downloadedAt)
        assertEquals(1, repository.listSavedWorks().size)
        assertTrue(
            database.syncTombstoneDao().getByRecord(
                workUuid,
                SyncTombstoneRecordType.SAVED_WORK
            ).isEmpty()
        )
    }

    @Test
    fun importLocalEpubRejectsUnsupportedExtension() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        // epub/pdf/html/htm/txt are all supported imports (txt/html/pdf via
        // works/converters). Anything outside that list must still be rejected.
        val result = importer.importLocalEpub(
            displayName = "notes.docx",
            bytes = epubBytes
        )

        val failure = result as WorkImportResult.Failure
        assertTrue(failure.error is AO3Error.Validation)
        assertNull(failure.work)
    }

    @Test
    fun savingMetadataOnlyAsQueueOnlyDoesNotMarkSavedAndIsExcludedFromTheLibrary() = runTest {
        // End-to-end: a queue-only work must not appear in observeSavedWorks() (the
        // same query Home/Library shelves are built from), while still being a real
        // row a reading-queue screen can look up by id.
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.saveMetadataOnly(sampleSummary(), markSaved = false, isQueuedForLater = true)

        val work = (result as WorkImportResult.Success).work
        assertFalse(work.isSaved)
        assertTrue(work.isQueuedForLater)
        assertTrue(work.isQueueOnlyWork)
        assertTrue(
            "a queue-only work must not show up in the saved-works library query",
            repository.observeSavedWorks().first().none { it.id == work.id }
        )
        assertNotNull("the row itself still exists for the Reading Queues screen", repository.getWork(work.id))
    }

    /** Re-importing an EPUB the library already has must not write the pre-write row. */
    @Test
    fun reimportKeepsAPlaceWrittenDuringTheEpubWrite() = runTest {
        val id = "55555555-5555-4555-8555-555555555555"
        val hooked = object : WorkFileStore(fileStore.worksDirectory.parent) {
            override suspend fun writeWorkEpub(workId: String, bytes: ByteArray): FileWriteResult {
                val row = database.workDao().getById(workId)!!
                database.workDao().upsert(row.copy(lastSpineIndex = 9, isFavorite = true))
                return super.writeWorkEpub(workId, bytes)
            }
        }
        fileStore = hooked
        repository = WorkRepository(database, fileStore, clock = { capturedNow })
        repository.upsert(
            sampleSavedWork(id).copy(
                sourceUrl = "https://archiveofourown.org/works/424242",
                lastSpineIndex = 1,
                isFavorite = false,
                hasEpub = false,
                title = "Local title"
            )
        )
        val result = importer(
            AO3Result.Failure(AO3Error.NotFound),
            AO3Result.Failure(AO3Error.NotFound)
        ).importLocalEpub("book.epub", syntheticAo3Epub())
        val saved = result as WorkImportResult.Success
        assertEquals(id, saved.work.id)
        assertEquals(9, saved.work.lastSpineIndex)
        assertTrue(saved.work.isFavorite)
        assertTrue(saved.work.hasEpub)
    }

    /** Preserving a queued work must not write the row from before the exists check. */
    @Test
    fun preserveKeepsAPlaceWrittenDuringTheExistsCheck() = runTest {
        val id = "66666666-6666-4666-8666-666666666666"
        val hooked = object : WorkFileStore(fileStore.worksDirectory.parent) {
            override suspend fun workEpubExists(workId: String): Boolean {
                val row = database.workDao().getById(workId) ?: return super.workEpubExists(workId)
                database.workDao().upsert(row.copy(lastSpineIndex = 9, isFavorite = true))
                return super.workEpubExists(workId)
            }
        }
        fileStore = hooked
        repository = WorkRepository(database, fileStore, clock = { capturedNow })
        val work = repository.upsert(
            sampleSavedWork(id).copy(hasEpub = true, lastSpineIndex = 1, isFavorite = false)
        )
        hooked.writeWorkEpub(id, epubBytes)
        val result = importer(
            AO3Result.Failure(AO3Error.NotFound),
            AO3Result.Failure(AO3Error.NotFound)
        ).preserveQueuedWork(repository.getWork(work.id)!!)
        val preserved = result as WorkImportResult.Success
        assertEquals("preserved", preserved.work.epubPreservationStatusRaw)
        assertEquals(9, preserved.work.lastSpineIndex)
        assertTrue(preserved.work.isFavorite)
    }

    @Test
    fun importLocalEpubRejectsNonZipPayload() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.importLocalEpub(
            displayName = "fake.epub",
            bytes = "not a zip".toByteArray()
        )

        val failure = result as WorkImportResult.Failure
        assertTrue(failure.error is AO3Error.Validation)
        assertTrue(
            (failure.error as AO3Error.Validation).message.contains("ZIP", ignoreCase = true)
        )
    }

    private fun importer(
        metadata: AO3Result<AO3WorkMetadata>,
        download: AO3Result<ByteArray>,
        onDownload: suspend () -> Unit = {}
    ): WorkImporter {
        val client = FakeAO3Client(
            onDownload = onDownload,
            text = when (metadata) {
                is AO3Result.Failure -> metadata
                is AO3Result.Success -> AO3Result.Success(
                    AO3HttpResponse(
                        url = "https://archiveofourown.org/works/123?view_adult=true",
                        statusCode = 200,
                        headers = emptyMap(),
                        body = "<html></html>"
                    )
                )
            },
            bytes = when (download) {
                is AO3Result.Failure -> download
                is AO3Result.Success -> AO3Result.Success(
                    AO3BinaryResponse(
                        url = "https://archiveofourown.org/downloads/123/work.epub",
                        statusCode = 200,
                        headers = mapOf("Content-Type" to listOf("application/epub+zip")),
                        body = download.value
                    )
                )
            }
        )
        val metadataRepository = object : AO3WorkMetadataRepository(client) {
            override suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> = metadata
        }
        return WorkImporter(
            workRepository = repository,
            metadataRepository = metadataRepository,
            downloader = AO3EpubDownloader(client),
            fileStore = fileStore,
            cacheDir = Files.createTempDirectory("kudos-import-cache-tests").toFile(),
            merger = WorkMetadataMerger(uuidFactory = { workUuid })
        )
    }
}

private class FakeAO3Client(
    private val text: AO3Result<AO3HttpResponse>,
    private val bytes: AO3Result<AO3BinaryResponse>,
    private val onDownload: suspend () -> Unit = {}
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = text

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> {
        onDownload()
        return bytes
    }
}

private const val workUuid = "11111111-1111-1111-1111-111111111111"
private val epubBytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

private fun syntheticAo3Epub(includePrefaceMetadata: Boolean = true): ByteArray {
    val opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>OPF Title</dc:title>
            <dc:creator>OPF Author</dc:creator>
            <dc:description>&lt;p&gt;OPF Summary&lt;/p&gt;</dc:description>
            <dc:source>https://archiveofourown.org/downloads/424242/book.epub</dc:source>
            <dc:language>en</dc:language>
            <dc:subject>Teen And Up Audiences</dc:subject>
            <dc:subject>Subject fallback</dc:subject>
            <dc:subject>No Archive Warnings Apply</dc:subject>
            <dc:subject>Gen</dc:subject>
            <dc:date>2020-01-01</dc:date>
            <meta property="dcterms:modified">2021-02-03</meta>
            <meta name="calibre:series" content="Series Name"/>
            <meta name="calibre:series_index" content="2.0"/>
            <meta name="calibre:word_count" content="1,234"/>
          </metadata>
          <manifest>
            <item id="preface" href="preface.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="preface"/>
            <itemref idref="chapter"/>
          </spine>
        </package>
    """.trimIndent()
    val preface = if (includePrefaceMetadata) {
        """
            <html><body>
              <h2 class="title">Preface title</h2>
              <h3 class="byline"><a rel="author">Preface author</a></h3>
              <p>Posted at <a href="https://archiveofourown.org/works/424242">AO3</a>.</p>
              <div class="summary"><blockquote>Preface summary</blockquote></div>
              <dl>
                <dt>Rating:</dt><dd><a>Explicit</a></dd>
                <dt>Archive Warning:</dt><dd><a>No Archive Warnings Apply</a></dd>
                <dt>Category:</dt><dd><a>F/F</a></dd>
                <dt>Fandom:</dt><dd><a>New Fandom</a></dd>
                <dt>Relationships:</dt><dd><a>A/B</a></dd>
                <dt>Characters:</dt><dd><a>Alice</a></dd>
                <dt>Additional Tags:</dt><dd><a>Fluff</a></dd>
                <dt>Language:</dt><dd>English</dd>
                <dt>Status:</dt><dd>Complete</dd>
                <dt>Stats:</dt><dd>
                  Published: 2022-03-04 Updated: 2023-05-06 Words: 2,345
                  Chapters: 2/3 Kudos: 10 Comments: 4 Hits: 100
                </dd>
              </dl>
            </body></html>
        """.trimIndent()
    } else {
        "<html><body><p>Chapter one.</p></body></html>"
    }
    val output = ByteArrayOutputStream()
    ZipOutputStream(output).use { zip ->
        fun entry(name: String, value: String) {
            zip.putNextEntry(ZipEntry(name))
            zip.write(value.toByteArray())
            zip.closeEntry()
        }
        entry("mimetype", "application/epub+zip")
        entry(
            "META-INF/container.xml",
            """<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"""
        )
        entry("OEBPS/content.opf", opf)
        entry("OEBPS/preface.xhtml", preface)
        entry("OEBPS/chapter.xhtml", "<html><body><p>Chapter two.</p></body></html>")
    }
    return output.toByteArray()
}

private fun sampleSummary(): AO3WorkSummary {
    return AO3WorkSummary(
        id = 123,
        title = "Example",
        authors = listOf("Alice"),
        fandoms = listOf("Fandom"),
        rating = "Teen",
        warnings = listOf("No Archive Warnings Apply"),
        categories = listOf("Gen"),
        relationships = listOf("A/B"),
        characters = listOf("A"),
        freeforms = listOf("Fluff"),
        summary = "Summary",
        language = "English",
        wordCount = 1200,
        chapters = "1/1",
        kudos = 7,
        comments = 2,
        hits = 99,
        isComplete = true
    )
}

private fun sampleSavedWork(id: String = workUuid): SavedWork {
    return SavedWork(
        id = id,
        title = "Example",
        author = "Alice",
        summary = "Summary",
        sourceUrl = "https://archiveofourown.org/works/123",
        dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
        isSaved = true,
        hasEpub = false
    )
}
