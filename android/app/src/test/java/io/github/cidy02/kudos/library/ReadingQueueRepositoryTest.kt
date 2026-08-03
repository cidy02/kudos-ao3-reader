package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadingQueueRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var repository: ReadingQueueRepository
    private val uuidSeq = AtomicInteger(0)
    private val fixedNow = Instant.parse("2026-07-31T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = ReadingQueueRepository(
            database = database,
            clock = { fixedNow },
            uuidFactory = { "id-${uuidSeq.incrementAndGet()}" }
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun ensureSavedForLaterCreatesDefaultQueueOnce() = runTest {
        val first = repository.ensureSavedForLaterQueue()
        val second = repository.ensureSavedForLaterQueue()

        assertEquals(first.id, second.id)
        assertEquals(ReadingQueueKind.SAVED_FOR_LATER, first.kindRaw)
        assertEquals(ReadingQueueKind.SAVED_FOR_LATER_NAME, first.displayName)
        assertEquals(1, repository.listQueues().size)
    }

    @Test
    fun addWorkListWorksAndRemoveWorkRoundTrip() = runTest {
        val workA = savedWork("work-a", title = "Alpha")
        val workB = savedWork("work-b", title = "Beta")
        database.workDao().upsert(workA.toEntity())
        database.workDao().upsert(workB.toEntity())

        val queue = repository.ensureSavedForLaterQueue()
        repository.addWork(queue.id, workA.id)
        repository.addWork(queue.id, workB.id)
        // Idempotent: second add does not duplicate membership.
        repository.addWork(queue.id, workA.id)

        val listed = repository.listWorks(queue.id)
        assertEquals(listOf("Alpha", "Beta"), listed.map { it.title })
        assertEquals(listOf("Author A", "Author B"), listed.map { it.author })
        assertTrue(repository.isInSavedForLater(workA.id))

        repository.removeWork(queue.id, workA.id)
        assertFalse(repository.isInSavedForLater(workA.id))
        assertEquals(listOf("Beta"), repository.listWorks(queue.id).map { it.title })
    }

    @Test
    fun listWorksExcludesSoftDeletedWorks() = runTest {
        // Same bug class already fixed for Collections: a queue membership must not
        // surface a work that's currently sitting in Recently Deleted.
        val kept = savedWork("work-kept", title = "Kept")
        val softDeleted = savedWork("work-deleted", title = "Deleted").copy(isDeleted = true)
        database.workDao().upsert(kept.toEntity())
        database.workDao().upsert(softDeleted.toEntity())

        val queue = repository.ensureSavedForLaterQueue()
        repository.addWork(queue.id, kept.id)
        repository.addWork(queue.id, softDeleted.id)

        assertEquals(listOf("Kept"), repository.listWorks(queue.id).map { it.title })
    }

    @Test
    fun listWorksShowsMissingWorkFallbackTitle() = runTest {
        val queue = repository.ensureSavedForLaterQueue()
        // Membership without a corresponding work row (tombstone / restore edge case).
        repository.addWork(queue.id, "ghost-work")

        val listed = repository.listWorks(queue.id)
        assertEquals(1, listed.size)
        assertEquals("Missing work", listed.single().title)
        assertEquals(null, listed.single().work)
    }

    @Test
    fun addToSavedForLaterUsesDefaultQueue() = runTest {
        val work = savedWork("work-later", title = "Later Read")
        database.workDao().upsert(work.toEntity())

        repository.addToSavedForLater(work.id)

        val queue = repository.listQueues().single()
        assertEquals(ReadingQueueKind.SAVED_FOR_LATER, queue.kindRaw)
        assertEquals(listOf("Later Read"), repository.listWorks(queue.id).map { it.title })

        repository.removeFromSavedForLater(work.id)
        assertTrue(repository.listWorks(queue.id).isEmpty())
        assertFalse(repository.isInSavedForLater(work.id))
    }

    @Test
    fun addWorkSetsIsQueuedForLaterAndPreservesIsSaved() = runTest {
        val savedWork = savedWork("work-saved", title = "Saved").copy(isSaved = true, isQueuedForLater = false)
        val notSavedWork = savedWork("work-unsaved", title = "Unsaved").copy(isSaved = false, isQueuedForLater = false)
        database.workDao().upsert(savedWork.toEntity())
        database.workDao().upsert(notSavedWork.toEntity())

        val queue = repository.ensureSavedForLaterQueue()

        repository.addWork(queue.id, savedWork.id)
        val updatedSaved = database.workDao().getById(savedWork.id)!!.toDomain()
        assertTrue(updatedSaved.isQueuedForLater)
        assertTrue(updatedSaved.isSaved)
        assertFalse(updatedSaved.isQueueOnlyWork)

        repository.addWork(queue.id, notSavedWork.id)
        val updatedUnsaved = database.workDao().getById(notSavedWork.id)!!.toDomain()
        assertTrue(updatedUnsaved.isQueuedForLater)
        assertFalse(updatedUnsaved.isSaved)
        assertTrue(updatedUnsaved.isQueueOnlyWork)
    }

    @Test
    fun removeWorkClearsIsQueuedForLaterWhenNoQueuesRemainAndSoftDeletesIfQueueOnly() = runTest {
        val notSavedWork = savedWork("work-unsaved", title = "Unsaved").copy(isSaved = false, isQueuedForLater = false)
        database.workDao().upsert(notSavedWork.toEntity())

        val queue = repository.ensureSavedForLaterQueue()
        repository.addWork(queue.id, notSavedWork.id)

        repository.removeWork(queue.id, notSavedWork.id)
        val updatedUnsaved = database.workDao().getById(notSavedWork.id)!!.toDomain()
        assertFalse(updatedUnsaved.isQueuedForLater)
        assertTrue("queue-only work loses its only queue -> soft-deleted", updatedUnsaved.isDeleted)

        val savedWork = savedWork("work-saved", title = "Saved").copy(isSaved = true, isQueuedForLater = false)
        database.workDao().upsert(savedWork.toEntity())
        repository.addWork(queue.id, savedWork.id)

        repository.removeWork(queue.id, savedWork.id)
        val updatedSaved = database.workDao().getById(savedWork.id)!!.toDomain()
        assertFalse(updatedSaved.isQueuedForLater)
        assertTrue("an explicitly-saved work is never deleted just for losing a queue", updatedSaved.isSaved)
        assertFalse(updatedSaved.isDeleted)
    }

    @Test
    fun removeWorkDoesNotSoftDeleteAFavoritedQueueOnlyWork() = runTest {
        val favoritedWork = savedWork("work-fav", title = "Favorited")
            .copy(isSaved = false, isFavorite = true, isQueuedForLater = false)
        database.workDao().upsert(favoritedWork.toEntity())
        val queue = repository.ensureSavedForLaterQueue()
        repository.addWork(queue.id, favoritedWork.id)

        repository.removeWork(queue.id, favoritedWork.id)

        val updated = database.workDao().getById(favoritedWork.id)!!.toDomain()
        assertFalse(updated.isQueuedForLater)
        assertTrue("favoriting also protects a queue-only work from deletion on removal", updated.isFavorite)
        assertFalse(updated.isDeleted)
    }

    @Test
    fun removeWorkOnlyClearsTheFlagWhileOtherQueueMembershipsRemain() = runTest {
        val work = savedWork("work-multi", title = "In two queues").copy(isSaved = false, isQueuedForLater = false)
        database.workDao().upsert(work.toEntity())
        val savedForLater = repository.ensureSavedForLaterQueue()
        val custom = repository.createQueue("Custom Queue")
        repository.addWork(savedForLater.id, work.id)
        repository.addWork(custom.id, work.id)

        repository.removeWork(savedForLater.id, work.id)
        val afterFirstRemoval = database.workDao().getById(work.id)!!.toDomain()
        assertTrue("still queued via the second membership", afterFirstRemoval.isQueuedForLater)
        assertFalse("not deleted while still in another queue", afterFirstRemoval.isDeleted)

        repository.removeWork(custom.id, work.id)
        val afterLastRemoval = database.workDao().getById(work.id)!!.toDomain()
        assertFalse(afterLastRemoval.isQueuedForLater)
        assertTrue("last queue membership dropped for a queue-only work -> soft-deleted", afterLastRemoval.isDeleted)
    }

    private fun savedWork(id: String, title: String): SavedWork {
        return SavedWork(
            id = id,
            title = title,
            author = if (id.endsWith("a")) "Author A" else if (id.endsWith("b")) "Author B" else "Author",
            dateAdded = fixedNow,
            isSaved = true
        )
    }
}
