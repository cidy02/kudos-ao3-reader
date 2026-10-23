package io.github.cidy02.kudos.works

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Paths
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WorkDetailSaveForLaterTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val folder = TemporaryFolder()
    private lateinit var database: KudosDatabase
    private lateinit var queues: ReadingQueueRepository
    private lateinit var works: WorkRepository
    private lateinit var anchor: SavedWork
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val reads = CopyOnWriteArrayList<String>()
    private val chrome = PushedShellChrome()
    @Volatile private var dismissed = false
    private fun fixture(name: String) = listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures",
        "android/app/src/debug/assets/fixtures").map { File(it, "$name.html") }.first { it.isFile }.readText()

    private fun open(enabled: Boolean, threshold: Int, seriesId: Int = 999, fail: Boolean = false, hasSeries: Boolean = true, sourceLess: Boolean = false, queueOnly: Boolean = false) = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        val files = WorkFileStore(Paths.get(folder.root.absolutePath, "works"))
        works = WorkRepository(database, files)
        queues = ReadingQueueRepository(database, epubOnDisk = files::workEpubExists,
            enqueueDownloads = { throw AssertionError("Series used background queue") })
        val html = fixture(if (seriesId == 999) "ao3_demo_series" else "ao3_demo_series_two_pages_1")
        val parsed = AO3SearchParser().parseSearchPage(html, 1)
        // Held copies let auto-preservation complete without any real timer or EPUB request.
        for (summary in parsed.works) {
            val work = works.upsert(SavedWork(title = summary.title, author = summary.authorText,
                sourceUrl = if (sourceLess) "" else summary.workUrl, hasEpub = true, isSaved = !queueOnly,
                dateAdded = java.time.Instant.ofEpochMilli(1000),
                epubPreservationStatusRaw = "preserved", seriesUrl = if (hasSeries) "https://archiveofourown.org/series/$seriesId" else ""))
            files.writeWorkEpub(work.id, EpubBuilder.buildEpub(work.title, "<p>Original local chapter.</p>"))
            if (summary == parsed.works.first()) anchor = work
        }
        if (queueOnly) queues.addToSavedForLater(anchor.id, enqueueMissingEpub = false)
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                reads += url
                return if (fail) AO3Result.Failure(AO3Error.Forbidden)
                else AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
            }
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                throw AssertionError("Read an already held EPUB: $url")
            }
        }
        val auth = object : AO3AuthenticatedClient {
            override fun username(): String? = null
            override suspend fun getAuthenticated(url: String) = AO3Result.Failure(AO3Error.AuthenticationRequired)
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                throw AssertionError("Save for Later wrote to AO3")
        }
        val series = AO3SeriesRepository(client)
        val importer = WorkImporter(works, AO3WorkMetadataRepository(client), AO3EpubDownloader(client), files, context.cacheDir)
        val downloads = DownloadQueue(importer, works, series, scope)
        val store = PreferenceDataStoreFactory.create(scope = storeScope, produceFile = { File(folder.root, "settings.preferences_pb") })
        val settings = SettingsRepository(store)
        settings.updateAutoPreserveSmallSeries(enabled)
        settings.updateAutoPreserveSeriesThreshold(threshold)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WorkDetailScreen(WorkDetailSource.LocalWork(anchor.id), works, importer, downloads,
                            AO3WriteRepository(auth), queues, settingsRepository = settings, seriesRepository = series,
                            onLogin = { throw AssertionError("Opened login") }, onOpenComments = {}, onOpenReader = {},
                            onDismiss = { dismissed = true })
                    }
                }
            }
        }
    }
    private fun save() {
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        assertTrue(reads.isEmpty()) // opening Detail alone never checks or preserves a series
        compose.onNodeWithContentDescription("More actions").performClick()
        compose.onNodeWithText("Save for Later").performClick()
    }
    private fun await(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun members() = runBlocking { queues.listWorks(queues.ensureSavedForLaterQueue().id) }
    @After fun close() { scope.cancel(); storeScope.cancel(); if (::database.isInitialized) database.close() }

    @Test fun aCheckedQueueInWorkDetailCanBeUnchecked() {
        open(false, 25, hasSeries = false)
        val queue = runBlocking { queues.createQueue("Parity queue").also { queues.addWork(it.id, anchor.id, enqueueMissingEpub = false) } }
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("More actions").performClick()
        compose.onNode(hasText("Add to Queue") or hasText("In 1 Queue")).performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Parity queue").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Parity queue").performClick()
        compose.waitUntil(5_000) { runBlocking { queues.listWorks(queue.id).isEmpty() } }
        assertNotNull(runBlocking { works.getWork(anchor.id) })
    }

    @Test fun removingSourceLessDetailDismissesAfterSoftDeletion() {
        open(false, 25, hasSeries = false, sourceLess = true)
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("More actions").performClick()
        compose.onNodeWithText("Remove from Library").performClick()
        // The default setting asks for confirmation before a destructive library action.
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Remove").fetchSemanticsNodes().isNotEmpty() || dismissed }
        if (!dismissed) compose.onNodeWithText("Remove").performClick()
        compose.waitUntil(15_000) { dismissed }
        assertTrue(runBlocking { works.getWork(anchor.id)!!.isDeleted })
        assertTrue(reads.isEmpty())
    }

    @Test fun removingSourceLessQueueOnlyWorkFromLaterDismisses() {
        open(false, 25, hasSeries = false, sourceLess = true, queueOnly = true)
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("More actions").performClick()
        compose.onNodeWithText("Remove from Later").performClick()
        compose.waitUntil(15_000) { dismissed }
        assertTrue(runBlocking { works.getWork(anchor.id)!!.isDeleted })
        assertTrue(reads.isEmpty())
    }

    @Test fun removingAO3QueueOnlyWorkFromLaterKeepsItsRemoteSummary() {
        open(false, 25, hasSeries = false, queueOnly = true)
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("More actions").performClick()
        compose.onNodeWithText("Remove from Later").performClick()
        await("Removed from Saved for Later.")
        assertFalse(dismissed)
        assertTrue(runBlocking { works.getWork(anchor.id)!!.isDeleted })
        compose.onAllNodesWithText(anchor.title).fetchSemanticsNodes().let { assertTrue(it.isNotEmpty()) }
        assertTrue(reads.isEmpty())
    }

    @Test fun noSeriesDoesNotPromptOrMakeASeriesRead() {
        open(true, 25, hasSeries = false); save(); await("Saved for Later.")
        compose.onNodeWithText("Preserve Series?").assertDoesNotExist()
        assertEquals(listOf(anchor.id), members().map { it.work!!.id })
        assertTrue(reads.isEmpty())
    }

    @Test fun existingLocalDetailRevivesBeforeSavingForLater() {
        open(true, 25, hasSeries = false)
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("More actions").fetchSemanticsNodes().isNotEmpty() }
        // The view is still bound to the old live snapshot while another action deletes it.
        runBlocking { works.softDelete(anchor.id) }
        save()
        await("Saved for Later.")
        val revived = runBlocking { works.getWork(anchor.id)!! }
        assertFalse(revived.isDeleted)
        assertNull(revived.deletedAt)
        assertNull(revived.permanentDeletionScheduledAt)
        assertEquals(listOf(anchor.id), members().map { it.work!!.id })
        assertTrue(runBlocking { database.syncTombstoneDao().getByRecord(anchor.id, "savedWork").isEmpty() })
        assertTrue(reads.isEmpty())
    }
    @Test fun settingOffPromptsAndOnlyThisWorkKeepsJustTheAnchor() {
        open(false, 4); save(); await("Preserve Series?")
        compose.onNodeWithTag("Work detail form").performScrollToNode(hasText("Only This Work"))
        compose.onNodeWithText("Only This Work").performClick()
        compose.waitForIdle()
        assertEquals(listOf(anchor.id), members().map { it.work!!.id })
        assertEquals(1, reads.size)
    }
    @Test fun settingOnAtThresholdUsesPreviewAndPreservesWithoutPrompt() {
        open(true, 4); save(); await("Series preservation complete: 4 already preserved.")
        compose.onNodeWithText("Preserve Series?").assertDoesNotExist()
        assertEquals(4, members().size)
        assertEquals(listOf("https://archiveofourown.org/series/999"), reads.toList())
    }
    @Test fun settingOnUnderThresholdUsesPreviewAndPreservesWithoutPrompt() {
        open(true, 6); save(); await("Series preservation complete: 4 already preserved.")
        assertEquals(4, members().size)
        assertEquals(1, reads.size)
    }
    @Test fun overSavedThresholdPromptsEvenThoughItIsBelowFive() {
        open(true, 3); save(); await("Preserve Series?")
        compose.onNodeWithTag("Work detail form").performScrollToNode(hasText("Always auto-preserve series under 3 works"))
        compose.onNodeWithText("Always auto-preserve series under 3 works").assertExists()
        assertEquals(1, members().size)
        assertEquals(1, reads.size)
    }
    @Test fun multiplePagesNeverAutoPreserveOrReadTheSecondPage() {
        open(true, 25, seriesId = 1000); save(); await("Preserve Series?")
        assertEquals(1, members().size)
        assertEquals(listOf("https://archiveofourown.org/series/1000"), reads.toList())
    }
    @Test fun failedPreviewPromptsAndRetainsTheAnchorWithOneAttempt() {
        open(true, 25, fail = true); save(); await("Preserve Series?")
        compose.onNodeWithTag("Work detail form").performScrollToNode(hasText("Kudos couldn't check how many works are in this series. Continuing may download many works. Kudos adds them one at a time."))
        assertEquals(listOf(anchor.id), members().map { it.work!!.id })
        assertEquals(1, reads.size)
    }
}
