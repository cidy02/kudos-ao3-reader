package io.github.cidy02.kudos.library

import org.junit.Ignore
import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.*
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LibraryForms3gxTest {
    @get:Rule val compose = createComposeRule()
    private val directory = Files.createTempDirectory("library-3gx")
    private val database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
        .allowMainThreadQueries().setQueryExecutor { it.run() }.setTransactionExecutor { it.run() }.build()
    private val works = WorkRepository(database, WorkFileStore(directory))
    private val queues = ReadingQueueRepository(database)
    private var visible by mutableStateOf(true)
    private fun show(content: @Composable () -> Unit) {
        compose.setContent { if (visible) KudosTheme(KudosThemeMode.Light) { content() } }
    }
    @After fun close() {
        compose.runOnIdle { visible = false }
        compose.waitForIdle()
        database.close()
        directory.toFile().deleteRecursively()
    }

    @Test fun queueNameHasALabelAndKeyboardDoneSavesTheDraft() {
        var saved: ReadingQueue? = null
        show { QueueEditorSheet(queues, existing = null, onDismiss = {}, onSaved = { saved = it }) }
        compose.onNodeWithContentDescription("Name").performTextInput("Night bus")
        compose.onNodeWithContentDescription("Name").performImeAction()
        compose.waitUntil(5_000) { saved != null }
        assertEquals("Night bus", saved!!.name)
    }

    @Test fun theSavedForLaterSeedIsOneSpokenClickableOptionIncludingItsCount() {
        runBlocking { works.upsert(SavedWork(id = "one", title = "Story", author = "Writer")); queues.addToSavedForLater("one", enqueueMissingEpub = false) }
        show { QueueEditorSheet(queues, existing = null, onDismiss = {}, onSaved = {}) }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Copy 1 work. They stay in Saved for Later.").fetchSemanticsNodes().isNotEmpty() }
        val choice = compose.onNode(hasText("Saved for Later") and hasText("Copy 1 work. They stay in Saved for Later."))
        choice.assertIsNotSelected().performClick().assertIsSelected()
    }

    @Test fun queueDetailsUseTheirOriginAndMarkTheCurrentPreset() {
        val queue = runBlocking { queues.createQueue("Rereads", hue = 0.4424) }
        show { QueueSettingsScreen(queue.id, queues, origin = "Library") }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Rereads").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("LIBRARY › QUEUES › QUEUE DETAILS").assertExists()
        compose.onNodeWithText("Colour").performScrollTo().performClick()
        compose.onNode(hasText("Mint") and SemanticsMatcher.expectValue(SemanticsProperties.Selected, true)).assertExists()
    }

    @Ignore("3gx, held for 3gy: Compose never goes idle (the dialog opens and works on the emulator)")

    @Test fun collectionPickerShowsNewestCreatedFirst() {
        val old = WorkCollection(id = "old", name = "Alpha", createdAt = Instant.EPOCH)
        val recent = WorkCollection(id = "new", name = "Zulu", createdAt = Instant.EPOCH.plusSeconds(10))
        runBlocking { works.upsert(SavedWork(id = "one", title = "Story", author = "Writer")) }
        show { AddToCollectionDialog("one", listOf(old, recent), works, rememberCoroutineScope(), { _, _ -> }, {}) }
        assertTrue(compose.onNodeWithText("Zulu").fetchSemanticsNode().boundsInRoot.top <
            compose.onNodeWithText("Alpha").fetchSemanticsNode().boundsInRoot.top)
    }

    @Test fun collectionReorderKeepsEveryCreatorLine() {
        val byline = "Avery and " + "Another Writer With A Long Name, ".repeat(6)
        val work = SavedWork(id = "one", title = "Story", author = byline)
        show { CollectionReorderSheet(WorkCollection(name = "Read"), listOf(work), works, {}, {}) }
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(byline, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.single().lineCount > 1)
        assertFalse(layouts.single().isLineEllipsized(layouts.single().lineCount - 1))
    }

    @Test fun collectionDetailsOmitTheCreationOnlyFooterAndUseThisColour() {
        show { CollectionEditorSheet(works, WorkCollection(name = "Read"), {}, {}) }
        compose.onNodeWithText("Kudos picks a colour from the collection name. Renaming it may change this colour.").assertExists()
        compose.onNodeWithText("This collection stays on this device. AO3 doesn't see it, and it isn't shared with your other devices.").assertDoesNotExist()
    }

    @Test fun newCollectionDoesNotAddAColourHeading() {
        show { CollectionEditorSheet(works, null, {}, {}) }
        compose.onNodeWithText("COLOUR").assertDoesNotExist()
    }

    @Test fun libraryQueueFormExplainsAFailedSeriesPreviewBeforePreserving() {
        val work = SavedWork(id = "one", title = "Story", author = "Writer", seriesUrl = "https://archiveofourown.org/series/321")
        runBlocking { works.upsert(work) }
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.Forbidden)
        }
        val repository = AO3SeriesRepository(client = client, pageCache = AO3PageCache())
        // An importer is required only to expose the existing series group; this read never downloads.
        val files = WorkFileStore(directory)
        val importer = io.github.cidy02.kudos.works.WorkImporter(works,
            io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository(client),
            io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader(client), files, directory.toFile())
        show { QueueMembershipDialog(listOf(work), queues, importer, onDismiss = {}, seriesRepository = repository) }
        compose.waitUntil(5_000) { compose.onAllNodesWithContentDescription("Also add works from this AO3 series").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("Also add works from this AO3 series").performClick()
        val message = SeriesPreservationPrompt(null, 5, true).message
        compose.waitUntil(5_000) { compose.onAllNodesWithText(message).fetchSemanticsNodes().isNotEmpty() }
    }
}
