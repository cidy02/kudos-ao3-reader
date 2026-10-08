package io.github.cidy02.kudos.works

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.*
import io.github.cidy02.kudos.works.detail.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.launch
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
class WorkDetailFormsTest {
    @get:Rule val compose = createComposeRule()
    private val chrome = PushedShellChrome()
    private fun show(mode: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f, content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        content()
                    }
                }
            }
        }
        compose.waitForIdle()
    }
    private fun reach(text: String) {
        compose.onNodeWithTag("Work detail form").performScrollToNode(hasText(text))
        compose.waitForIdle()
    }
    private fun noClippedText(text: String) {
        reach(text)
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onAllNodesWithText(text).onFirst().performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        for (layout in layouts) {
            assertFalse(layout.didOverflowHeight)
            assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
        }
    }
    private fun series(mode: KudosThemeMode) {
        var enabled by mutableStateOf(false)
        var only = 0
        var preserve = 0
        val prompt = SeriesPreservationPrompt(null, 25, true)
        show(mode, 2f) { WorkDetailSeriesForm(prompt, enabled, { enabled = it }, { only++ }, { preserve++ }) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Preserve Series?").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Preserve Series?").assertExists()
        compose.runOnIdle { assertNotNull(chrome.onBack) }
        noClippedText(prompt.message)
        noClippedText(prompt.autoPreserveLabel)
        reach(prompt.autoPreserveLabel)
        compose.onNodeWithContentDescription(prompt.autoPreserveLabel).performClick()
        compose.runOnIdle { assertTrue(enabled) }
        noClippedText("Preserve Entire Series")
        reach("Preserve Entire Series"); compose.onNodeWithText("Preserve Entire Series").performClick()
        reach("Only This Work"); compose.onNodeWithText("Only This Work").performClick()
        compose.runOnIdle { assertEquals(1, only); assertEquals(1, preserve) }
    }
    @Test fun seriesLightAtAccessibilitySize() = series(KudosThemeMode.Light)
    @Test fun seriesDarkAtAccessibilitySize() = series(KudosThemeMode.Dark)
    @Test fun seriesSepiaAtAccessibilitySize() = series(KudosThemeMode.Sepia)
    @Test fun seriesOledAtAccessibilitySize() = series(KudosThemeMode.Oled)

    private fun bookmarkInventory(mode: KudosThemeMode) {
        show(mode, 2f) { WorkDetailBookmarkForm(AO3BookmarkInput(), false, false, null, {}, {}, {}) }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Bookmark on AO3").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Bookmark on AO3").assertExists()
        compose.onNodeWithContentDescription("Notes").assertExists()
        noClippedText("Comma-separated tags")
        noClippedText("Separate your bookmark tags with commas.")
        reach("Private"); compose.onNodeWithContentDescription("Private").assertIsOff()
        reach("Recommend"); compose.onNodeWithContentDescription("Recommend").assertIsOff()
        compose.onNodeWithText("Cancel").assertExists()
        compose.onNodeWithText("Save").assertExists()
    }
    @Test fun bookmarkLightAtAccessibilitySize() = bookmarkInventory(KudosThemeMode.Light)
    @Test fun bookmarkDarkAtAccessibilitySize() = bookmarkInventory(KudosThemeMode.Dark)
    @Test fun bookmarkSepiaAtAccessibilitySize() = bookmarkInventory(KudosThemeMode.Sepia)
    @Test fun bookmarkOledAtAccessibilitySize() = bookmarkInventory(KudosThemeMode.Oled)

    @Test fun bookmarkFieldsReachExistingWriteUnchangedAndRefusalKeepsDraftOpen() {
        val form = """<meta name='csrf-token' content='local-token'><form action='/works/123/bookmarks'>
            <input name='bookmark[pseud_id]' value='99'></form>"""
        val client = FakeAuthenticatedClient(listOf(success(form)), listOf(success(
            "<div id='error'><ul><li>Notes must be less than 5000 characters long.</li></ul></div>")))
        val writes = AO3WriteRepository(client)
        var input by mutableStateOf(AO3BookmarkInput())
        var error by mutableStateOf<String?>(null)
        var working by mutableStateOf(false)
        var open by mutableStateOf(true)
        show(KudosThemeMode.Sepia, 2f) {
            val scope = rememberCoroutineScope()
            if (open) WorkDetailBookmarkForm(input, false, working, error, { input = it }, onSave = {
                scope.launch {
                    working = true
                    val result = writes.createBookmark(123, input)
                    if (result is AO3Result.Failure) error = result.error.displayMessage() else open = false
                    working = false
                }
            }, onClose = { open = false })
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Bookmark on AO3").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Bookmark on AO3").assertExists()
        val notes = "n".repeat(5001)
        compose.onNodeWithContentDescription("Notes").performTextReplacement(notes)
        reach("Separate your bookmark tags with commas.")
        compose.onNodeWithContentDescription("Tags").performTextReplacement(" keep, spaces & 星 ")
        reach("Private"); compose.onNodeWithContentDescription("Private").performClick()
        reach("Recommend"); compose.onNodeWithContentDescription("Recommend").performClick()
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { error != null && !working }
        noClippedText("Notes must be less than 5000 characters long.")
        compose.runOnIdle {
            assertTrue(open)
            assertEquals(notes, input.notes)
            assertEquals(" keep, spaces & 星 ", input.tags)
            assertEquals(1, client.gets.size)
            assertEquals(1, client.posts.size)
            val fields = client.posts.single().fields.toMap()
            assertEquals(notes, fields["bookmark[bookmarker_notes]"])
            assertEquals(input.tags, fields["bookmark[tag_string]"])
            assertEquals("1", fields["bookmark[private]"])
            assertEquals("1", fields["bookmark[rec]"])
        }
    }

    @Test fun workingBookmarkDisablesFieldsSaveAndDismissal() {
        var closes = 0
        show { WorkDetailBookmarkForm(AO3BookmarkInput(notes = "Keep me"), true, true, null, {}, {}, { closes++ }) }
        compose.onNodeWithContentDescription("Notes").assertIsNotEnabled()
        compose.onNodeWithText("Cancel").assertIsNotEnabled()
        compose.onNodeWithText("Save").assertDoesNotExist()
        compose.runOnIdle { chrome.onBack!!.invoke(); assertEquals(0, closes) }
    }

    @Test fun queueSheetHasProgressCancelCompletionAndFootnote() {
        var running by mutableStateOf(true)
        var result by mutableStateOf(SeriesPreservationResult(total = 4, preserved = 2))
        var cancel = 0
        show(KudosThemeMode.Oled, 2f) {
            WorkDetailQueueForm(emptyList(), emptySet(), "", false, true, true, false, null,
                running, result, {}, {}, {}, {}, {}, {
                    cancel++; running = false; result = result.copy(cancelled = 2)
                }, {})
        }
        noClippedText("Adding 2 of 4 series works…")
        reach("Cancel Series Addition"); compose.onNodeWithText("Cancel Series Addition").performClick()
        noClippedText("Stopped adding the series. 2 works were added.")
        noClippedText("Kudos adds series works only after you choose Add Series, one work at a time.")
        compose.runOnIdle { assertEquals(1, cancel) }
    }
}
