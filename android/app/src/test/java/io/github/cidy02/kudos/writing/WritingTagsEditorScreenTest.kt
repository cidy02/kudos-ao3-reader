package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.nio.file.Files
import java.io.File
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.*
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingTagsEditorScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var form: WritingWorkFormState
    private val tags = WritingTagTestClient()
    private val chrome = PushedShellChrome()
    private val repository = AO3TagAutocompleteRepository(tags)
    private val temporary = Files.createTempDirectory("writing-tags-ui").toFile()
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
        produceFile = { File(temporary, "settings.preferences_pb") }))
    @After fun cleanUp() { settingsScope.cancel(); temporary.deleteRecursively() }
    private var mounted by mutableStateOf(true)

    private fun show(id: Long?, mode: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f, withRecents: Boolean = false) {
        setup = runBlocking { workFormSetup() }
        form = setup.model(id)
        runBlocking { form.load() }
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    if (mounted) Column {
                        WritingWorkFormContent(form, setup.auth.username().orEmpty(), "New work", {}, repository, if (withRecents) settings else null)
                    }
                }
            }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("Writing work form").fetchSemanticsNodes().isNotEmpty() }
    }
    private fun reach(label: String) = compose.onNodeWithTag("Writing work form").performScrollToNode(hasText(label))
    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun open(kind: WritingTagKind) {
        val label = if (kind == WritingTagKind.Fandom) "Fandoms ∗" else kind.title
        reach(label)
        compose.onNodeWithText(label).assertHasClickAction().performClick()
        awaitText(kind.title)
        compose.onNodeWithTag("Writing tags editor").assertExists()
        compose.onNodeWithText("EDIT TAGS").assertExists()
        compose.onNodeWithText(writingTagSubtitle(kind.values(form.state.value.form!!))).assertExists()
        compose.onNodeWithContentDescription("Add a tag").assertExists()
        compose.onNodeWithText("Done").assertDoesNotExist() // The reference has Back only.
        assertNull(chrome.trailingContent)
    }
    private fun back() { compose.runOnIdle { chrome.onBack!!.invoke() }; compose.waitForIdle() }

    private fun editEveryKind(id: Long?) {
        show(id)
        for (kind in WritingTagKind.entries) {
            val old = form.state.value.form!!
            val original = kind.values(old)
            val reads = tags.gets.size
            open(kind)
            compose.waitForIdle(); assertEquals(reads, tags.gets.size) // Nothing on opening.
            compose.onNodeWithContentDescription("Add a tag").performTextReplacement("  First 星  ")
            compose.onNodeWithContentDescription("Add a tag").performImeAction()
            compose.waitForIdle()
            assertEquals(original + "First 星", kind.values(form.state.value.form!!))
            compose.onNodeWithContentDescription("Add a tag").performTextReplacement("paste A, paste B,")
            compose.waitForIdle()
            assertEquals(original + "First 星", kind.values(form.state.value.form!!))
            compose.onNodeWithContentDescription("Add a tag").performImeAction()
            compose.waitForIdle()
            assertEquals(original + listOf("First 星", "paste A, paste B,"), kind.values(form.state.value.form!!))
            // Exact duplicate leaves the field; no extra chosen chip.
            compose.onNodeWithContentDescription("Add a tag").performTextReplacement(" First 星 ")
            compose.onNodeWithContentDescription("Add a tag").performImeAction()
            compose.onNodeWithContentDescription("Add a tag").assertTextContains(" First 星 ")
            compose.onNodeWithContentDescription("Clear").performClick()
            compose.onNodeWithTag("Writing tags editor").performScrollToNode(hasContentDescription("Remove First 星"))
            compose.onNodeWithContentDescription("Remove First 星").performClick()
            compose.waitForIdle()
            assertEquals(original + "paste A, paste B,", kind.values(form.state.value.form!!))
            // Real autocomplete repository, wholly in-memory client.
            compose.onNodeWithContentDescription("Add a tag").performTextReplacement("demo")
            awaitText("Demo Second")
            compose.onNodeWithContentDescription("Add Demo Second").performClick()
            compose.waitForIdle()
            val expected = original + listOf("paste A, paste B,", "Demo Second")
            assertEquals(expected, kind.values(form.state.value.form!!))
            back()
            assertDelta(old, form.state.value.form!!, mapOf(kind.formField() to listOf(expected.joinToString(", "))))
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts); assertEquals(0, tags.posts)
        }
    }
    @Test fun newRouteFormOpensAllFourEditorsAndHandsChangesBack() = editEveryKind(null)
    @Test fun draftRouteFormOpensAllFourEditorsAndHandsChangesBack() = editEveryKind(995001L)
    @Test fun postedRouteFormOpensAllFourEditorsAndHandsChangesBack() = editEveryKind(995006L)

    @Test fun typedRowCanonicalBadgesEmptyAndFailedResponsesKeepTheFieldEditable() {
        show(null); open(WritingTagKind.Freeform)
        compose.onNodeWithText("SUGGESTIONS").assertDoesNotExist()
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("demo")
        awaitText("Demo Third")
        compose.onNodeWithContentDescription("Add demo").assertExists()
        compose.onAllNodesWithText("Canonical").assertCountEquals(3)
        compose.onNodeWithText("Posts as typed").assertExists()
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("none")
        compose.waitUntil(15_000) {
            tags.gets.any { it.contains("term=none") } && compose.onAllNodesWithText("Canonical").fetchSemanticsNodes().isEmpty()
        }
        compose.onNodeWithContentDescription("Add none").assertExists()
        compose.onNodeWithText("Posts as typed").assertExists()
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("fail")
        awaitText(WritingTagFailure)
        compose.onNodeWithContentDescription("Add fail").performClick()
        compose.waitForIdle()
        assertEquals(listOf("fail"), form.state.value.form!!.additionalTags)
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("can still type")
        compose.onNodeWithContentDescription("Add a tag").performImeAction()
        compose.waitForIdle()
        assertEquals(listOf("fail", "can still type"), form.state.value.form!!.additionalTags)
        compose.onNodeWithTag("Writing tags editor").performScrollToNode(hasText(WritingTagFootnote))
        compose.onNodeWithText(WritingTagFootnote).assertExists()
        assertEquals(0, tags.posts)
    }

    @OptIn(androidx.compose.ui.test.ExperimentalTestApi::class)
    @Test fun accessibilityReorderChangesPayloadInBothDirectionsAndWaitingRowsStayInert() {
        show(995006L)
        open(WritingTagKind.Fandom)
        val old = form.state.value.form!!
        val first = old.fandoms.first()
        val chosen = compose.onNodeWithContentDescription(first)
        chosen.performCustomAccessibilityActionWithLabel("Move Later")
        compose.waitForIdle()
        assertEquals(old.fandoms.reversed(), form.state.value.form!!.fandoms)
        compose.onNodeWithContentDescription(first).performCustomAccessibilityActionWithLabel("Move Earlier")
        compose.waitForIdle()
        assertEquals(old.fandoms, form.state.value.form!!.fandoms)
        back()
        for (label in listOf("Series", "Add to collections", "Gift recipients", "Co-creators", "Inspired by", "Chapters", "Add chapter", "Edit tags")) {
            reach(label); compose.onNodeWithText(label).assertHasNoClickAction()
        }
        assertEquals(0, setup.client.posts); assertEquals(0, tags.posts)
    }

    @Test fun closingCancelsAHeldReadAndUnsubmittedTextNeverChangesTheForm() {
        show(null); open(WritingTagKind.Character)
        var cancelled = false
        tags.beforeResponse = { try { awaitCancellation() } finally { cancelled = true } }
        val before = form.state.value.form!!
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("held")
        compose.waitUntil(15_000) { tags.gets.isNotEmpty() }
        compose.runOnIdle { mounted = false }
        compose.waitUntil(15_000) { cancelled }
        assertEquals(before, form.state.value.form)
        assertEquals(1, tags.gets.size); assertEquals(0, tags.posts)
    }

    @Test fun recentTagsAddWithoutAReadHideChosenSpellingsAndSurviveEditorReopening() {
        runBlocking {
            settings.recordWritingTag("freeform", "Fluff")
            settings.recordWritingTag("freeform", "Angst")
            settings.recordWritingTag("fandom", "Other kind")
        }
        show(null, withRecents = true)
        compose.runOnIdle { form.writingTags(WritingTagKind.Freeform, listOf("fluff")) }
        open(WritingTagKind.Freeform)
        awaitText("RECENTLY USED")
        compose.onNodeWithContentDescription("Add Fluff").assertDoesNotExist()
        compose.onNodeWithContentDescription("Add Other kind").assertDoesNotExist()
        compose.onNodeWithContentDescription("Add Angst").performClick()
        compose.waitForIdle()
        assertEquals(listOf("fluff", "Angst"), form.state.value.form!!.additionalTags)
        compose.onNodeWithText("RECENTLY USED").assertDoesNotExist()
        assertTrue(tags.gets.isEmpty())
        back()
        open(WritingTagKind.Freeform)
        compose.onNodeWithContentDescription("Remove Angst").performClick()
        awaitText("RECENTLY USED")
        compose.onNodeWithContentDescription("Add Angst").assertExists()
        assertTrue(tags.gets.isEmpty()); assertEquals(0, tags.posts)
    }

    @Test fun draggingOntoTheLastChipPostsItLastWithoutRemovingIt() {
        show(null)
        compose.runOnIdle { form.writingTags(WritingTagKind.Relationship, listOf("A/B", "C/D", "E/F")) }
        open(WritingTagKind.Relationship)
        val first = compose.onNodeWithContentDescription("A/B").fetchSemanticsNode().boundsInRoot.center
        val last = compose.onNodeWithContentDescription("E/F").fetchSemanticsNode().boundsInRoot.center
        compose.onRoot().performTouchInput {
            down(first)
            advanceEventTime(650)
            moveTo(last, delayMillis = 100)
            up()
        }
        compose.waitForIdle()
        assertEquals(listOf("C/D", "E/F", "A/B"), form.state.value.form!!.relationships)
        assertEquals(0, tags.posts)
    }

    @Test fun longChosenListsAreLazyAndTypingBringsSuggestionsBelowThePinnedField() {
        show(null)
        compose.runOnIdle { form.writingTags(WritingTagKind.Freeform, List(150) { "Chosen tag $it" }) }
        open(WritingTagKind.Freeform)
        compose.onNodeWithContentDescription("Remove Chosen tag 149").assertDoesNotExist()
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("demo")
        awaitText("Demo First")
        compose.onNodeWithContentDescription("Add a tag").assertIsDisplayed()
        compose.onNodeWithContentDescription("Add Demo First").assertIsDisplayed()
        compose.onNodeWithText("SUGGESTIONS").assertIsDisplayed()
        val input = compose.onNodeWithContentDescription("Add a tag").fetchSemanticsNode().boundsInRoot
        val suggestion = compose.onNodeWithContentDescription("Add Demo First").fetchSemanticsNode().boundsInRoot
        assertTrue(suggestion.top >= input.bottom)
        assertEquals(150, form.state.value.form!!.additionalTags.size)
        assertEquals(0, tags.posts)
    }

    private fun largeText(mode: KudosThemeMode) {
        show(null, mode, 2f)
        val long = "Long chosen tag with spaces and 星 ".repeat(6).trim()
        compose.runOnIdle { form.writingTags(WritingTagKind.Freeform, listOf(long)) }
        open(WritingTagKind.Freeform)
        compose.onNodeWithTag("Writing tags editor").performScrollToNode(hasContentDescription("Remove $long"))
        assertTextFits(compose.onNodeWithText(long, useUnmergedTree = true))
        compose.onNodeWithContentDescription("Remove $long").assertIsDisplayed()
        compose.onNodeWithContentDescription("Add a tag").performTextReplacement("a long typed name with several words and 星")
        awaitText("Posts as typed")
        val term = "a long typed name with several words and 星"
        assertTextFits(compose.onNode(hasText(term) and hasAnyAncestor(hasContentDescription("Add $term")), useUnmergedTree = true))
        compose.onNodeWithTag("Writing tags editor").performScrollToNode(hasText(WritingTagFootnote))
        assertTextFits(compose.onNodeWithText(WritingTagFootnote, useUnmergedTree = true))
    }
    private fun assertTextFits(node: SemanticsNodeInteraction) {
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { layout ->
            assertFalse(layout.didOverflowHeight)
            assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
        }
    }
    @Test fun lightAtAccessibilityScaleWrapsLongChipsSuggestionsAndFootnote() = largeText(KudosThemeMode.Light)
    @Test fun darkAtAccessibilityScaleWrapsLongChipsSuggestionsAndFootnote() = largeText(KudosThemeMode.Dark)
    @Test fun sepiaAtAccessibilityScaleWrapsLongChipsSuggestionsAndFootnote() = largeText(KudosThemeMode.Sepia)
    @Test fun oledAtAccessibilityScaleWrapsLongChipsSuggestionsAndFootnote() = largeText(KudosThemeMode.Oled)
}
