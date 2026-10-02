package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryRepositoryAllWorksTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private lateinit var libraryRepository: LibraryRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        workRepository = WorkRepository(
            database = database,
            fileStore = WorkFileStore(Files.createTempDirectory("kudos-library-tests"))
        )
        libraryRepository = LibraryRepository(workRepository)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun statisticsCountWorksThatWereReadThenUnsaved() = runTest {
        // iOS computes Reading Insights over every non-deleted work; Android was
        // computing them over saved works only, so un-saving something you had read
        // silently changed all nine statistics. The Library shelves must NOT change.
        workRepository.upsert(savedWork("saved").copy(isSaved = true))
        workRepository.upsert(savedWork("history").copy(isSaved = false))

        val statistics = libraryRepository.observeStatisticsWorks().first()
        val shelves = libraryRepository.observeSavedWorks().first()

        assertEquals(listOf("history", "saved"), statistics.map { it.id }.sorted())
        assertEquals(listOf("saved"), shelves.map { it.id })
    }

    @Test
    fun statisticsStillExcludeQueueOnlyWorks() = runTest {
        workRepository.upsert(savedWork("saved").copy(isSaved = true))
        workRepository.upsert(
            savedWork("queued").copy(isSaved = false, isQueuedForLater = true)
        )

        val statistics = libraryRepository.observeStatisticsWorks().first()

        assertEquals(listOf("saved"), statistics.map { it.id })
    }

    @Test
    fun snapshotIncludesSavedWorksUserTagsAndCollections() = runTest {
        // Work / collection ids are UUIDs in production; membership tombstone ids
        // XOR those UUIDs, so tests that join collections must use real UUIDs too.
        val savedId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        val historyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        workRepository.upsert(savedWork(savedId).copy(isSaved = true))
        workRepository.upsert(savedWork(historyId).copy(isSaved = false))
        workRepository.addUserTag(savedId, "Comfort")
        workRepository.addToCollection(savedId, "Weekend")

        val snapshot = libraryRepository.observeSnapshot().first()

        // iOS LibraryView queries every non-deleted work (`!$0.isPendingDeletion`) and
        // each shelf filters it, so an unsaved work you read is in the snapshot too.
        assertEquals(setOf(savedId, historyId), snapshot.items.map { it.work.id }.toSet())
        val saved = snapshot.items.single { it.work.id == savedId }
        assertEquals(listOf("Comfort"), saved.userTags.map { it.normalizedName })
        assertEquals(listOf("Weekend"), saved.collections.map { it.name })
        assertEquals(listOf("Comfort"), snapshot.userTags.map { it.normalizedName })
        assertEquals(listOf("Weekend"), snapshot.collections.map { it.name })
    }

    private fun savedWork(id: String): SavedWork {
        return SavedWork(
            id = id,
            title = "Work $id",
            author = "Author",
            // T-344: no AO3 id means an imported, always-protected download on iOS;
            // these fixtures model AO3 works (Models/Models.swift:469-480).
            sourceUrl = "https://archiveofourown.org/works/123",
            dateAdded = Instant.parse("2026-06-26T12:00:00Z")
        )
    }
}
