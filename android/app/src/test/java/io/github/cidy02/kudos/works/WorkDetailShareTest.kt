package io.github.cidy02.kudos.works

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
class WorkDetailShareTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun linklessImportStillHasNeitherShareNorOriginalViewerOnTheActualWorkPage() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        val store = WorkFileStore(context.filesDir.toPath())
        val work = SavedWork(title = "Linkless import", author = "Author")
        // No network implementation exists in this test. Any accidental request fails it.
        val offline = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("Unexpected network request: $url")
        }
        val writes = object : AO3AuthenticatedClient {
            override fun username(): String? = null
            override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
                error("Unexpected authenticated request: $url")
            override suspend fun postAuthenticated(
                url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
            ): AO3Result<AO3HttpResponse> = error("Unexpected write: $url")
        }
        val repository = WorkRepository(database, store)
        val importer = WorkImporter(repository, AO3WorkMetadataRepository(offline), AO3EpubDownloader(offline),
            store, context.cacheDir)
        val series = AO3SeriesRepository(offline)
        val chrome = PushedShellChrome()
        var showing by mutableStateOf(true)
        try {
            runBlocking {
                repository.upsert(work)
                store.writeWorkEpub(work.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04))
                store.writeOriginal(work.id, "pdf", "Original contents".toByteArray())
            }
            compose.setContent {
                MaterialTheme {
                    CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                        if (showing) Column {
                            Row { chrome.trailingContent?.invoke(this) }
                            WorkDetailScreen(
                                source = WorkDetailSource.LocalWork(work.id),
                                workRepository = repository,
                                workImporter = importer,
                                downloadQueue = DownloadQueue(importer, repository, series),
                                writeRepository = AO3WriteRepository(writes),
                                readingQueueRepository = ReadingQueueRepository(database),
                                seriesRepository = series,
                                onLogin = {}, onOpenComments = {}, onOpenReader = {}
                            )
                        }
                    }
                }
            }
            compose.waitUntil(timeoutMillis = 5_000) {
                compose.onAllNodesWithText(work.title).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("More actions").performClick()
            compose.onNodeWithText("Add to Queue").assertExists()
            compose.onNodeWithText("Share").assertDoesNotExist()
            compose.onNodeWithContentDescription("View the original file this work was converted from")
                .assertDoesNotExist()
            compose.onNodeWithText("Original").assertDoesNotExist()
            compose.onNodeWithText("Open on AO3").assertDoesNotExist()
        } finally {
            // Dispose the screen's effects before its database is closed.
            compose.runOnIdle { showing = false }
            compose.waitForIdle()
            database.close()
            runBlocking {
                store.deleteWorkEpub(work.id)
                store.deleteOriginal(work.id)
            }
        }
    }
}
