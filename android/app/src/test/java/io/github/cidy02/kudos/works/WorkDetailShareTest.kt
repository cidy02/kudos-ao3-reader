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
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.app.ReaderLaunchRequest
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

    @Test fun rebuildAsksBeforeWritingAndShowsTheImporterFailure() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        val store = WorkFileStore(java.nio.file.Files.createTempDirectory("rebuild-dialog"))
        val repository = WorkRepository(database, store)
        val offline = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("A local rebuild must not request the network")
        }
        val importer = WorkImporter(repository, AO3WorkMetadataRepository(offline), AO3EpubDownloader(offline),
            store, context.cacheDir)
        val work = SavedWork(title = "An imported work", author = "A")
        var showing by mutableStateOf(true)
        var rebuilt = false
        try {
            runBlocking { repository.upsert(work) }
            compose.setContent {
                MaterialTheme {
                    if (showing) RebuildOriginalDialog(work, importer, onRebuilt = { rebuilt = true },
                        onDismiss = { showing = false })
                }
            }
            // The dialog is absent until LaunchedEffect's archived-original check returns from IO.
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Rebuild this work?").fetchSemanticsNodes().size == 1
            }
            compose.onNodeWithText("Rebuild this work?").assertExists()
            org.junit.Assert.assertFalse(rebuilt)
            compose.onNodeWithText("Rebuild").assertIsEnabled().performClick()
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Couldn't Rebuild").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("No archived original for this work.").assertExists()
            org.junit.Assert.assertFalse(rebuilt)
            compose.onNodeWithText("OK").performClick()
            compose.onNodeWithText("Couldn't Rebuild").assertDoesNotExist()
        } finally {
            compose.runOnIdle { showing = false }
            compose.waitForIdle()
            database.close()
        }
    }

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
                                onLogin = {}, onOpenComments = {}, onOpenReader = { true }
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

    @Test
    fun completedLocalOnlyWorkShowsCompleteInWorkDetailScreenIconStrip() {
        val work = SavedWork(
            title = "Completed local import",
            author = "Author",
            sourceUrl = "file:///import.epub",
            isComplete = true
        )
        assertLocalWorkCompletionOnRealWorkDetailScreen(work, expected = "Status: complete")
    }

    @Test
    fun unfinishedLocalOnlyWorkShowsUnknownCompletionInWorkDetailScreenIconStrip() {
        val work = SavedWork(
            title = "Unfinished local import",
            author = "Author",
            sourceUrl = "file:///draft.epub",
            isComplete = false
        )
        assertLocalWorkCompletionOnRealWorkDetailScreen(work, expected = "Status: unknown")
    }

    private fun assertLocalWorkCompletionOnRealWorkDetailScreen(work: SavedWork, expected: String) {
        withOfflineWorkDetailScreen(work = work, tempPrefix = "detail-completion") {
            compose.onNode(hasContentDescription(expected, substring = true)).assertExists()
        }
    }

    @Test
    fun readAloudDoesNotArmDuringRefreshAndDropsWhenPoppedBeforeNavigation() {
        val queryPool = java.util.concurrent.Executors.newSingleThreadExecutor()
        val gateQueries = java.util.concurrent.atomic.AtomicBoolean(false)
        val queriesAfterGate = java.util.concurrent.atomic.AtomicInteger(0)
        val enteredRefresh = java.util.concurrent.atomic.AtomicBoolean(false)
        val releaseRefresh = java.util.concurrent.CountDownLatch(1)
        val work = SavedWork(title = "Refresh Gate Work", author = "Author", hasEpub = true, isSaved = true)
        val owner = object : LifecycleOwner {
            override val lifecycle = LifecycleRegistry.createUnsafe(this).apply {
                currentState = Lifecycle.State.RESUMED
            }
        }
        val opened = mutableListOf<String>()
        try {
            withOfflineWorkDetailScreen(
                work = work,
                tempPrefix = "detail-launch-gate",
                writeDummyEpub = true,
                lifecycleOwner = owner,
                onOpenReader = { opened += it; true },
                configureDatabase = { builder ->
                    builder.setQueryExecutor { task ->
                        queryPool.execute {
                            if (gateQueries.get() && queriesAfterGate.incrementAndGet() >= 4 &&
                                enteredRefresh.compareAndSet(false, true)
                            ) {
                                releaseRefresh.await(5, java.util.concurrent.TimeUnit.SECONDS)
                            }
                            task.run()
                        }
                    }
                }
            ) {
                compose.onNodeWithContentDescription("Read Aloud").assertIsEnabled()
                compose.waitForIdle()

                gateQueries.set(true)
                compose.onNodeWithContentDescription("Read Aloud").performClick()
                compose.waitUntil(5_000) { enteredRefresh.get() }

                // Still inside refreshLocal: WorkDetailScreen must not have armed ReaderLaunchRequest yet.
                org.junit.Assert.assertNull(ReaderLaunchRequest.peek(work.id))

                // Simulate a popped NavBackStackEntry staying composed through its ~300 ms exit transition.
                compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.CREATED }
                releaseRefresh.countDown()
                compose.waitUntil(5_000) {
                    compose.onAllNodesWithContentDescription("Read Aloud")
                        .fetchSemanticsNodes()
                        .any { SemanticsProperties.Disabled !in it.config }
                }
                org.junit.Assert.assertNull(ReaderLaunchRequest.peek(work.id))
                org.junit.Assert.assertEquals(emptyList<String>(), opened)
            }
        } finally {
            releaseRefresh.countDown()
            queryPool.shutdownNow()
        }
    }

    @Test
    fun readAloudClearsArmedLaunchWhenOpenReaderReturnsFalse() {
        val work = SavedWork(title = "Pop Failed Work", author = "Author", hasEpub = true, isSaved = true)
        val opened = mutableListOf<String>()
        withOfflineWorkDetailScreen(
            work = work,
            tempPrefix = "detail-pop-false",
            writeDummyEpub = true,
            onOpenReader = { opened += it; false }
        ) {
            compose.onNodeWithContentDescription("Read Aloud").assertIsEnabled().performClick()
            compose.waitUntil(5_000) {
                opened == listOf(work.id) &&
                    compose.onAllNodesWithContentDescription("Read Aloud")
                        .fetchSemanticsNodes()
                        .any { SemanticsProperties.Disabled !in it.config }
            }
            org.junit.Assert.assertNull(ReaderLaunchRequest.peek(work.id))
        }
    }

    private fun withOfflineWorkDetailScreen(
        work: SavedWork,
        tempPrefix: String,
        writeDummyEpub: Boolean = false,
        lifecycleOwner: LifecycleOwner? = null,
        onOpenReader: (String) -> Boolean = { true },
        configureDatabase: (RoomDatabase.Builder<KudosDatabase>) -> RoomDatabase.Builder<KudosDatabase> = { it },
        block: () -> Unit
    ) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = configureDatabase(
            Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries()
        ).build()
        val store = WorkFileStore(java.nio.file.Files.createTempDirectory(tempPrefix).toFile().toPath())
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
        val importer = WorkImporter(
            repository, AO3WorkMetadataRepository(offline), AO3EpubDownloader(offline),
            store, context.cacheDir
        )
        val series = AO3SeriesRepository(offline)
        val chrome = PushedShellChrome()
        var showing by mutableStateOf(true)
        try {
            runBlocking {
                repository.upsert(work)
                if (writeDummyEpub) {
                    store.writeWorkEpub(work.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1, 2, 3))
                }
            }
            compose.setContent {
                MaterialTheme {
                    val hostOwner = lifecycleOwner ?: LocalLifecycleOwner.current
                    CompositionLocalProvider(
                        LocalPushedShellChrome provides chrome,
                        LocalLifecycleOwner provides hostOwner
                    ) {
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
                                onLogin = {},
                                onOpenComments = {},
                                onOpenReader = onOpenReader
                            )
                        }
                    }
                }
            }
            compose.waitUntil(timeoutMillis = 5_000) {
                compose.onAllNodesWithText(work.title).fetchSemanticsNodes().isNotEmpty()
            }
            block()
        } finally {
            ReaderLaunchRequest.consume(work.id)
            compose.runOnIdle { showing = false }
            compose.waitForIdle()
            database.close()
        }
    }
}
