package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import java.time.Instant
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    private var now = fixedNow

    @Before
    fun setUp() {
        now = fixedNow
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = ReadingQueueRepository(
            database = database,
            clock = { now },
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
    fun ensureSavedForLaterIsRaceSafeUnderConcurrentCallers() = runTest {
        // Regression test: LibraryViewModel's refresh() and refreshQueues() (plus this
        // repository's own add()/preserve() paths) can all call ensureSavedForLaterQueue()
        // around the same time. Before wrapping the check-then-create in a transaction,
        // concurrent callers could each pass the "does it exist" check before either had
        // committed its insert, producing two "Saved for Later" queues — reproduced on a
        // real device via a direct sqlite query on a fresh install.
        coroutineScope {
            (1..20).map {
                async(Dispatchers.IO) { repository.ensureSavedForLaterQueue() }
            }.awaitAll()
        }

        val savedForLaterQueues = repository.listQueues()
            .filter { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
        assertEquals(1, savedForLaterQueues.size)
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

    @Test
    fun updateQueueWritesColourTagsNotesAndStampsDateUpdated() = runTest {
        val queue = repository.createQueue("Night")
        now = fixedNow.plusSeconds(40)
        val turnedOn = repository.updateQueue(
            queue.id,
            QueueEdit(
                name = "Night watch",
                hue = 0.4424,
                colorHex = "#112233",
                keepsWorksOffline = false,
                notes = "After dark",
                tagNames = listOf("Comfort")
            )
        )
        val updated = repository.getQueue(queue.id)!!
        assertFalse(turnedOn)
        assertEquals("Night watch", updated.name)
        assertEquals(0.4424, updated.hue!!, 0.0)
        assertEquals("#112233", updated.colorHex)
        assertEquals(false, updated.keepsWorksOffline)
        assertEquals("After dark", updated.notes)
        assertEquals(now, updated.dateUpdated)
        assertEquals(listOf("Comfort"), repository.tagsForQueue(queue.id).map { it.name })
    }

    @Test
    fun updateQueueKeepsABlankNameAndANeverAskedOfflineFlag() = runTest {
        val queue = repository.createQueue("Plain")
        assertNull(queue.keepsWorksOffline)
        repository.updateQueue(
            queue.id,
            QueueEdit(name = "  ", hue = null, colorHex = null, keepsWorksOffline = true, tagNames = emptyList())
        )
        val updated = repository.getQueue(queue.id)!!
        assertEquals("Plain", updated.name)
        assertNull(updated.keepsWorksOffline)
    }

    @Test
    fun updateQueueReportsWhenKeepOfflineTurnsOn() = runTest {
        val queue = repository.createQueue("Loose", keepsWorksOffline = false)
        val turnedOn = repository.updateQueue(
            queue.id,
            QueueEdit(name = "Loose", hue = null, colorHex = null, keepsWorksOffline = true)
        )
        assertTrue(turnedOn)
        assertEquals(true, repository.getQueue(queue.id)!!.keepsWorksOffline)
    }

    @Test
    fun setQueuesPinnedStampsOnlyTheQueuesThatChange() = runTest {
        val first = repository.createQueue("One")
        val second = repository.createQueue("Two")
        now = fixedNow.plusSeconds(5)
        repository.setQueuesPinned(listOf(first.id, second.id), true)
        assertTrue(repository.getQueue(first.id)!!.isPinned)
        assertEquals(now, repository.getQueue(first.id)!!.dateUpdated)
        val pinnedAt = repository.getQueue(second.id)!!.dateUpdated
        now = fixedNow.plusSeconds(9)
        repository.setQueuesPinned(listOf(second.id), true)
        assertEquals(pinnedAt, repository.getQueue(second.id)!!.dateUpdated)
    }

    @Test
    fun replaceQueueTagsRemovesTheLinkAndKeepsTheTag() = runTest {
        val queue = repository.createQueue("Tagged", tagNames = listOf("Comfort", "Reread"))
        val comfort = repository.allTags().first { it.name == "Comfort" }
        now = fixedNow.plusSeconds(3)
        repository.replaceQueueTags(queue.id, listOf("comfort"))
        assertEquals(listOf("Comfort"), repository.tagsForQueue(queue.id).map { it.name })
        assertEquals(now, repository.getQueue(queue.id)!!.dateUpdated)
        assertEquals(comfort.id, repository.allTags().first { it.name.equals("Comfort", ignoreCase = true) }.id)
        assertTrue(repository.allTags().any { it.name == "Reread" })
    }

    @Test
    fun toggleSharedTagFillsTheQueuesThatLackIt() = runTest {
        val first = repository.createQueue("A", tagNames = listOf("Later"))
        val second = repository.createQueue("B")
        repository.toggleSharedTag(listOf(first.id, second.id), "Later")
        assertEquals(listOf("Later"), repository.tagsForQueue(second.id).map { it.name })
        repository.toggleSharedTag(listOf(first.id, second.id), "Later")
        assertTrue(repository.tagsForQueue(first.id).isEmpty())
        assertTrue(repository.tagsForQueue(second.id).isEmpty())
    }

    @Test
    fun reorderQueuesRewritesCustomSortOrder() = runTest {
        val first = repository.createQueue("First")
        val second = repository.createQueue("Second")
        now = fixedNow.plusSeconds(2)
        repository.reorderQueues(listOf(second.id, first.id))
        assertEquals(0, repository.getQueue(second.id)!!.sortOrder)
        assertEquals(1, repository.getQueue(first.id)!!.sortOrder)
        assertEquals(now, repository.getQueue(second.id)!!.dateUpdated)
    }

    @Test
    fun createQueueCopiesSavedForLaterWithoutRemovingThoseWorks() = runTest {
        val saved = repository.ensureSavedForLaterQueue()
        val work = savedWork("seed-work", "Seeded")
        database.workDao().upsert(work.toEntity())
        repository.addWork(saved.id, work.id)
        assertEquals(1, repository.savedForLaterSeedCount())
        val created = repository.createQueue("From saved", seedFromSavedForLater = true)
        assertEquals(listOf(work.id), repository.listWorks(created.id).map { it.work?.id })
        assertEquals(listOf(work.id), repository.listWorks(saved.id).map { it.work?.id })
    }

    @Test
    fun worksAvailableToAddSkipsMembersAndDeletedWorks() = runTest {
        val queue = repository.createQueue("Shelf")
        val inside = savedWork("inside", "Inside")
        val outside = savedWork("outside", "Outside")
        val gone = savedWork("gone", "Gone").copy(isDeleted = true)
        database.workDao().upsert(inside.toEntity())
        database.workDao().upsert(outside.toEntity())
        database.workDao().upsert(gone.toEntity())
        repository.addWork(queue.id, inside.id)
        assertEquals(listOf("outside"), repository.worksAvailableToAdd(queue.id).map { it.id })
    }

    @Test
    fun mergeAndStripStayInsideThisQueue() = runTest {
        val queue = repository.createQueue("Shelf", tagNames = listOf("Comfort", "Angst"))
        val other = repository.createQueue("Other", tagNames = listOf("Comfort"))
        val member = savedWork("member", "Member")
        val outsider = savedWork("outsider", "Outsider")
        database.workDao().upsert(member.toEntity())
        database.workDao().upsert(outsider.toEntity())
        repository.addWork(queue.id, member.id)
        val comfort = repository.allTags().first { it.name == "Comfort" }
        val angst = repository.allTags().first { it.name == "Angst" }
        database.tagDao().addToWork(WorkTagCrossRef(member.id, comfort.id))
        database.tagDao().addToWork(WorkTagCrossRef(outsider.id, comfort.id))
        assertEquals(1, repository.workTagCounts(queue.id)[comfort.id])
        assertEquals(angst.id, repository.tagRenameConflict(comfort.id, "angst")?.id)
        repository.mergeQueueTag(queue.id, comfort.id, angst.id)
        assertEquals(listOf("Angst"), repository.tagsForQueue(queue.id).map { it.name })
        assertEquals(listOf(angst.id), database.tagDao().getTagsForWork(member.id).map { it.id })
        assertEquals(listOf(comfort.id), database.tagDao().getTagsForWork(outsider.id).map { it.id })
        assertEquals(listOf("Comfort"), repository.tagsForQueue(other.id).map { it.name })
        repository.copyTagToQueue("Angst", other.id)
        assertEquals(listOf("Angst", "Comfort"), repository.tagsForQueue(other.id).map { it.name }.sorted())
        repository.stripQueueTag(queue.id, angst.id)
        assertTrue(repository.tagsForQueue(queue.id).isEmpty())
        assertTrue(database.tagDao().getTagsForWork(member.id).isEmpty())
        repository.renameUserTag(comfort.id, "Slow Burn")
        assertEquals("Slow Burn", repository.allTags().first { it.id == comfort.id }.name)
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
