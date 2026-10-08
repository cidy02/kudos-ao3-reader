package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
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
class WritingAssociationScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var form: WritingWorkFormState
    private val client = AssociationSuggestionsClient()
    private val repository = AO3TagAutocompleteRepository(client)
    private val chrome = PushedShellChrome()
    private var theme by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)

    private fun show(id: Long?) {
        setup = runBlocking { workFormSetup() }
        form = setup.model(id)
        runBlocking { form.load() }
        setup.client.body = workFixture("ao3_collections_index")
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    WritingWorkFormContent(form, "AO3_Reader", "New work", {}, repository)
                }
            }
        }
        awaitTag("Writing work form")
        assertEquals(1, setup.client.gets.size)
    }
    private fun awaitTag(tag: String) = compose.waitUntil(15_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun open(row: String, title: String) {
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText(row))
        compose.onNodeWithText(row).assertHasClickAction().performClick()
        awaitTag("Writing association picker")
        compose.onNodeWithText(title).assertExists()
        compose.onNodeWithText("EDIT WORK").assertExists()
        assertNotNull(chrome.onBack)
        assertNull(chrome.trailingContent) // Back only, restored even after the form was scrolled.
    }
    private fun reach(text: String) = compose.onNodeWithTag("Writing association picker").performScrollToNode(hasText(text, ignoreCase = true))
    private fun back() { compose.runOnIdle { chrome.onBack!!.invoke() }; awaitTag("Writing work form") }

    private fun editEachPicker(id: Long?) {
        show(id)
        open("Series", "Series")
        compose.onNodeWithContentDescription("Mill Maps").performClick()
        compose.waitForIdle()
        assertEquals(listOf("88"), form.state.value.form!!.parameters(AO3WorkSubmitAction.Update)
            .filter { it.first == AO3WorkFormField.seriesID }.map { it.second })
        awaitText("Saving adds ${form.state.value.form!!.title} to Mill Maps")
        reach("Reorder the series")
        compose.onNodeWithText("Reorder the series").assertHasNoClickAction()
        reach("Create a series from this work")
        compose.onNodeWithContentDescription("Create a series from this work").performTextReplacement("  New Voyage 星  ")
        compose.waitForIdle()
        assertTrue(form.state.value.form!!.series.none { it.isSelected })
        back()
        compose.onNodeWithText(if (id == 995006L) "Lantern Voyages + New Voyage 星" else "Adding New Voyage 星").assertExists()

        open("Add to collections", "Collections and gifts")
        awaitText("Winter Exchange 2026")
        assertEquals(2, setup.client.gets.size)
        assertTrue(client.gets.isEmpty()) // No suggestion read on opening.
        compose.onNodeWithContentDescription("Winter Exchange 2026").performClick()
        compose.onNodeWithContentDescription("Search").performTextReplacement("demo")
        awaitText("Demo Two") // Must redraw on answer without another key.
        compose.onNodeWithContentDescription("Add Demo Two").performClick()
        compose.waitForIdle()
        assertFalse(form.state.value.form!!.collections.last().isSelected)
        compose.onNodeWithContentDescription("Demo Two").performClick()
        compose.waitForIdle()
        assertTrue(form.state.value.form!!.postedCollectionNames.contains("demo_two"))
        compose.onNodeWithContentDescription("Search").performTextReplacement("")
        reach("Gift recipients")
        compose.onNodeWithContentDescription("Add").performTextReplacement("  Gift 星  ")
        compose.onNodeWithContentDescription("Add").performImeAction()
        compose.waitForIdle()
        assertTrue(form.state.value.form!!.gifts.contains("Gift 星"))
        reach("Gift 星")
        compose.onNodeWithContentDescription("Remove Gift 星").performClick()
        compose.waitForIdle()
        assertFalse(form.state.value.form!!.gifts.contains("Gift 星"))
        compose.onNodeWithContentDescription("Add").performTextReplacement("Another gift")
        compose.onNode(hasText("Add") and hasClickAction()).performClick()
        compose.waitForIdle()
        assertTrue(form.state.value.form!!.gifts.contains("Another gift"))
        back()
        open("Gift recipients", "Collections and gifts")
        compose.waitForIdle(); assertEquals(2, setup.client.gets.size)
        back()

        open("Co-creators", "Co-creators")
        compose.onNodeWithContentDescription("AO3_Reader").performClick() // Keep last selected.
        compose.waitForIdle(); assertEquals(listOf("101"), form.state.value.form!!.creators.selectedPseudIDs)
        compose.onNodeWithContentDescription("LanternMaker").performClick()
        compose.onNodeWithContentDescription("Byline").performTextReplacement("OtherWriter (pseud)")
        compose.waitForIdle()
        assertEquals(listOf("101", "202"), form.state.value.form!!.creators.selectedPseudIDs)
        back()
        compose.onNodeWithText("2 + 1 invited").assertExists()

        open("Inspired by", "Inspired by")
        compose.onNodeWithContentDescription("URL").performTextReplacement("https://example.test/source")
        compose.onNodeWithContentDescription("Title").performTextReplacement("A source 星")
        compose.onNodeWithContentDescription("Author").performTextReplacement("A creator")
        compose.onNodeWithContentDescription("This work is a translation").performClick()
        reach("Language of the source")
        compose.onNodeWithText("Language of the source").performClick()
        compose.onNodeWithText("Español").performClick()
        compose.waitForIdle()
        assertEquals(AO3ParentWorkDraft("https://example.test/source", "A source 星", "A creator", "2", true), form.state.value.form!!.parentWork)
        compose.onNodeWithContentDescription("URL").performTextReplacement("")
        back()
        // Title-only still encodes a source but iOS words the row None; the header remains route-specific.
        assertEquals("A source 星", form.state.value.form!!.parentWork.title)
        compose.onNode(hasText("Inspired by") and hasText("None")).assertExists()
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts); assertEquals(0, client.posts)
    }
    @Test fun newWorkRowsEditTheFormAndEncoder() = editEachPicker(null)
    @Test fun draftRowsEditTheFormAndEncoder() = editEachPicker(995001L)
    @Test fun postedRowsEditTheFormAndEncoder() = editEachPicker(995006L)

    @Test fun failedCollectionsAndSuggestionsLeaveBothEditorsUsableAndDoNotRetryOnReopen() {
        show(995001L)
        setup.client.failure = AO3Error.Forbidden
        open("Gift recipients", "Collections and gifts")
        awaitText("AO3 offers this work no collections")
        compose.onNodeWithContentDescription("Search").performTextReplacement("fail")
        compose.waitUntil(15_000) { client.gets.isNotEmpty() }
        awaitText("No collection matches “fail”")
        compose.onNodeWithContentDescription("Search").performTextReplacement("none")
        compose.waitUntil(15_000) { client.gets.size == 2 }
        awaitText("No collection matches “none”")
        compose.onNodeWithContentDescription("Search").performTextReplacement("demo")
        awaitText("Demo One")
        compose.onNodeWithContentDescription("Add Demo One").performClick()
        compose.onNodeWithContentDescription("Demo One").performClick()
        compose.onNodeWithContentDescription("Search").performTextReplacement("")
        reach("Gift recipients")
        compose.onNodeWithContentDescription("Add").performTextReplacement("Still usable")
        compose.onNodeWithContentDescription("Add").performImeAction()
        back()
        setup.client.failure = null
        open("Add to collections", "Collections and gifts")
        compose.waitForIdle()
        assertEquals(2, setup.client.gets.size)
        assertEquals(listOf("demo_one"), form.state.value.form!!.postedCollectionNames)
        assertEquals(listOf("Still usable"), form.state.value.form!!.gifts)
    }

    @Test fun allThemesAtAccessibilityScaleKeepEveryPickerAndItsWordsUnclipped() {
        scale = 2f
        show(995006L)
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode }
            for ((row, title, label) in listOf(Triple("Series", "Series", "Create a series from this work"),
                Triple("Add to collections", "Collections and gifts", "GIFT RECIPIENTS"),
                Triple("Co-creators", "Co-creators", "INVITE A CO-CREATOR"),
                Triple("Inspired by", "Inspired by", "This work is a translation"))) {
                open(row, title)
                reach(label)
                val matches = compose.onAllNodesWithText(label, useUnmergedTree = true)
                val count = matches.fetchSemanticsNodes().size
                assertTrue(count > 0)
                repeat(count) { index ->
                    val layouts = mutableListOf<TextLayoutResult>()
                    matches[index].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    assertTrue(layouts.isNotEmpty())
                    layouts.forEach { layout ->
                        assertFalse("$mode / $label", layout.didOverflowHeight)
                        if (layout.lineCount > 0) assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
                    }
                }
                back()
            }
        }
        assertEquals(0, setup.client.posts)
    }

    @Test fun manyCollectionRowsStayLazyAndSearchShowsNamesAfterAnAnswer() {
        show(995001L)
        compose.runOnIdle {
            repeat(150) { form.addCollection(AO3CollectionOffer("held_$it", "Long held collection $it 星")) }
        }
        open("Add to collections", "Collections and gifts")
        compose.onNodeWithContentDescription("Search").performTextReplacement("demo")
        awaitText("Demo Two")
        compose.onNodeWithContentDescription("Add Demo Two").assertIsDisplayed()
        compose.onNodeWithContentDescription("Search").assertIsDisplayed()
        assertTrue(compose.onAllNodesWithText("Long held collection", substring = true).fetchSemanticsNodes().size < 150)
    }
}
