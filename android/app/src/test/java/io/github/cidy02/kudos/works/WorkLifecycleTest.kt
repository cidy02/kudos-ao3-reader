package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
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
import java.nio.file.Files
import java.time.Instant
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

    @Test
    fun workRepositoryInsertUpdateAndToggles() = runTest {
        repository.upsert(sampleSavedWork())

        assertEquals("Example", repository.getWork(workUuid)?.title)
        assertTrue(repository.toggleFavorite(workUuid)!!.isFavorite)
        assertTrue(repository.toggleFinished(workUuid)!!.isFinished)
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
                io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_WORK
            ).isEmpty()
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

    @Test
    fun markFinishedFreesEpubWhenUnprotected() = runTest {
        // History-only: not saved, not favorite — Apple WorkLifecycle free-on-finish.
        repository.upsert(
            sampleSavedWork().copy(isSaved = false, isFavorite = false, hasEpub = true, isFinished = false)
        )
        fileStore.writeWorkEpub(workUuid, epubBytes)

        val finished = repository.setFinished(workUuid, true)

        assertTrue(finished!!.isFinished)
        assertFalse(finished.hasEpub)
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
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkImporterLifecycleTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var repository: WorkRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-import-tests"))
        repository = WorkRepository(database, fileStore)
    }

    @After
    fun tearDown() {
        database.close()
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
    fun downloadSuccessSetsHasEpubOnlyAfterFileExists() = runTest {
        val importer = importer(
            metadata = AO3Result.Success(AO3WorkMetadata(chapters = "1/1")),
            download = AO3Result.Success(epubBytes)
        )

        val result = importer.download(sampleSummary())

        val work = (result as WorkImportResult.Success).work
        assertTrue(work.hasEpub)
        assertTrue(fileStore.workEpubExists(work.id))
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
    fun importLocalEpubRejectsNonEpubExtension() = runTest {
        val importer = importer(
            metadata = AO3Result.Failure(AO3Error.NotFound),
            download = AO3Result.Failure(AO3Error.NotFound)
        )

        val result = importer.importLocalEpub(
            displayName = "notes.txt",
            bytes = epubBytes
        )

        val failure = result as WorkImportResult.Failure
        assertTrue(failure.error is AO3Error.Validation)
        assertNull(failure.work)
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
        download: AO3Result<ByteArray>
    ): WorkImporter {
        val client = FakeAO3Client(
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
            merger = WorkMetadataMerger(uuidFactory = { workUuid })
        )
    }
}

private class FakeAO3Client(
    private val text: AO3Result<AO3HttpResponse>,
    private val bytes: AO3Result<AO3BinaryResponse>
) : AO3Client {
    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = text

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> = bytes
}

private const val workUuid = "11111111-1111-1111-1111-111111111111"
private val epubBytes = byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3)

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
