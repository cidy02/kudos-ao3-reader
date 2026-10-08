package io.github.cidy02.kudos.reader

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderCompletionTest {
    @Test
    fun navigatorEndFinishesEvenOnLandingBackgroundDoesNotHoldAndCloseDoes() = runBlocking {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java
        ).allowMainThreadQueries().build()
        val directory = Files.createTempDirectory("kudos-reader-completion-test").toFile()
        var model: ReaderViewModel? = null
        try {
            val files = WorkFileStore(directory.toPath())
            val works = WorkRepository(database, files)
            val work = works.upsert(SavedWork(
                title = "Long completed work", author = "Author", hasEpub = true, isComplete = true,
                sourceUrl = "https://archiveofourown.org/works/123", wordCount = 500000
            ))
            // Same local file-presence setup as ReaderRepositoryTest; never opens Readium or a URL.
            files.writeWorkEpub(work.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
            var now = Instant.parse("2026-10-08T12:00:00Z")
            val store = object : DataStore<Preferences> {
                override val data = MutableStateFlow(emptyPreferences())
                override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
                    transform(data.value).also { data.value = it }
            }
            val reader = ReaderViewModel(
                ReaderRepository(works, files, settingsProvider = { KudosSettings.Defaults }, clock = { now }),
                ReadingLogService(database.readingLogDao()), SettingsRepository(store),
                AnnotationRepository(database.annotationDao(), database.syncTombstoneDao()), work.id
            )
            model = reader
            withTimeout(5_000) { reader.state.filterIsInstance<ReaderUiState.Reading>().first() }
            reader.setSpineCount(10)
            val landing = ReaderProgress(9, 0.97, totalProgression = 0.985)
            reader.onProgress(landing)
            reader.onViewport(ReaderViewport(9, 99, 100))
            assertFalse(works.getWork(work.id)!!.isFinished)
            reader.onViewport(ReaderViewport(9, 100, 100))
            withTimeout(5_000) { reader.state.filterIsInstance<ReaderUiState.Reading>().first { it.finished } }
            assertNull(works.getWork(work.id)!!.freedAt)
            assertEquals(0.97, works.getWork(work.id)!!.lastScrollFraction, 0.0)
            now = now.plusSeconds(30)
            reader.pauseReadingSession()
            val paused = withTimeout(5_000) {
                works.observeLibraryWorks().first { items -> items.any { it.id == work.id && it.lastReadDate == now } }
                    .first { it.id == work.id }
            }
            assertNull(paused.freedAt)
            now = now.plusSeconds(30)
            reader.close()
            val held = withTimeout(5_000) {
                works.observeLibraryWorks().first { items -> items.any { it.id == work.id && it.freedAt != null } }
                    .first { it.id == work.id }
            }
            assertTrue(held.isFinished)
            assertEquals(now, held.freedAt)
            assertTrue(files.workEpubExists(work.id))
        } finally {
            model?.viewModelScope?.coroutineContext?.get(Job)?.cancelAndJoin()
            database.close()
            directory.deleteRecursively()
            Dispatchers.resetMain()
        }
    }
}
