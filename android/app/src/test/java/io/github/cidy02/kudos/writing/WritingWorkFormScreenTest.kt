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
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormField
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkSubmitAction
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
class WritingWorkFormScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var model: WritingWorkFormState
    private val chrome = PushedShellChrome()
    private var leaves = 0

    private fun show(id: Long? = null, mode: KudosThemeMode = KudosThemeMode.Light, scale: Float = 1f) {
        setup = runBlocking { workFormSetup() }
        model = setup.model(id)
        runBlocking { model.load() }
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingWorkFormContent(model, setup.auth.username().orEmpty(), if (id == null) "New work" else "Edit work", { leaves++ })
                    }
                }
            }
        }
    }
    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun reach(label: String) = compose.onNodeWithTag("Writing work form").performScrollToNode(hasText(label))
    private fun row(label: String, value: String) {
        reach(label)
        if (value.isEmpty()) compose.onNodeWithText(label).assertExists()
        else compose.onNode(hasText(label) and (hasText(value) or hasAnySibling(hasText(value)))).assertExists()
    }
    private fun noWrites() {
        assertEquals(1, setup.client.gets.size)
        assertEquals(0, setup.client.posts)
        assertNotNull(chrome.trailingContent)
    }

    private fun inventory(id: Long?) {
        show(id)
        val posted = id == 995006L
        awaitText(if (id == null) "Untitled · never posted" else if (posted) "The Cartographer’s \"Second\" Tide & 星 · 2 chapters"
            else "Lanterns Above the Mill · never posted")
        compose.onNodeWithText(if (id == null) "New work" else if (posted) "Edit work" else "Draft").assertExists()
        for (section in listOf(if (posted) "REQUIRED" else "REQUIRED BEFORE POSTING", "TAGS", "ASSOCIATION", "TEXT",
            if (posted) "PUBLICATION" else "WHEN POSTED")) {
            reach(section); compose.onNodeWithText(section).assertExists()
        }
        reach("Title ∗")
        compose.onNodeWithText("Title ∗").assertExists()
        row("Rating", if (id == null) "Please select a rating" else "Teen And Up Audiences")
        row("Archive warnings ∗", if (id == null) "None" else "1")
        row("Fandoms ∗", if (id == null) "None" else "2")
        row("Language", if (id == null) "Please select a language" else "English")
        row("Categories", if (id == null) "None" else "2")
        row("Relationships", if (id == null) "None" else "2")
        row("Characters", if (id == null) "None" else "2")
        row("Additional tags", if (id == null) "None" else "3")
        row("Series", if (posted) "Lantern Voyages" else "None")
        row("Add to collections", if (posted) "2" else "None")
        row("Gift recipients", if (posted) "1" else "None")
        row("Co-creators", "1")
        row("Inspired by", if (posted) "1" else "None")
        if (id == null) row("Summary", "Empty") else {
            reach("Summary")
            awaitText("A map for the tide, a promise for the night. 星 & light.")
        }
        row("Beginning notes", if (id == null) "Empty" else "Set")
        row("End notes", if (id == null) "Empty" else "Set")
        if (posted) {
            row("Chapters", "2")
            row("Add chapter", "")
            row("Edit tags", "")
        } else row("Work text", if (id == null) "Empty" else "Set")
        row("Work skin", if (posted) "Tidal Ink & 星" else "Default")
        if (posted) {
            reach("Chapters posted")
            compose.onNodeWithText("2 of").assertExists()
            compose.onNodeWithContentDescription("Chapter total").assertTextContains("5")
            compose.onNodeWithContentDescription("Work is complete").assertIsOff()
        }
        reach("Set a different publication date")
        if (posted) compose.onNodeWithContentDescription("Set a different publication date").assertIsOn()
        else compose.onNodeWithContentDescription("Set a different publication date").assertIsOff()
        compose.onNodeWithContentDescription("Only show to registered users").assertIsOff()
        if (posted) compose.onNodeWithContentDescription("Enable comment moderation").assertIsOn()
        else compose.onNodeWithContentDescription("Enable comment moderation").assertIsOff()
        row("Who can comment", if (posted) "Only registered users" else "Registered users and guests")
        // Posted fixture is metadata-only, despite served backdate inputs.
        compose.onNodeWithText("Publication date").assertDoesNotExist()
        for (omitted in listOf("Post work", "Preview on AO3", "Delete draft", "Delete work on AO3", "Chapter title", "Anonymous", "Collection inbox")) {
            compose.onNodeWithText(omitted).assertDoesNotExist()
        }
        noWrites()
    }
    @Test fun newFormHasIosSectionsRowsAndValues() = inventory(null)
    @Test fun draftFormHasIosSectionsRowsAndValues() = inventory(995001L)
    @Test fun postedFormHasIosSectionsRowsAndValues() = inventory(995006L)

    @Test fun chapterEntryHasAnActionWithoutSendingUntilOpened() {
        show(995006L)
        for (label in listOf("Add chapter")) { // Chapters opens its list since brief 3bm
            reach(label)
            compose.onNodeWithText(label).assertHasClickAction()
        }
        noWrites()
    }

    @Test fun titleAndServedSingleChoiceAndSwitchEditTheActualScreenStateWithoutAnotherRead() {
        show(995001L)
        val old = model.state.value.form!!
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Changed through screen")
        compose.onNodeWithText("Rating").performClick()
        awaitText("Mature")
        compose.onNodeWithText("Mature").performClick()
        reach("Only show to registered users")
        compose.onNodeWithContentDescription("Only show to registered users").performClick()
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.title to listOf("Changed through screen"),
            AO3WorkFormField.rating to listOf("Mature"), AO3WorkFormField.restricted to listOf("1")))
        noWrites()
    }

    @Test fun multipleChoicePushUsesOnlyServedOptionsAndBackKeepsTitleAndSelections() {
        show(995001L)
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Keep title")
        val old = model.state.value.form!!
        compose.onNodeWithText("Archive warnings ∗").performClick()
        awaitText("1 chosen")
        compose.onNodeWithText("CHOOSE").assertExists()
        for (option in old.warningOptions) compose.onNodeWithText(option.title).assertExists()
        compose.onNodeWithText("Major Character Death").performClick()
        awaitText("2 chosen")
        compose.runOnIdle { chrome.onBack!!.invoke() }
        awaitText("Keep title · never posted")
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.warnings to listOf("No Archive Warnings Apply", "Major Character Death")))
        noWrites()
    }

    @Test fun publicationDateFollowsIosBindings() {
        show(995001L)
        val old = model.state.value.form!!
        reach("Set a different publication date")
        compose.onNodeWithContentDescription("Set a different publication date").performClick()
        row("Publication date", old.publicationDate().format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM)))
        compose.onNodeWithText("Publication date").performClick()
        awaitText("Year")
        compose.onNodeWithText("Year").performClick()
        awaitText("2024")
        compose.onNodeWithText("2024").performClick()
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.backdate to listOf("1"),
            AO3WorkFormField.chapterPublishedYear to listOf("2024"), AO3WorkFormField.chapterPublishedMonth to listOf("10"),
            AO3WorkFormField.chapterPublishedDay to listOf("5")))
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun postedTotalAndCompleteAreEditableWithNoChapterRead() {
        show(995006L)
        reach("Work is complete")
        val old = model.state.value.form!!
        compose.onNodeWithContentDescription("Work is complete").performClick()
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.wipLength to listOf("2")))
        compose.onNodeWithContentDescription("Chapter total").performTextReplacement("9")
        compose.onNodeWithContentDescription("Work is complete").assertIsOff()
        assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.wipLength to listOf("9")))
        noWrites()
    }

    @Test fun editorDoneAndBackReturnExactTextAndNeverReloadForm() {
        show(995001L)
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Kept while editing")
        val old = model.state.value.form!!
        reach("Work text")
        compose.onNodeWithText("Work text").performClick()
        awaitText("Recovery copy on this device · Save from the work form")
        compose.onNodeWithContentDescription("Bold").performClick()
        compose.onNodeWithContentDescription("Done").performClick()
        awaitText("Kept while editing · never posted")
        val done = model.state.value.form!!
        assertDelta(old, done, mapOf(AO3WorkFormField.chapterContent to listOf("<strong></strong>" + old.chapter!!.content)))
        reach("Work text")
        compose.onNodeWithText("Work text").performClick()
        awaitText("Recovery copy on this device · Save from the work form")
        compose.onNodeWithContentDescription("Italic").performClick()
        compose.runOnIdle { chrome.onBack!!.invoke() }
        awaitText("Kept while editing · never posted")
        assertDelta(done, model.state.value.form!!, mapOf(AO3WorkFormField.chapterContent to listOf("<em></em>" + done.chapter!!.content)))
        noWrites()
    }

    @Test fun leavingHasNoUnsavedDialogOrWrite() {
        show()
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Unsaved")
        compose.runOnIdle { chrome.onBack!!.invoke() }
        assertEquals(1, leaves)
        compose.onNodeWithText("Discard changes?").assertDoesNotExist()
        noWrites()
    }

    private fun largeTheme(mode: KudosThemeMode) {
        show(995006L, mode, 2f)
        val saveLayouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("Save").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(saveLayouts) }
        assertTrue(saveLayouts.isNotEmpty())
        assertTrue(saveLayouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        for (label in listOf("Fandoms ∗", "Series", "Chapters posted", "Set a different publication date", "Only show to registered users", "Enable comment moderation")) {
            reach(label)
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(label).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            // Not hasVisualOverflow: a short label narrower than its row reports a width overflow it does not have.
            assertTrue("$mode / $label", layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        }
        reach("Who can comment")
        compose.onNodeWithText("Who can comment").assertExists()
        noWrites()
        val reason = "Title is too long (maximum is 255 characters)"
        compose.runOnIdle { setup.client.postBody = "<main id=main><div id=error><ul><li>$reason</li></ul></div></main>" }
        compose.onNodeWithText("Save").performClick()
        awaitText("AO3 could not save the change")
        for (text in listOf("AO3 could not save the change", reason, "OK")) {
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(text).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue(layouts.isNotEmpty())
            assertTrue("$mode / alert / $text", layouts.all { !it.didOverflowHeight && !it.isLineEllipsized(it.lineCount - 1) })
        }
        assertEquals(1, setup.client.posts); assertEquals(0, leaves)
    }
    @Test fun lightAccessibilityTextWraps() = largeTheme(KudosThemeMode.Light)
    @Test fun darkAccessibilityTextWraps() = largeTheme(KudosThemeMode.Dark)
    @Test fun sepiaAccessibilityTextWraps() = largeTheme(KudosThemeMode.Sepia)
    @Test fun oledAccessibilityTextWraps() = largeTheme(KudosThemeMode.Oled)

    private fun saveEditedForm(id: Long?) {
        show(id)
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("  Screen title & 星  ")
        val before = model.state.value.form!!
        compose.onNodeWithText("Save").assertIsEnabled().performClick()
        compose.waitUntil(15_000) { leaves == 1 }
        val submit = if (id == 995006L) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft
        assertEquals(before.parameters(submit), setup.client.recordedPosts.single().fields)
        assertEquals(iosFixtureSaveFields(id, title = "  Screen title & 星  "), setup.client.recordedPosts.single().fields)
        assertEquals(listOf("  Screen title & 星  "), setup.client.recordedPosts.single().fields
            .filter { it.first == AO3WorkFormField.title }.map { it.second })
        assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
    }
    @Test fun newWorkSavePostsTheActualEditedScreenFormAndCloses() = saveEditedForm(null)
    @Test fun draftSavePostsTheActualEditedScreenFormAndCloses() = saveEditedForm(995001L)
    @Test fun postedSavePostsTheActualEditedScreenFormAndCloses() = saveEditedForm(995006L)

    @Test fun saveDisablesInFlightAndSecondTapSendsNothingThenClosesOnlyOnConfirmation() {
        show(995001L)
        val release = CompletableDeferred<Unit>()
        compose.runOnIdle { setup.client.beforePostResponse = { release.await() } }
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { setup.client.posts == 1 }
        compose.onNodeWithText("Save").assertIsNotEnabled().performClick()
        compose.runOnIdle { assertEquals(0, leaves); assertEquals(1, setup.client.posts) }
        compose.runOnIdle { release.complete(Unit) }
        compose.waitUntil(15_000) { leaves == 1 }
        assertEquals(1, setup.client.posts)
    }

    @Test fun refusedSaveKeepsTheTypedFormWithIosAlertAndAo3Reason() {
        show(995001L)
        compose.runOnIdle {
            setup.client.postBody = "<main id=main><div id=error><ul><li>Title is too long (maximum is 255 characters)</li></ul></div></main>"
            setup.client.postStatus = 422
        }
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Keep this title")
        compose.onNodeWithText("Save").performClick()
        awaitText("AO3 could not save the change")
        compose.onNodeWithText("Title is too long (maximum is 255 characters)").assertExists()
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithContentDescription("Title ∗").assertTextContains("Keep this title")
        assertEquals(0, leaves); assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
    }

    @Test fun unconfirmedSaveKeepsTheFormAndShowsIosWords() {
        show()
        compose.runOnIdle { setup.client.postBody = "<main id=main></main>" }
        compose.onNodeWithText("Save").performClick()
        awaitText("AO3 could not save the change")
        compose.onNodeWithText("AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.").assertExists()
        assertEquals(0, leaves); assertEquals(1, setup.client.posts)
    }

    @Test fun multiChapterDraftHasNoWorkTextRowAndSaveSendsNoContent() {
        setup = runBlocking { workFormSetup() }
        val doc = org.jsoup.Jsoup.parse(io.github.cidy02.kudos.network.ao3.writing.workFixture("ao3_demo_work_draft_edit"))
        doc.select("textarea[name='work[chapter_attributes][content]']").remove()
        setup.client.body = doc.outerHtml()
        model = setup.model(995001L)
        runBlocking { model.load() }
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                Column {
                    Row { chrome.trailingContent?.invoke(this) }
                    WritingWorkFormContent(model, model.account, "Edit work", { leaves++ })
                }
            }
        } }
        reach("Work skin")
        compose.onNodeWithText("Work text").assertDoesNotExist()
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { leaves == 1 }
        assertTrue(setup.client.recordedPosts.single().fields.none { it.first == AO3WorkFormField.chapterContent })
    }

    @Test fun realWrapperKeepsTypedFieldsWhenTheSessionChangesDuringSave() {
        setup = runBlocking { workFormSetup() }
        val release = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = { release.await() }
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                Column {
                    Row { chrome.trailingContent?.invoke(this) }
                    WritingWorkFormScreen(995001L, setup.repository, setup.auth, { leaves++ }, writeRepository = setup.writes)
                }
            }
        } }
        awaitText("Lanterns Above the Mill · never posted")
        compose.onNodeWithContentDescription("Title ∗").performTextReplacement("Retained on session failure")
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { setup.client.posts == 1 }
        compose.runOnIdle { runBlocking { setup.auth.logout() }; release.complete(Unit) }
        awaitText("AO3 could not save the change")
        compose.onNodeWithText(WORK_FORM_SESSION_CHANGED).assertExists()
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithContentDescription("Title ∗").assertTextContains("Retained on session failure")
        assertEquals(0, leaves); assertEquals(1, setup.client.posts); assertEquals(1, setup.client.gets.size)
    }

    private fun showLoader(signedIn: Boolean = true, hold: CompletableDeferred<Unit>? = null, error: AO3Error? = null) {
        setup = runBlocking { workFormSetup(signedIn) }
        setup.client.beforeResponse = { hold?.await() }
        setup.client.failure = error
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    WritingWorkFormScreen(null, setup.repository, setup.auth, { leaves++ }, writeRepository = setup.writes)
                }
            }
        }
    }
    @Test fun realScreenLoadingFailureAndRetryUseOneReadEachAndIosWords() {
        val release = CompletableDeferred<Unit>()
        showLoader(hold = release, error = AO3Error.Overloaded(503, null))
        awaitText("New work")
        compose.onNodeWithText("REQUIRED BEFORE POSTING").assertDoesNotExist()
        compose.runOnIdle { release.complete(Unit) }
        awaitText("Couldn't load from AO3")
        compose.onNodeWithText("AO3 had a server problem (HTTP 503). Try again shortly.").assertExists()
        compose.runOnIdle { setup.client.failure = null }
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Untitled · never posted")
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }
    @Test fun realSignedOutScreenReadsNothingAndOffersNoSignInAction() {
        showLoader(signedIn = false)
        awaitText("Log in to AO3 first.")
        compose.onNodeWithText("Try Again").performClick()
        compose.waitForIdle()
        assertTrue(setup.client.gets.isEmpty()); assertEquals(0, setup.client.posts)
    }
    @Test fun realLogoutRemovesThePrivateFormAndCannotReadAgain() {
        showLoader()
        awaitText("Untitled · never posted")
        compose.runOnIdle { runBlocking { setup.auth.logout() } }
        awaitText("Log in to AO3 first.")
        compose.onNodeWithText("REQUIRED BEFORE POSTING").assertDoesNotExist()
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }
}
