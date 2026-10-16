package io.github.cidy02.kudos.ui.components

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.*
import java.nio.file.Files
import kotlinx.coroutines.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1800dp")
class RemoteWorkActionsTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var queues: ReadingQueueRepository
    private lateinit var importer: WorkImporter
    private lateinit var downloads: DownloadQueue
    private lateinit var settings: SettingsRepository
    private lateinit var store: WorkFileStore
    private val directory = Files.createTempDirectory("remote-work-actions")
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val downloadScope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private val gate = PrivacyGate()
    private val opened = mutableListOf<String>()
    private var requests = 0
    private var selectionTaps = 0
    private val remote = AO3WorkSummary(id = 123, title = "Remote title", authors = listOf("A"),
        fandoms = emptyList(), rating = "Explicit", warnings = emptyList(), categories = emptyList())

    @Before fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        store = WorkFileStore(directory.resolve("files"))
        works = WorkRepository(database, store)
        queues = ReadingQueueRepository(database)
        settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
            produceFile = { directory.resolve("settings.preferences_pb").toFile() }))
        settings.updateHideMatureContent(false)
        val fake = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
                error("A listing action must not enrich metadata")
            override suspend fun getBytes(url: String, headers: Map<String, String>): AO3Result<AO3BinaryResponse> {
                requests++
                return AO3Result.Failure(AO3Error.NotFound)
            }
        }
        importer = WorkImporter(works, AO3WorkMetadataRepository(fake), AO3EpubDownloader(fake), store, context.cacheDir)
        downloads = DownloadQueue(importer, works, scope = downloadScope)
    }

    @After fun tearDown() {
        // Writes started from the UI finish before the database closes under them.
        compose.waitForIdle()
        settingsScope.cancel(); downloadScope.cancel(); database.close()
        directory.toFile().deleteRecursively()
    }

    private fun show(selection: RemoteWorkSelectionState? = null, matureMenu: Boolean = false, selectingRow: Boolean = false) {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ProvideWorkRowActions(works, queues, downloads, importer, settings, gate,
                    openDetails = {}, openReader = { opened += it }, openComments = {}) {
                    Column {
                        SensitiveWorkRow(work = remote, onOpenWork = { selectionTaps++ }, selecting = selectingRow)
                        if (matureMenu) MatureWorkMenuItem {}
                        if (selection != null) RemoteWorkSelectionActions(selection, listOf(remote), importer, queues)
                    }
                }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(10_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test fun matchedBlurredRowRevealsBeforeReadingAndUsesItsLocalIdentity() {
        val local = runBlocking {
            settings.updateHideMatureContent(true)
            settings.updateMatureContentMode(MatureContentMode.Obscure)
            works.upsert(SavedWork(id = "1c000000-0000-4000-8000-000000000001", title = "Local title", author = "A",
                rating = "Explicit", sourceUrl = remote.workUrl, hasEpub = true))
                .also { store.writeWorkEpub(it.id, byteArrayOf(0x50, 0x4B, 0x03, 0x04, 1)) }
        }
        show()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithContentDescription("Hidden mature work. Activate to reveal.").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Remote title").assertDoesNotExist()
        compose.onNodeWithText("Local title").assertDoesNotExist()
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").performClick()
        awaitText("Local title")
        assertTrue(opened.isEmpty())
        compose.onNodeWithText("Local title").performClick()
        compose.waitUntil(10_000) { opened.isNotEmpty() }
        assertEquals(listOf(local.id), opened)
        assertEquals(0, requests)
    }

    @Test fun hideModeLeavesTheRemoteListingUnmatched() {
        runBlocking {
            settings.updateHideMatureContent(true)
            settings.updateMatureContentMode(MatureContentMode.Hide)
            works.upsert(SavedWork(title = "Local title", author = "A", rating = "Explicit",
                sourceUrl = remote.workUrl, hasEpub = false))
        }
        show()
        awaitText("Remote title")
        compose.onNodeWithText("Local title").assertDoesNotExist()
        assertEquals(0, requests)
    }

    @Test fun selectingAMatchedRemoteCardTogglesSelectionInsteadOfOpeningTheReader() {
        runBlocking {
            works.upsert(SavedWork(title = "Local title", author = "A", sourceUrl = remote.workUrl, hasEpub = false))
        }
        show(selectingRow = true)
        awaitText("Remote title")
        compose.onNodeWithText("Remote title").performClick()
        assertEquals(1, selectionTaps)
        assertTrue(opened.isEmpty())
        assertEquals(0, requests)
    }

    @Test fun remoteQueueMenuSurvivesCreatingTheLocalRecordAndUsesTheSharedPicker() {
        show()
        awaitText("Remote title")
        compose.onNodeWithText("Remote title").performTouchInput { longClick() }
        compose.onNodeWithText("Read").assertExists()
        compose.onNodeWithText("Comments").assertExists()
        compose.onNodeWithText("Add to Collection").assertExists()
        compose.onNodeWithText("Add to Queue").performClick()
        awaitText("New queue")
        compose.onNode(hasSetTextAction()).performTextInput("My queue")
        compose.onNodeWithText("Add").performClick()
        awaitText("My queue")
        val created = runBlocking { queues.listQueues().single { it.displayName == "My queue" } }
        compose.waitUntil(10_000) { runBlocking { queues.listWorks(created.id).size == 1 } }
        // Selecting it again removes membership and keeps the work.
        compose.onNodeWithText("My queue").performClick()
        compose.waitUntil(10_000) { runBlocking { queues.listWorks(created.id).isEmpty() } }
        assertEquals(0, requests)
    }

    @Test fun failedBulkDownloadShowsItsFailureAndRetainsSelection() {
        val selection = RemoteWorkSelectionState().apply { enter(remote.id) }
        show(selection)
        compose.onNodeWithText("Actions").performClick()
        compose.onNodeWithText("Download").performClick()
        awaitText("Action Failed")
        assertTrue(selection.isSelecting)
        assertEquals(setOf(remote.id), selection.selected)
        assertEquals(1, requests)
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithText("Action Failed").assertDoesNotExist()
    }

    // The bulk collection picker staying open after the selection ends is checked on the
    // emulator, not here: `AddSelectionToCollectionDialog` never settles under Robolectric's
    // idling (the test hung and the run ran out of memory), though it runs on a device.

    @Test fun matureMenuUsesTheSharedSessionGateInBothDirections() {
        runBlocking { settings.updateHideMatureContent(true) }
        show(matureMenu = true)
        awaitText("Show mature")
        compose.onNodeWithText("Show mature").performClick()
        awaitText("Hide mature")
        assertTrue(gate.state.value.revealAll)
        compose.onNodeWithText("Hide mature").performClick()
        awaitText("Show mature")
        assertFalse(gate.state.value.revealAll)
        assertEquals(0, requests)
    }
}
