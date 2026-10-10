package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2800dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingBulkEditScreenTest {
    @get:Rule val compose = createComposeRule()
    private val client = BulkRecordingClient(listOf(11, 22, 33))
    private val model = WritingBulkEditState(client.ids, AO3WriteRepository(client), 7)
    private var theme by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)
    private var closed by mutableStateOf(false)
    private fun show(focus: String? = null) {
        val chrome = PushedShellChrome()
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        if (closed) Text("Own list remains selected")
                        else WritingBulkEditScreen(model, focus, { closed = true }, { closed = true })
                    }
                }
            }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithContentDescription("Save").fetchSemanticsNodes().isNotEmpty() }
    }
    private fun scroll(label: String) { compose.onNode(hasScrollAction()).performScrollToNode(hasText(label)) }
    @Test fun saveAppearsAfterLoadRefusalAndUnconfirmedRetainFormThenSuccessDismisses() {
        show()
        assertEquals(2, client.requests.size); assertEquals(1, client.posts.size)
        scroll("Add co-creators")
        compose.onNodeWithText("Pseud").performTextInput("Writer")
        client.status = 422; client.reply = "<main id=main><div class='flash error'>AO3 refuses this creator.</div></main>"
        compose.onNodeWithContentDescription("Save").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("AO3 refuses this creator.").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("OK").performClick()
        assertEquals("Writer", model.state.value.changes.pseudsToAdd); assertFalse(model.state.value.saving)
        client.status = 200; client.reply = "<form><textarea>Saved successfully</textarea></form>"
        compose.onNodeWithContentDescription("Save").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText(AO3CollectionFields.UNCONFIRMED).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(AO3CollectionFields.UNCONFIRMED).assertExists()
        compose.onNodeWithText("OK").performClick()
        assertFalse(closed); assertFalse(model.state.value.saving)
        client.reply = "<main id=main><div class='flash notice'>Saved.</div></main>"
        compose.onNodeWithContentDescription("Save").performClick()
        compose.waitUntil(15_000) { closed }
        compose.onNodeWithText("Own list remains selected").assertExists()
        assertEquals(4, client.posts.size); assertEquals(8, client.requests.size)
    }
    @Test fun collectionAndVisibilityFocusAndThreeStateChoicesUseServedOptionsWithoutRequests() {
        show("Collections and gifts")
        compose.onNodeWithText("Add to collections").assertIsDisplayed()
        scroll("Only show to registered users")
        compose.onNodeWithText("Only show to registered users").performClick()
        compose.onNodeWithText("On").performClick()
        assertEquals("1", model.state.value.changes.scalars["work[restricted]"])
        scroll("Archive warnings"); compose.onNodeWithText("Archive warnings").performClick()
        compose.onNodeWithText("No Archive Warnings Apply").performClick()
        assertEquals(listOf("No Archive Warnings Apply"), model.state.value.changes.added["work[archive_warning_strings][]"])
        compose.onNodeWithText("No Archive Warnings Apply").performClick()
        assertEquals(listOf("No Archive Warnings Apply"), model.state.value.changes.removed["work[archive_warning_strings][]"])
        compose.onNodeWithText("No Archive Warnings Apply").performClick()
        assertTrue(model.state.value.changes.removed["work[archive_warning_strings][]"].orEmpty().isEmpty())
        assertEquals(2, client.requests.size); assertEquals(1, client.posts.size)
    }
    @Test fun cancelledFormSendsOnlyItsInitialRenderingPost() {
        show(); compose.onNodeWithContentDescription("Cancel").performClick()
        compose.waitUntil(15_000) { closed }
        assertEquals(2, client.requests.size); assertEquals(1, client.posts.size)
    }
    @Test fun longRowsAndFootnotesHaveFullHeightAcrossFourThemesAtAccessibilitySize() {
        show("Comments and visibility")
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode; scale = 2f }
            for (label in listOf("Only show to registered users", "Enable comment moderation", "Remove me as a co-creator")) {
                scroll(label)
                compose.onNodeWithText(label).assertIsDisplayed()
                val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithText(label).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
                layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
            }
        }
    }
}
