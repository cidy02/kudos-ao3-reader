package io.github.cidy02.kudos.library

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.InspectableValue
import androidx.compose.ui.platform.isDebugInspectorInfoEnabled
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.components.AddSelectionToCollectionDialog
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
class ActionParityFormsTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private lateinit var queues: ReadingQueueRepository
    private val directory = Files.createTempDirectory("kudos-actions")
    private val first = SavedWork(id = "1f000000-0000-4000-8000-000000000001", title = "First work", author = "Anonymous",
        sourceUrl = "https://archiveofourown.org/works/555", isSaved = true)
    private val second = first.copy(id = "2f000000-0000-4000-8000-000000000002", title = "Second work",
        sourceUrl = "https://archiveofourown.org/works/556")

    @Before fun setUp(): Unit = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        works = WorkRepository(database, WorkFileStore(directory))
        queues = ReadingQueueRepository(database)
        works.upsert(first); works.upsert(second)
    }
    @After fun tearDown() { database.close(); directory.toFile().deleteRecursively() }
    private fun show(content: @Composable () -> Unit) {
        val chrome = PushedShellChrome()
        compose.setContent { KudosTheme(themeMode = io.github.cidy02.kudos.ui.theme.KudosThemeMode.Light) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                Column { Row { chrome.trailingContent?.invoke(this) }; content() }
            }
        } }
    }
    private fun await(predicate: suspend () -> Boolean) {
        compose.waitUntil(15_000) { runBlocking { predicate() } }
        compose.waitForIdle()
    }

    @Test fun queuePickerTogglesAllMembersAndCreatesWithoutClosing() {
        val queue = runBlocking { queues.createQueue("To read", keepsWorksOffline = false).also { queues.addWork(it.id, first.id) } }
        var closed = false
        show { QueueMembershipDialog(listOf(first, second), queues, onDismiss = { closed = true }) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("To read").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("To read").performClick()
        await { queues.listWorks(queue.id).size == 2 }
        compose.onNodeWithText("To read").performClick()
        await { queues.listWorks(queue.id).isEmpty() }
        // The form is busy (its field disabled) until the membership change settles.
        compose.waitUntil(15_000) { compose.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasSetTextAction()).performTextInput("Another queue")
        compose.onNodeWithText("Add", useUnmergedTree = true).performClick()
        await { queues.listQueues().any { it.name == "Another queue" && queues.listWorks(it.id).size == 2 } }
        assertFalse(closed)
        runBlocking { assertFalse(works.getWork(first.id)!!.isDeleted); assertTrue(works.getWork(first.id)!!.hasEpub) }
    }

    /**
     * A62 F16. The picker's checks are the memberships every selected work has (a tap then adds
     * to all or removes from all). The dialog itself never settles under Robolectric's idling
     * here, though it runs and toggles on the emulator (2026-10-16), so its rule is tested here.
     */
    @Test fun collectionPickerChecksOnlyTheMembershipsEverySelectedWorkHas() {
        assertEquals(setOf("shelf"), io.github.cidy02.kudos.ui.components.sharedMemberships(
            listOf(setOf("shelf", "later"), setOf("shelf"))))
        assertEquals(emptySet<String>(), io.github.cidy02.kudos.ui.components.sharedMemberships(
            listOf(setOf("shelf"), emptySet())))
        assertEquals(emptySet<String>(), io.github.cidy02.kudos.ui.components.sharedMemberships(emptyList()))
    }

    @Test fun scopedLaterRemovalUsesSystemQueueMembershipAndRetainsOtherQueues() {
        val custom = runBlocking {
            val queue = queues.createQueue("Other queue", keepsWorksOffline = false)
            for (work in listOf(first, second)) {
                queues.addWork(queue.id, work.id)
                queues.addToSavedForLater(work.id)
            }
            queue
        }
        show { ScopedSelectionBar(listOf(first, second), "Remove", "collection", works, queues, null,
            io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current.scopePalette,
            onRemove = {}, onChanged = {}, onDone = {}) }
        compose.onNodeWithText("Actions").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Remove from Saved for Later").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Remove from Saved for Later").performClick()
        await { !queues.isInSavedForLater(first.id) && !queues.isInSavedForLater(second.id) }
        runBlocking {
            assertEquals(2, queues.listWorks(custom.id).size)
            assertFalse(works.getWork(first.id)!!.isDeleted)
        }
    }

    @Test fun existingCollectionEditsPersistBeforeDoneAndSurviveLeaving() {
        val collection = runBlocking { works.createCollection("Shelf", description = "Before") }
        val shown = mutableStateOf(true)
        var saves = 0
        show { if (shown.value) CollectionEditorSheet(works, collection, {}, { saves++ }) }
        compose.onNodeWithText("Before").performTextReplacement("Keep this description")
        compose.runOnIdle { shown.value = false }
        await { works.getCollection(collection.id)?.description == "Keep this description" }
        assertEquals(0, saves)
    }

    @Test fun queueEditorUsesThePickedFillForItsSwitchAndReadableSheetInkForCancel() {
        val queue = runBlocking { queues.createQueue("Blue queue", hue = 0.62, colorHex = "#193B97", keepsWorksOffline = true) }
        val oldInspector = isDebugInspectorInfoEnabled
        isDebugInspectorInfoEnabled = true
        try {
            compose.setContent { KudosTheme(io.github.cidy02.kudos.ui.theme.KudosThemeMode.Dark) {
                QueueEditorSheet(queues, queue, {}, {})
            } }
            assertSwitchFill("Keep works offline", Color(0xFF990000))
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("Cancel").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(ReaderTheme.Dark.accentInk(Color(0xFF990000)), layouts.single().layoutInput.style.color)
        } finally { isDebugInspectorInfoEnabled = oldInspector }
    }

    @Test fun collectionEditorUsesThePickedFillForBothSwitches() {
        val collection = runBlocking { works.createCollection("Blue collection", hue = 0.62, colorHex = "#193B97",
            keepsWorksOffline = true, showsOnHome = true) }
        val oldInspector = isDebugInspectorInfoEnabled
        isDebugInspectorInfoEnabled = true
        try {
            compose.setContent { KudosTheme(io.github.cidy02.kudos.ui.theme.KudosThemeMode.Oled) {
                CollectionEditorSheet(works, collection, {}, {})
            } }
            assertSwitchFill("Keep downloads", Color(0xFF990000))
            assertSwitchFill("Show on Home", Color(0xFF990000))
        } finally { isDebugInspectorInfoEnabled = oldInspector }
    }

    private fun assertSwitchFill(description: String, expected: Color) {
        val colors = compose.onNodeWithContentDescription(description).fetchSemanticsNode().layoutInfo.getModifierInfo()
            .flatMap { (it.modifier as? InspectableValue)?.inspectableElements?.toList().orEmpty() }
            .filter { it.name == "color" }.map { it.value }
        assertTrue("$description track should be $expected, was $colors", expected in colors)
    }

    @Test fun collectionWorkLongPressOffersSharedActionsAndScopedRemove() {
        val collection = runBlocking { works.createCollection("Shelf").also { works.addWorkToCollection(first.id, it.id) } }
        show { CollectionDetailScreen(collection.id, works, queueRepository = queues,
            onOpenWork = {}, onOpenReader = {}, onCollectionDeleted = {}) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("First work").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("First work").performTouchInput { longClick() }
        compose.onNodeWithText("Comments").assertExists()
        compose.onNodeWithText("Select").assertExists()
        compose.onNodeWithText("Add to Queue").assertExists()
        compose.onNodeWithText("Delete").assertExists()
        compose.onNodeWithText("Remove from Collection").assertExists()
    }

    @Test fun queueWorkLongPressUsesFullMenuAndScopedRemovalAsks() {
        val queue = runBlocking { queues.createQueue("To read", keepsWorksOffline = false).also { queues.addWork(it.id, first.id) } }
        show { QueuePageScreen(queues, queue.id, { 1L }, workRepository = works,
            onOpenWork = {}, onOpenReader = {}, onManageQueue = {}) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("First work").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("First work").performTouchInput { longClick() }
        compose.onNodeWithText("Comments").assertExists()
        compose.onNodeWithText("Add to Collection").assertExists()
        compose.onNodeWithText("Work Details").assertExists()
        compose.onNodeWithText("Delete").assertExists()
        compose.onNodeWithText("Remove from Queue").performClick()
        compose.onNodeWithText("Remove this work?").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        runBlocking { assertEquals(1, queues.listWorks(queue.id).size) }
    }
}
