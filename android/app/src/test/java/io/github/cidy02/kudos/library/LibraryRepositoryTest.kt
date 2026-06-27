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
    fun snapshotIncludesSavedWorksUserTagsAndCollections() = runTest {
        workRepository.upsert(savedWork("saved").copy(isSaved = true))
        workRepository.upsert(savedWork("history").copy(isSaved = false))
        workRepository.addUserTag("saved", "Comfort")
        workRepository.addToCollection("saved", "Weekend")

        val snapshot = libraryRepository.observeSnapshot().first()

        assertEquals(listOf("saved"), snapshot.items.map { it.work.id })
        assertEquals(listOf("Comfort"), snapshot.items.single().userTags.map { it.normalizedName })
        assertEquals(listOf("Weekend"), snapshot.items.single().collections.map { it.name })
        assertEquals(listOf("Comfort"), snapshot.userTags.map { it.normalizedName })
        assertEquals(listOf("Weekend"), snapshot.collections.map { it.name })
    }

    private fun savedWork(id: String): SavedWork {
        return SavedWork(
            id = id,
            title = "Work $id",
            author = "Author",
            dateAdded = Instant.parse("2026-06-26T12:00:00Z")
        )
    }
}
