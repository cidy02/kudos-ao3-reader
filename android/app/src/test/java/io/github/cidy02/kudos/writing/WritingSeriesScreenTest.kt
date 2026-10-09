package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.AO3SeriesField
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingSeriesScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: SeriesSetup
    private lateinit var model: WritingSeriesState
    private val chrome = PushedShellChrome()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableStateOf(1f)
    private var backCount = 0
    private var browser: String? = null

    private fun show(load: Boolean = true) {
        setup = runBlocking { seriesSetup() }
        model = setup.model()
        if (load) runBlocking<Unit> { model.load() }
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingSeriesContent(model, "The Dawn Cycle", onBack = { backCount++ }, onOpenAo3 = { browser = it })
                    }
                }
            }
        }
    }
    private fun await(text: String) {
        compose.waitForIdle()
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(text: String) {
        compose.onNodeWithTag("Writing series form").performScrollToNode(hasText(text))
        await(text)
    }
    private fun back() { compose.runOnIdle { chrome.onBack?.invoke() }; compose.waitForIdle() }

    @Test fun delayedFormLoadAddsTheShellSaveAsAValueOnlyWhenItApplies() {
        show(load = false)
        compose.waitForIdle()
        assertNull(chrome.trailingContent)
        compose.onNodeWithText("Save").assertDoesNotExist()
        compose.runOnIdle { runBlocking<Unit> { model.load() } }
        await("Save")
        assertNotNull(chrome.trailingContent)
        compose.onNodeWithText("Save").assertIsEnabled()
        assertEquals(2, setup.client.gets.size)
        assertEquals(0, setup.client.posts.size)
    }

    @Test fun summaryBackAndNotesDoneCheckpointIntoTheSameDraftWithoutReadingOrSaving() {
        show()
        val original = model.state.value.form!!
        reach("Series summary"); compose.onNodeWithText("Series summary").performClick()
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Bold").performClick()
        back(); await("Edit series")
        assertTrue(model.state.value.form!!.summary.contains("<strong></strong>"))
        assertTrue(model.state.value.form!!.summary.contains(original.summary))
        assertEquals(original.notes, model.state.value.form!!.notes)
        assertNotNull(chrome.trailingContent)
        compose.onNodeWithText("Save").assertIsEnabled()
        reach("Series notes"); compose.onNodeWithText("Series notes").performClick()
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Italic").performClick()
        compose.onNodeWithContentDescription("Done").performClick()
        await("Edit series")
        assertTrue(model.state.value.form!!.notes.contains("<em></em>"))
        assertTrue(model.state.value.form!!.notes.contains(original.notes))
        assertEquals(2, setup.client.gets.size)
        assertEquals(0, setup.client.posts.size)
        assertEquals(0, backCount)
    }

    @Test fun workPickerReorderBackReturnsToPickerThenKeepsTheUnsavedWorkAndItsChrome() {
        val workSetup = runBlocking { workFormSetup() }
        val work = workSetup.model(995006)
        setup = runBlocking { seriesSetup() }
        runBlocking<Unit> { work.load() }
        work.title("A held work title")
        val draft = work.state.value.form
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingWorkFormContent(work, work.account, "Edit work", { backCount++ },
                            seriesRepository = setup.repository, seriesWrites = setup.writes)
                    }
                }
            }
        }
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Series"))
        compose.onNodeWithText("Series").performClick()
        compose.onNodeWithTag("Writing association picker").performScrollToNode(hasText("Reorder the series"))
        compose.onNodeWithText("Reorder the series").performClick()
        await("Reorder")
        assertEquals(listOf("https://archiveofourown.org/series/77/manage"), setup.client.gets)
        back(); await("Reorder the series")
        back(); await("Edit work")
        assertEquals(draft, work.state.value.form)
        assertNotNull(chrome.trailingContent)
        compose.onNodeWithText("Save").assertIsEnabled()
        assertEquals(1, workSetup.client.gets.size)
        assertEquals(0, workSetup.client.posts)
        assertEquals(0, setup.client.posts.size)
        assertEquals(0, backCount)
    }

    @Test fun realFieldsSaveBylineOnceAndLeaveConfirmedFormOpen() {
        show()
        compose.onNodeWithContentDescription("Title").performTextReplacement("A new dawn")
        compose.onNodeWithContentDescription("Creators").performTextReplacement("friend (pseud)")
        compose.onNodeWithText("Save").performClick()
        reach("Series was successfully updated.")
        assertEquals(1, setup.client.posts.size)
        assertEquals(listOf(AO3SeriesField.byline to "friend (pseud)"), setup.client.posts.single().fields.filter { it.first == AO3SeriesField.byline })
        assertEquals("A new dawn", model.state.value.form!!.title)
        assertEquals(0, backCount)
        assertEquals(2, setup.client.gets.size)
    }

    @Test fun refusalRetainsTitleBylineAndEveryOtherField() {
        show()
        setup.client.postResponse = seriesResponse(422, "<div id='error'><ul><li>Byline is invalid</li></ul></div>")
        compose.onNodeWithContentDescription("Title").performTextReplacement("Still here")
        compose.onNodeWithContentDescription("Creators").performTextReplacement("rejected (pseud)")
        val before = model.state.value.form
        compose.onNodeWithText("Save").performClick()
        reach("Byline is invalid")
        assertEquals(before, model.state.value.form)
        assertEquals(0, backCount)
        assertEquals(1, setup.client.posts.size)
    }

    @Test fun heldSaveDisablesButtonAndDoesNotOptimisticallyConfirm() {
        show()
        val hold = CompletableDeferred<Unit>()
        setup.client.beforePost = { hold.await() }
        compose.onNodeWithText("Save").performClick()
        compose.waitForIdle()
        compose.waitUntil(15_000) { setup.client.posts.size == 1 }
        compose.onNodeWithText("Save").assertIsNotEnabled()
        assertNull(model.state.value.notice)
        hold.complete(Unit)
        reach("Series was successfully updated.")
        compose.onNodeWithText("Save").assertIsEnabled()
    }

    @Test fun reorderUsesOwnChromeCustomMoveAndReturnsOnlyAfterVerification() {
        show()
        reach("Reorder works"); compose.onNodeWithText("Reorder works").performClick()
        await("Reorder")
        val row = compose.onNodeWithContentDescription("1. First Light")
        val actions = row.fetchSemanticsNode().config[SemanticsActions.CustomActions]
        compose.runOnIdle { assertTrue(actions.first { it.label == "Move Later" }.action()) }
        assertEquals(0, setup.client.posts.size)
        compose.onNodeWithText("Save").performClick()
        await("Edit series")
        assertEquals(listOf(3212L, 3211L, 3213L), model.state.value.form!!.works.map { it.serialWorkID })
        assertEquals(1, setup.client.posts.size)
        reach("Reorder works"); compose.onNodeWithText("Reorder works").performClick()
        await("Reorder"); compose.onNodeWithContentDescription("1. A Lamp at the Crossing").assertExists()
        back(); await("Edit series")
        assertEquals(4, setup.client.gets.size)
        assertEquals(0, backCount)
    }

    @Test fun longPressDragChangesOnlyLocalOrderUntilSave() {
        show()
        reach("Reorder works"); compose.onNodeWithText("Reorder works").performClick(); await("Reorder")
        val first = compose.onNodeWithContentDescription("1. First Light").fetchSemanticsNode().boundsInRoot
        val second = compose.onNodeWithContentDescription("2. A Lamp at the Crossing").fetchSemanticsNode().boundsInRoot
        compose.onRoot().performTouchInput {
            down(first.center)
            advanceEventTime(1000L)
            moveTo(second.center)
            up()
        }
        compose.waitForIdle()
        assertEquals(listOf(3212L, 3211L, 3213L), model.state.value.rows!!.map { it.serialWorkID })
        assertEquals(0, setup.client.posts.size)
        compose.onNodeWithText("Save").performClick(); await("Edit series")
        assertEquals(1, setup.client.posts.size)
    }

    @Test fun removeConfirmationAndBrowserDeleteKeepIosBoundary() {
        show()
        reach("Remove works"); compose.onNodeWithText("Remove works").performClick()
        await("Remove works")
        compose.onNodeWithContentDescription("Remove First Light from the series").performClick()
        await("Remove “First Light” from The Dawn Cycle?")
        compose.onNodeWithText("The work stays posted on AO3.").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(0, setup.client.posts.size)
        back(); await("Edit series")
        reach("Delete series on AO3"); compose.onNodeWithText("Delete series on AO3").performClick()
        assertEquals("https://archiveofourown.org/series/321", browser)
        assertEquals(2, setup.client.gets.size)
        assertEquals(0, setup.client.posts.size)
    }

    @Test fun allThemesAndAccessibilityScaleWrapLongRowsWithoutHeightOverflowOrEllipsis() {
        scale = 2f
        show()
        compose.runOnIdle { model.edit { it.copy(works = it.works.map { row -> row.copy(
            title = row.title + " — a long original title about lanterns carried across the quiet harbour at dawn") }) } }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            for (label in listOf("Title", "Creators", "Series summary", "Series notes", "Series is complete", "Reorder works", "Remove works", "Delete series on AO3", "Save")) {
                if (label != "Save") reach(label)
                val nodes = compose.onAllNodesWithText(label, useUnmergedTree = true)
                val count = nodes.fetchSemanticsNodes().size
                assertTrue(count > 0)
                repeat(count) { index ->
                    val layouts = mutableListOf<TextLayoutResult>()
                    nodes[index].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    assertTrue(layouts.isNotEmpty())
                    layouts.forEach { layout ->
                        assertFalse("$theme / $label", layout.didOverflowHeight)
                        if (layout.lineCount > 0) assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
                    }
                }
            }
            reach("Reorder works"); compose.onNodeWithText("Reorder works").performClick(); await("Reorder")
            val longTitle = model.state.value.rows!!.first().title
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(longTitle, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            back(); await("Edit series")
        }
    }

    @Test fun largeWorksListIsLazyAndLastDraftCanMoveUsingAccessibilityAction() {
        show()
        compose.runOnIdle { model.edit { it.copy(works = List(150) { index ->
            io.github.cidy02.kudos.network.ao3.writing.AO3SeriesWorkRow(index.toLong() + 1, "Work $index", index + 1, isDraft = index == 149)
        }) } }
        reach("Reorder works"); compose.onNodeWithText("Reorder works").performClick(); await("Reorder")
        compose.onNodeWithText("Work 149").assertDoesNotExist()
        reach("Work 149")
        val actions = compose.onNodeWithContentDescription("150. Work 149, Draft").fetchSemanticsNode().config[SemanticsActions.CustomActions]
        compose.runOnIdle { assertTrue(actions.first { it.label == "Move Earlier" }.action()) }
        assertEquals("Work 149", model.state.value.rows!![148].title)
        assertEquals(0, setup.client.posts.size)
        assertEquals(2, setup.client.gets.size)
    }
}
