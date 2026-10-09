package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.*
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
class WritingWorkActionsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var model: WritingWorkFormState
    private val chrome = PushedShellChrome()
    private var leaves = 0

    private fun show(id: Long? = 995001, mode: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f,
        wrapper: Boolean = false) {
        setup = runBlocking { workFormSetup() }
        model = setup.model(id)
        if (!wrapper) runBlocking<Unit> { model.load() }
        compose.setContent { KudosTheme(mode) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalPushedShellChrome provides chrome, LocalDensity provides Density(density.density, scale)) {
                Column {
                    Row { chrome.trailingContent?.invoke(this) }
                    if (wrapper) WritingWorkFormScreen(id, setup.repository, setup.auth, { leaves++ }, writeRepository = setup.writes)
                    else WritingWorkFormContent(model, model.account, "New work", { leaves++ })
                }
            }
        } }
        awaitText(if (id == null) "Untitled · never posted" else if (id == 995006L)
            "The Cartographer’s \"Second\" Tide & 星 · 2 chapters" else "Lanterns Above the Mill · never posted")
    }
    private fun awaitText(text: String) {
        compose.waitForIdle()
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun reach(text: String, tag: String = "Writing work form") =
        compose.onNodeWithTag(tag).performScrollToNode(hasText(text))
    private fun confirmPost() {
        awaitText("Post this work?")
        compose.onNode(hasText("Post work") and hasAnyAncestor(isDialog())).performClick()
    }
    private fun noClip(text: String) {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { assertFalse(it.didOverflowHeight); assertFalse(it.isLineEllipsized(it.lineCount - 1)) }
    }

    @Test fun newMissingRequiredFieldsUseIosWordsWithoutSendingAnything() {
        show(null)
        reach("Post work"); compose.onNodeWithText("Post work").performClick()
        awaitText("Fill in what is missing")
        compose.onNodeWithText(workPostConfirmation(listOf("Title", "Rating", "Archive Warning", "Fandoms", "Language", "Work Text"))).assertExists()
        compose.onNodeWithText("Fill in what is missing").performClick()
        assertEquals(0, setup.client.posts); assertEquals(1, setup.client.gets.size)
        compose.onNodeWithText("Delete draft").assertDoesNotExist()
        assertEquals("One thing is missing. Add a title. AO3 requires it. Posting also notifies your subscribers and can't be undone. You can edit a posted work, but you can't return it to a draft.", workPostConfirmation(listOf("Title")))
        assertTrue(workPostConfirmation(listOf("Title", "Rating")).startsWith("Two things are missing. Add a title and a rating. AO3 requires both."))
    }

    @Test fun draftPostAsksThenRefusalKeepsAllTypedFieldsAndDoesNotClose() {
        show()
        compose.onNodeWithContentDescription("Title, required").performTextReplacement("Typed private title")
        compose.runOnIdle { setup.client.postBody = "<main id=main><div class='flash error'>This draft could not be posted.</div></main>" }
        reach("Post work"); compose.onNodeWithText("Post work").performClick()
        awaitText("Post this work?")
        compose.onNodeWithText(workPostConfirmation(emptyList())).assertExists()
        assertEquals(0, setup.client.posts)
        confirmPost(); awaitText("AO3 could not save the change")
        compose.onNodeWithText("This draft could not be posted.").assertExists()
        compose.onNodeWithText("OK").performClick()
        reach("Title ∗"); compose.onNodeWithText("Typed private title").assertExists()
        assertEquals(0, leaves); assertEquals(1, setup.client.posts)
        assertEquals(listOf("post_button" to "1"), setup.client.recordedPosts.single().fields.filter { it.first.endsWith("_button") })
    }

    @Test fun postedWorkHasOnlyDeleteAndShowsAo3CautionCountsThenClosesOnConfirmation() {
        show(995006)
        compose.runOnIdle { prepareDeletePages(setup, 995006) }
        reach("Delete work on AO3")
        compose.onNodeWithText("Post work").assertDoesNotExist(); compose.onNodeWithText("Preview on AO3").assertDoesNotExist()
        compose.onNodeWithText("Delete work on AO3").performClick()
        awaitText("Delete this work?")
        compose.onNodeWithText(workDeleteCaution).assertExists(); assertEquals(0, setup.client.posts)
        compose.onNodeWithText("Delete on AO3").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { leaves == 1 }
        assertEquals(1, setup.client.posts); assertEquals(3, setup.client.gets.size)
    }

    @Test fun newPreviewIsPushedWithItsOwnChromeAndEditThenSaveUpdatesTheCreatedDraft() {
        show(null)
        compose.runOnIdle { setup.client.postBody = workPreviewHtml(995007) }
        reach("Preview on AO3"); compose.onNodeWithText("Preview on AO3").performClick()
        awaitText("Draft was successfully created."); awaitText("Preview")
        compose.onNodeWithTag("Writing work preview").assertExists()
        assertNull(chrome.trailingContent)
        reach("Edit", "Writing work preview"); compose.onNodeWithText("Edit").performClick()
        awaitText("Save"); reach("Delete draft"); compose.onNodeWithText("Delete draft").assertExists()
        compose.runOnIdle { setup.client.postBody = "<main id=main><div class='flash notice'>Draft was successfully saved.</div></main>" }
        compose.onNodeWithText("Save").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { leaves == 1 }
        assertEquals(listOf("https://archiveofourown.org/works", "https://archiveofourown.org/works/995007"), setup.client.recordedPosts.map { it.url })
        assertEquals(1, setup.client.gets.size)
    }

    @Test fun previewPostUsesItsOwnConfirmationAndErrorTitleAndKeepsPreviewOnRefusal() {
        show()
        compose.runOnIdle { setup.client.postBody = workPreviewHtml(995001) }
        reach("Preview on AO3"); compose.onNodeWithText("Preview on AO3").performClick(); awaitText("Draft was successfully created.")
        reach("Post work", "Writing work preview")
        compose.runOnIdle { setup.client.postBody = "<main id=main><div class='flash error'>AO3 refuses this post.</div></main>" }
        compose.onNodeWithText("Post work").performClick(); confirmPost()
        awaitText("AO3 could not post this"); compose.onNodeWithText("AO3 refuses this post.").assertExists()
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithTag("Writing work preview").assertExists(); assertEquals(0, leaves)
        assertEquals(2, setup.client.posts)
    }

    @Test fun failedPreviewAndDeleteKeepFieldsAndLongPreviewLaysOutParagraphsLazily() {
        show()
        compose.runOnIdle { setup.client.postBody = "<main id=main><div class='flash notice'>A notice is no pane.</div></main>" }
        reach("Preview on AO3"); compose.onNodeWithText("Preview on AO3").performClick()
        awaitText(CHAPTER_PREVIEW_UNAVAILABLE); compose.onNodeWithText("OK").performClick()
        compose.runOnIdle {
            setup.client.postBody = workPreviewHtml(995001).replace("<p>Another paragraph.</p>", (0..999).joinToString("") { "<p>Paragraph $it.</p>" })
        }
        reach("Preview on AO3"); compose.onNodeWithText("Preview on AO3").performClick(); awaitText("Draft was successfully created.")
        // The rows are built off the main thread; the notice is on screen before them.
        awaitText("Preview title")
        assertTrue(compose.onAllNodesWithText("Paragraph", substring = true).fetchSemanticsNodes().size in 1..99)
        reach("Paragraph 999.", "Writing work preview"); awaitText("Paragraph 999.")
        reach("Edit", "Writing work preview"); compose.onNodeWithText("Edit").performClick()
        compose.runOnIdle { prepareDeletePages(setup, 995001); setup.client.postBody = "<main id=main></main>" }
        reach("Delete draft"); compose.onNodeWithText("Delete draft").performClick(); awaitText("Delete this draft?")
        compose.onNodeWithText("Delete", useUnmergedTree = true).performClick()
        awaitText(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED)
        compose.onNodeWithText("OK").performClick(); assertEquals(0, leaves)
        reach("Title ∗"); compose.onNodeWithText("Lanterns Above the Mill").assertExists()
    }

    @Test fun realWrapperRetainsItsOpeningFormDuringPostSessionFailureAndIgnoresSecondTap() {
        show(wrapper = true)
        val release = CompletableDeferred<Unit>()
        compose.runOnIdle { setup.client.beforePostResponse = { release.await() } }
        compose.onNodeWithContentDescription("Title, required").performTextReplacement("Retained across sessions")
        reach("Post work"); compose.onNodeWithText("Post work").performClick(); confirmPost()
        compose.waitForIdle(); compose.waitUntil(15_000) { setup.client.posts == 1 }
        compose.onNodeWithText("Post work").assertIsNotEnabled().performClick()
        compose.runOnIdle { runBlocking<Unit> { setup.auth.logout() }; release.complete(Unit) }
        awaitText(io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields.UNCONFIRMED); compose.onNodeWithText("OK").performClick()
        reach("Title ∗"); compose.onNodeWithText("Retained across sessions").assertExists()
        assertEquals(0, leaves); assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
    }

    private fun theme(mode: KudosThemeMode, scale: Float) {
        show(mode = mode, scale = scale)
        reach("Post work"); noClip("Post work"); noClip("Preview on AO3"); noClip("Delete draft")
        compose.runOnIdle { prepareDeletePages(setup, 995001) }
        compose.onNodeWithText("Delete draft").performClick(); awaitText("Delete this draft?")
        noClip("Delete this draft?"); noClip(workDeleteCaution); noClip("Delete"); noClip("Cancel")
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle { setup.client.postBody = workPreviewHtml(995001) }
        reach("Preview on AO3"); compose.onNodeWithText("Preview on AO3").performClick(); awaitText("Draft was successfully created.")
        noClip("Preview"); reach("Edit", "Writing work preview"); noClip("Edit"); noClip("Post work")
    }
    @Test fun lightActionsAndPreviewAtNormalText() = theme(KudosThemeMode.Light, 1f)
    @Test fun darkActionsAndPreviewAtLargeText() = theme(KudosThemeMode.Dark, 2f)
    @Test fun sepiaActionsAndPreviewAtLargeText() = theme(KudosThemeMode.Sepia, 2f)
    @Test fun oledActionsAndPreviewAtLargeText() = theme(KudosThemeMode.Oled, 2f)
}
