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
    @Test fun unchangedIsSpokenWithoutAnExtraVisibleWord() {
        var changes by mutableStateOf(io.github.cidy02.kudos.network.ao3.writing.AO3BulkEditChanges(workIDs = emptyList()))
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            BulkOptionsScreen(BulkPicker("Archive warnings", "warnings", "tri"),
                listOf(io.github.cidy02.kudos.network.ao3.writing.AO3FormOption("none", "No warnings")), changes,
                { changes = it(changes) }, {})
        } }
        compose.onNodeWithText("Unchanged").assertDoesNotExist()
        compose.onNodeWithText("Tap an option once", substring = true).assertDoesNotExist()
        val rowNode = compose.onNodeWithText("No warnings")
        compose.onNode(hasText("No warnings") and SemanticsMatcher.expectValue(
            androidx.compose.ui.semantics.SemanticsProperties.StateDescription, "Unchanged")).assertExists()
        assertEquals("add it to every selected work",
            rowNode.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.OnClick].label)
        rowNode.performClick()
        compose.onNodeWithText("Add").assertExists()
        assertEquals("remove it from every selected work",
            rowNode.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.OnClick].label)
        rowNode.performClick()
        compose.onNodeWithText("Remove").assertExists()
        assertEquals("leave it unchanged",
            rowNode.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.OnClick].label)
        val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithText("No warnings", useUnmergedTree = true).performSemanticsAction(
            androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertEquals(androidx.compose.ui.text.style.TextDecoration.LineThrough, layouts.single().layoutInput.style.textDecoration)
        compose.onNodeWithTag("Bulk option mark", useUnmergedTree = true).assertExists()
    }

    @Test fun addedCollectionNamesHaveAHeading() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            BulkOptionsScreen(BulkPicker("Add to collections", "collections", "names"), emptyList(),
                io.github.cidy02.kudos.network.ao3.writing.AO3BulkEditChanges(workIDs = emptyList(), collectionsToAdd = listOf("Winter")), {}, {})
        } }
        compose.onNodeWithText("ADDED").assertExists()
    }


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
    /** iOS draws these five as `WritingChoiceRow` (EditMultipleWorksView.swift:251, 271, 326, 332, 338): choices (3hj). */
    @Test fun scalarRowsAreChoicesAndThreeStateRowsStayDisclosures() {
        show()
        fun indicatorBeside(label: String) = compose.onNode(hasTestTag("Choice indicator") and
            hasParent(hasAnyDescendant(hasText(label))), useUnmergedTree = true)
        for (label in listOf("Rating", "Language", "Only show to registered users", "Enable comment moderation", "Who can comment")) {
            scroll(label)
            indicatorBeside(label).assertExists()
        }
        for (label in listOf("Archive warnings", "Categories")) {
            scroll(label)
            indicatorBeside(label).assertDoesNotExist()
        }
    }

    /** iOS's tag-state page (`BulkTagStatePicker`) is a plain list; its names page keeps the wash (3hj). */
    @Test fun tagStatePageIsFlatWhileTheNamesPageKeepsItsWash() {
        var pickerMode by mutableStateOf("tri")
        lateinit var view: android.view.View
        var ground = androidx.compose.ui.graphics.Color.Unspecified
        var card = androidx.compose.ui.graphics.Color.Unspecified
        compose.setContent { KudosTheme(theme) {
            view = androidx.compose.ui.platform.LocalView.current
            // A plain list's ground and cards, as the Settings pages (3hk): SurfaceDark in Dark, elevated cards.
            val tokens = io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current
            ground = if (tokens.theme == io.github.cidy02.kudos.ui.subject.ReaderTheme.Dark) io.github.cidy02.kudos.ui.theme.SurfaceDark
                else tokens.background
            card = tokens.theme.cardSurface
            BulkOptionsScreen(BulkPicker("Archive warnings", "warnings", pickerMode),
                listOf(io.github.cidy02.kudos.network.ao3.writing.AO3FormOption("none", "No warnings")),
                io.github.cidy02.kudos.network.ao3.writing.AO3BulkEditChanges(workIDs = emptyList()), {}, {})
        } }
        fun pixel(x: (Int) -> Int, y: Int): androidx.compose.ui.graphics.Color {
            var color = androidx.compose.ui.graphics.Color.Unspecified
            compose.runOnIdle {
                val bitmap = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
                view.draw(android.graphics.Canvas(bitmap))
                color = androidx.compose.ui.graphics.Color(bitmap.getPixel(x(view.width), y))
                bitmap.recycle()
            }
            return color
        }
        fun top() = pixel({ it / 2 }, 4)
        fun near(a: androidx.compose.ui.graphics.Color, b: androidx.compose.ui.graphics.Color) =
            maxOf(kotlin.math.abs(a.red - b.red), kotlin.math.abs(a.green - b.green), kotlin.math.abs(a.blue - b.blue)) < 0.012f
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode; pickerMode = "tri" }
            compose.waitForIdle()
            assertTrue("Flat tag-state page in $mode", near(top(), ground))
            val row = compose.onNodeWithText("No warnings").fetchSemanticsNode().boundsInRoot
            assertTrue("Tag-state rows are the plain list's cards in $mode", near(pixel({ it - 120 }, row.center.y.toInt()), card))
            if (mode == KudosThemeMode.Dark || mode == KudosThemeMode.Oled) {
                compose.runOnIdle { pickerMode = "names" }
                compose.waitForIdle()
                assertFalse("The names page keeps its wash in $mode", near(top(), ground))
            }
        }
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
