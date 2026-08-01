package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
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
