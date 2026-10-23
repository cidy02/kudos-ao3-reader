package io.github.cidy02.kudos.library

import android.app.Application
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
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

@org.robolectric.annotation.GraphicsMode(org.robolectric.annotation.GraphicsMode.Mode.NATIVE)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
class TagSheetParityTest {
    @Test fun mergeChoicesSpeakTheirScopeAndConfirmationRepeatsIt() {
        val queues = ReadingQueueRepository(database)
        val queue = runBlocking { queues.createQueue("Read", tagNames = listOf("Comfort", "Rereads")) }
        val tags = runBlocking { queues.tagsForQueue(queue.id) }
        val source = tags.first { it.name == "Rereads" }
        val target = tags.first { it.name == "Comfort" }
        compose.setContent { if (visible.value) KudosTheme(KudosThemeMode.Light) {
            InlineTagEditor(queues, queue.id, source, listOf(target), mapOf(target.id to 12), 3)
        } }
        compose.onNodeWithContentDescription("Merge into Comfort, 12 works in this queue").performClick()
        val confirmation = "Merge “${source.name}” into “${target.name}”?"
        val expected = "All 3 works in this queue get the tag you pick, and “Rereads” leaves the queue. You can't undo this in Kudos."
        compose.onNode(hasText(expected) and hasAnyAncestor(hasTestTag(confirmation))).assertExists()
        assertEquals("No work in this queue uses “Rereads”. Merging removes the tag from this queue.",
            queueTagMergeMessage(source.name, 0))
    }

    @Test fun workTagNameCanBeAddedFromTheKeyboard() {
        runBlocking { works.upsert(SavedWork(id = "one", title = "First", author = "A")) }
        compose.setContent { if (visible.value) KudosTheme(KudosThemeMode.Light) {
            WorkBulkTagSheet(works, listOf("one"), LocalKudosTokens.current.scopePalette, {})
        } }
        compose.onNode(hasSetTextAction()).performTextInput("Comfort")
        compose.onNode(hasSetTextAction()).performImeAction()
        compose.waitUntil(5_000) { runBlocking { works.userTagsForWork("one").any { it.name == "Comfort" } } }
    }

    @Test fun aConflictingRenameCannotBeSavedAndCopyNeedsAnotherQueue() {
        val queues = ReadingQueueRepository(database)
        val queue = runBlocking { queues.createQueue("Read", tagNames = listOf("Comfort", "Rereads")) }
        val tags = runBlocking { queues.tagsForQueue(queue.id) }
        val source = tags.first { it.name == "Rereads" }
        val editing = mutableStateOf(false)
        compose.setContent { if (visible.value) KudosTheme(KudosThemeMode.Light) {
            if (editing.value) InlineTagEditor(queues, queue.id, source, tags.filter { it.id != source.id }, count = 0)
            else QueueTagManager(queues, queue, LocalKudosTokens.current.scopePalette, 0, {}, {})
        } }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Rereads").fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodesWithContentDescription("0 works in this queue", useUnmergedTree = true).assertCountEquals(2)
        compose.onNodeWithText("Rereads").performClick()
        compose.onNodeWithText("Copy tag to another queue").assertIsNotEnabled()
        // The manager/menu was checked above; the large editor runs in the activity window.
        compose.runOnIdle { editing.value = true }
        compose.onNodeWithText("Name").performTextReplacement("Comfort")
        compose.onNodeWithText("Save").assertIsNotEnabled()
        compose.waitUntil(5_000) { compose.onAllNodesWithText("You already have a tag called “Comfort”.").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Save").assertIsNotEnabled()
    }

    @Composable
    private fun InlineTagEditor(
        repository: ReadingQueueRepository, queueId: String, tag: Tag, siblings: List<Tag>,
        counts: Map<String, Int> = emptyMap(), count: Int, onRemove: () -> Unit = {}
    ) {
        Box(Modifier.fillMaxSize()) {
            QueueTagEditContent(repository, queueId, tag, siblings, counts, count, onRemove, {}, {}) {
                    _, title, body, confirm, dismiss ->
                Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).testTag(title)) {
                    Text(title)
                    Box(Modifier.weight(1f, fill = false)) { body() }
                    Row { dismiss(); confirm() }
                }
            }
        }
    }

    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private val directory = Files.createTempDirectory("tag-sheet-parity")
    private val visible = mutableStateOf(true)

    @Before fun setUp() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().setQueryExecutor { it.run() }.setTransactionExecutor { it.run() }.build()
        works = WorkRepository(database, WorkFileStore(directory))
    }

    @After fun tearDown() {
        compose.runOnIdle { visible.value = false }
        compose.waitForIdle()
        database.close()
        directory.toFile().deleteRecursively()
    }

    @Test fun editTagPutsMergeBeforeTheRemoveSection() {
        val queues = ReadingQueueRepository(database)
        val queue = runBlocking { queues.createQueue("Rereads", tagNames = listOf("Rereads", "Comfort")) }
        val tags = runBlocking { queues.tagsForQueue(queue.id) }
        val source = tags.first { it.name == "Rereads" }
        val removing = mutableStateOf(false)
        compose.setContent {
            if (visible.value) KudosTheme(KudosThemeMode.Light) {
                if (removing.value) QueueTagRemovalDialog(source, 0, onDismiss = { removing.value = false }, onConfirm = {})
                else InlineTagEditor(queues, queue.id, source, tags.filter { it.id != source.id }, count = 0,
                    onRemove = { removing.value = true })
            }
        }
        val name = compose.onNodeWithText("Name").fetchSemanticsNode().boundsInRoot
        val merge = compose.onNodeWithText("MERGE INTO ANOTHER TAG").fetchSemanticsNode().boundsInRoot
        val remove = compose.onNodeWithText("REMOVE").fetchSemanticsNode().boundsInRoot
        val action = compose.onNodeWithText("Remove from this queue").fetchSemanticsNode().boundsInRoot
        assertTrue(name.top < merge.top && merge.top < remove.top && remove.top < action.top)
        compose.onNodeWithText("Remove from this queue").performClick()
        compose.onNodeWithText("Remove “Rereads” from this queue?").assertExists()
    }

    @Test fun workTagsHaveLeadingThreeStateMarksAndToggleOnlyTheSelectedWorks() {
        runBlocking {
            listOf("one", "two", "outside").forEach { works.upsert(SavedWork(id = it, title = it, author = "A")) }
            works.addUserTag("one", "AllTag"); works.addUserTag("two", "AllTag")
            works.addUserTag("one", "SomeTag"); works.addUserTag("outside", "UnusedTag")
        }
        compose.setContent {
            if (visible.value) KudosTheme(KudosThemeMode.Light) {
                WorkBulkTagSheet(works, listOf("one", "two"), LocalKudosTokens.current.scopePalette, {})
            }
        }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("Tag selection mark", useUnmergedTree = true)
            .fetchSemanticsNodes().size == 3 }
        compose.onNode(hasText("Tag") and hasAnyAncestor(isDialog())).assertExists()
        compose.onNodeWithText("Your changes apply to all 2 selected works.").assertExists()
        compose.onNodeWithText("All").assertDoesNotExist()
        val marks = compose.onAllNodesWithTag("Tag selection mark", useUnmergedTree = true).fetchSemanticsNodes()
        listOf("AllTag", "SomeTag", "UnusedTag").forEachIndexed { index, name ->
            val text = compose.onNodeWithText(name, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("Selection mark precedes $name", marks[index].boundsInRoot.right <= text.left)
        }
        compose.onNodeWithText("SomeTag").performClick()
        compose.waitUntil(5_000) { runBlocking { works.userTagsForWork("two").any { it.name == "SomeTag" } } }
        assertEquals(listOf("UnusedTag"), runBlocking { works.userTagsForWork("outside").map { it.name } })
    }

    @Test fun aQueuePagesSelectedWorksOpenWorkTagsInsteadOfQueueVocabulary() {
        val queues = ReadingQueueRepository(database)
        val queue = runBlocking {
            works.upsert(SavedWork(id = "one", title = "First work", author = "A"))
            works.upsert(SavedWork(id = "two", title = "Second work", author = "A"))
            queues.createQueue("Rereads").also {
                queues.addWork(it.id, "one", enqueueMissingEpub = false)
                queues.addWork(it.id, "two", enqueueMissingEpub = false)
            }
        }
        val chrome = PushedShellChrome()
        compose.setContent {
            if (visible.value) KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    Box {
                        QueuePageScreen(queues, queue.id, epubBytes = { 0L }, workRepository = works,
                            onOpenWork = {}, onOpenReader = {}, onManageQueue = {})
                        Row(Modifier.align(Alignment.TopEnd)) { chrome.trailingContent?.invoke(this) }
                    }
                }
            }
        }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("First work").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithText("Select").performClick()
        compose.onNodeWithText("Select All").performClick()
        compose.onNodeWithText("+ TAG").performClick()
        compose.onNode(hasText("Tag") and hasAnyAncestor(isDialog())).assertExists()
        compose.onNodeWithText("Your changes apply to all 2 selected works.").assertExists()
        compose.onNode(hasSetTextAction()).performTextInput("Comfort")
        compose.onNodeWithText("Add").performClick()
        compose.waitUntil(5_000) { runBlocking { works.userTagsForWork("two").any { it.name == "Comfort" } } }
        assertTrue(runBlocking { works.userTagsForWork("one").any { it.name == "Comfort" } })
        assertTrue("Tagging works must leave the queue vocabulary alone", runBlocking { queues.tagsForQueue(queue.id).isEmpty() })
    }
}
