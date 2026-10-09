package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
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
class WritingChapterFormScreenTest {
    @get:Rule val compose = createComposeRule()
    private val chrome = PushedShellChrome()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var model: WritingChapterFormState
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)
    private var closes = 0
    private var changes = 0
    private fun show(kind: String = "new", failure: AO3Error? = null, count: Int? = null) {
        setup = runBlocking { workFormSetup() }
        setup.client.body = workFixture("ao3_demo_chapter_995006_$kind")
        setup.client.failure = failure
        model = WritingChapterFormState(995006, if (kind == "new") null else 12302, count, setup.repository, setup.auth, writes = setup.writes)
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingChapterFormScreen(model, "Tide & 星", onSaved = { changes++ }, onBack = { closes++ })
                    }
                }
            }
        }
        compose.waitForIdle()
        awaitText(if (failure == null) "Title" else "Try Again")
    }
    private fun awaitText(text: String) {
        compose.waitForIdle()
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun reach(text: String) = compose.onNodeWithTag("Writing chapter form").performScrollToNode(hasText(text))
    private fun back() { compose.runOnIdle { chrome.onBack!!.invoke() }; compose.waitForIdle() }

    @Test fun sectionsPositionAndDateEditCollectedStateAndNoCreatorRowIsInvented() {
        show()
        // The four section titles are drawn in capitals (the shared section header does that).
        for (text in listOf("CHAPTER", "TEXT", "PUBLICATION", "POST", "Chapter text", "Summary", "Beginning notes", "End notes", "This is the last chapter")) {
            reach(text); compose.onNodeWithText(text).assertExists()
        }
        compose.onAllNodesWithText("Co-creators").assertCountEquals(0)
        reach("Title"); compose.onNodeWithContentDescription("Title").performTextReplacement("New midnight tide")
        compose.onNodeWithTag("Position, after chapter").performTextReplacement("12")
        compose.onNodeWithTag("Expected chapter total").performTextReplacement("17")
        compose.waitForIdle()
        assertEquals("13", model.state.value.form!!.position); assertEquals("17", model.state.value.form!!.wipLength)
        assertEquals("New midnight tide", model.state.value.form!!.title)
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        reach("This is the last chapter"); compose.onNodeWithContentDescription("This is the last chapter").performClick()
        compose.waitForIdle(); assertTrue(model.state.value.isLastChapter)
        assertEquals("13", model.state.value.form!!.position)
    }

    @Test fun everyTextRowOpensTheCorrectEditorAndBackKeepsItsCheckpointWithoutReads() {
        show("draft", count = 2)
        for (field in ChapterFormText.entries) {
            reach(field.title); compose.onNodeWithText(field.title).performClick()
            awaitText("Recovery copy on this device · Save from the work form")
            compose.onNodeWithText(field.title).assertExists()
            assertNotNull(chrome.trailingContent) // The editor restores its own toolbar.
            val original = field.text(model.state.value.form!!)
            compose.onNodeWithContentDescription("Bold").performClick()
            back(); awaitText("Edit chapter")
            assertEquals("<strong></strong>" + original, field.text(model.state.value.form!!))
            assertNull(chrome.trailingContent) // Chapter form has no top Save action on iOS.
        }
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun draftSaveClosesOnlyOnConfirmationAndRefusalKeepsTypedTitleAndAllFields() {
        show("draft")
        setup.client.postBody = "<main id=main><div id=error><ul><li>Title is too long</li></ul></div></main>"
        reach("Title"); compose.onNodeWithContentDescription("Title").performTextReplacement("Keep this title")
        val before = model.state.value.form
        reach("Save as draft"); compose.onNodeWithText("Save as draft").performClick()
        awaitText("AO3 could not save the chapter"); compose.onNodeWithText("Title is too long").assertExists()
        assertEquals(before, model.state.value.form); assertEquals(0, closes); assertEquals(0, changes)
        compose.onNodeWithText("OK").performClick()
        setup.client.postBody = "<main id=main><div class='flash notice'>Saved.</div></main>"
        compose.onNodeWithText("Save as draft").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(2, setup.client.posts); assertEquals(1, setup.client.gets.size); assertEquals(1, changes)
    }

    @Test fun defaultPostShowsAo3PreviewAndPostsTheAdoptedDraftWithNoSecondCreate() {
        show()
        setup.client.postBody = chapterPreviewHtml()
        reach("Post chapter now"); compose.onNodeWithText("Post chapter now").performClick()
        awaitText("Original text")
        compose.onNodeWithTag("Writing chapter preview").assertExists()
        assertEquals(12303L, model.state.value.form!!.chapterID); assertEquals(1, changes); assertEquals(0, closes)
        setup.client.postBody = "<main id=main><div class='flash notice'>Posted.</div></main>"
        compose.onNodeWithTag("Writing chapter preview").performScrollToNode(hasText("Post chapter"))
        compose.onNodeWithText("Post chapter").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(2, setup.client.posts); assertEquals(1, setup.client.gets.size)
        assertEquals(AO3ChapterUrls.chapter(995006, 12303), setup.client.recordedPosts.last().url)
    }

    /**
     * The half the test below names and never ran (audit A28-5): it only ever opened a new chapter, so a
     * posted chapter offering Post and Save as draft would have passed.
     */
    @Test fun aPostedChapterOffersOnlySaveChapterChangesAndSendsUpdate() {
        show("posted", count = 2)
        reach("Save chapter changes")
        compose.onNodeWithText("Post chapter now").assertDoesNotExist()
        compose.onNodeWithText("Save as draft").assertDoesNotExist()
        compose.onNodeWithContentDescription("Post without preview").assertDoesNotExist()
        compose.onNodeWithText("Save chapter changes").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(listOf("update_button" to "1"), setup.client.recordedPosts.single().fields.filter { it.first.endsWith("_button") })
    }

    @Test fun directPostSwitchSendsOnlyOnePostAndPostedChapterOffersOnlyUpdate() {
        show()
        reach("Post without preview"); compose.onNodeWithContentDescription("Post without preview").performClick()
        reach("Post chapter now"); compose.onNodeWithText("Post chapter now").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(listOf("post_without_preview_button" to "1"), setup.client.recordedPosts.single().fields.filter { it.first.endsWith("_button") })
    }

    @Test fun totalFailureOffersOnlyRetryAndDoesNotRepeatTheChapter() {
        show("draft")
        reach("This is the last chapter"); compose.onNodeWithContentDescription("This is the last chapter").performClick()
        setup.client.beforeResponse = { setup.client.body = workFixture("ao3_demo_work_posted_edit") }
        setup.client.beforePostResponse = {
            setup.client.postBody = if (setup.client.posts == 1) "<main id=main><div class='flash notice'>Saved.</div></main>"
                else "<main id=main><div id=error><ul><li>Total refused</li></ul></div></main>"
        }
        reach("Save as draft"); compose.onNodeWithText("Save as draft").performClick()
        awaitText("The chapter was saved, but the work total was not updated. Total refused")
        compose.onNodeWithText("OK").performClick()
        reach("Retry updating the work total")
        compose.onNodeWithText("The chapter was saved. Only the work total will be retried.").assertExists()
        assertEquals(1, changes); assertEquals(0, closes)
        setup.client.beforePostResponse = { setup.client.postBody = "<main id=main><div class='flash notice'>Updated.</div></main>" }
        compose.onNodeWithText("Retry updating the work total").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(3, setup.client.posts); assertEquals(1, setup.client.recordedPosts.count { "/chapters/" in it.url })
    }

    @Test fun deleteExistsOnlyInContentMoreAndRequiresItsNamedConfirmationBeforeAnyRead() {
        show("posted", count = 2)
        reach("Chapter text"); compose.onNodeWithText("Chapter text").performClick()
        awaitText("Recovery copy on this device · Save from the work form")
        compose.onNodeWithContentDescription("More").performClick(); compose.onNodeWithText("Delete chapter").performClick()
        awaitText("Delete “Chapter 2: Second Tide & 星”?")
        compose.onNodeWithText("This will delete all comments on the chapter as well and cannot be undone.").assertExists()
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        setup.client.body = workFixture("ao3_demo_chapter_995006_delete")
        compose.onNodeWithContentDescription("More").performClick(); compose.onNodeWithText("Delete chapter").performClick()
        compose.onNodeWithText("Delete on AO3").performClick()
        compose.waitForIdle(); compose.waitUntil(15_000) { closes == 1 }
        assertEquals(2, setup.client.gets.size); assertEquals(1, setup.client.posts); assertEquals(1, changes)
        assertEquals(listOf("authenticity_token" to "demo-delete-995006==", "_method" to "delete"), setup.client.recordedPosts.single().fields)
    }

    @Test fun failedOpeningHasNoToolbarActionAndTryAgainMakesOneRead() {
        show(failure = AO3Error.Forbidden)
        assertNull(chrome.trailingContent)
        assertEquals(1, setup.client.gets.size)
        setup.client.failure = null
        compose.onNodeWithText("Try Again").performClick(); awaitText("Title")
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun listReloadsOnceAfterPostedUpdateAndPreservesUnsavedWorkTitle() { chapterFlow("posted", "Save chapter changes") }
    @Test fun listReloadsOnceAfterDraftSave() { chapterFlow("draft", "Save as draft") }
    @Test fun listReloadsOnceAfterDirectPost() { chapterFlow("draft", "Post chapter now") }
    @Test fun listReloadsOnceAfterConfirmedDelete() { chapterFlow("posted", "Delete chapter") }

    @Test fun addChapterPreviewRefreshesWorkOnceAndTheNextIndexOpeningShowsItsDraft() {
        setup = runBlocking { workFormSetup() }
        val parent = setup.model(995006).also { runBlocking { it.load() } }
        parent.title("Unsaved owning work")
        val freshWork = org.jsoup.Jsoup.parse(workFixture("ao3_demo_work_posted_edit")).apply {
            selectFirst("form")!!.appendElement("a").attr("href", "/works/995006/chapters/12303/edit").text("Chapter")
        }.outerHtml()
        setup.client.beforeResponse = {
            val url = setup.client.gets.last()
            setup.client.body = when {
                url.endsWith("/chapters/new") -> workFixture("ao3_demo_chapter_995006_new")
                url.endsWith("/navigate") -> workFixture("ao3_demo_work_posted_navigate").replace("</ol>",
                    "<li><a href='/works/995006/chapters/12303'>3. New Tide</a></li></ol>")
                else -> freshWork
            }
        }
        setup.client.postBody = chapterPreviewHtml()
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                WritingWorkFormContent(parent, "AO3_Reader", "Edit work", {})
            }
        } }
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Add chapter"))
        compose.onNodeWithText("Add chapter").performClick(); awaitText("Title")
        reach("Post chapter now"); compose.onNodeWithText("Post chapter now").performClick(); awaitText("Original text")
        compose.waitForIdle()
        compose.waitUntil(15_000) { setup.client.gets.size == 3 && !parent.state.value.publicationNeedRefresh }
        assertEquals(3, parent.state.value.form!!.chaptersPosted)
        assertEquals("Unsaved owning work", parent.state.value.form!!.title)
        back(); awaitText("Title") // Edit returns to the adopted chapter; no read.
        back(); compose.onNodeWithTag("Writing work form").assertExists()
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Chapters"))
        compose.onNodeWithText("Chapters").performClick(); awaitText("Chapter 3 · New Tide")
        assertEquals(4, setup.client.gets.size); assertEquals(1, setup.client.posts)
    }

    @Test fun confirmedWriteAfterBackFromChapterAndListStillRefreshesTheWork() {
        chapterFlow("posted", "Save chapter changes", leaveWhilePending = true)
    }

    @Test fun partialTotalFailureAndItsRetryEachReloadIndexAndWorkOnceWithoutRepeatingChapter() {
        chapterFlow("posted", "Save chapter changes", retryTotal = true)
    }

    private fun chapterFlow(kind: String, action: String, leaveWhilePending: Boolean = false, retryTotal: Boolean = false) {
        setup = runBlocking { workFormSetup() }
        val parent = setup.model(995006).also { runBlocking { it.load() } }
        parent.title("Unsaved owning work")
        setup.client.beforeResponse = {
            val url = setup.client.gets.last()
            setup.client.body = when {
                url.endsWith("/confirm_delete") -> workFixture("ao3_demo_chapter_995006_delete")
                "/chapters/" in url -> workFixture("ao3_demo_chapter_995006_$kind")
                url.endsWith("/navigate") -> if (setup.client.posts == 0) workFixture("ao3_demo_work_posted_navigate")
                    else "<ol class='chapter index'><li><a href='/works/995006/chapters/12301'>1. Chapter 1</a></li>" +
                        (if (action == "Delete chapter") "" else "<li><a href='/works/995006/chapters/12302'>2. Changed tide</a></li>") + "</ol>"
                else -> workFixture("ao3_demo_work_posted_edit")
            }
        }
        val release = CompletableDeferred<Unit>()
        if (leaveWhilePending) setup.client.beforePostResponse = { release.await() }
        if (retryTotal) setup.client.beforePostResponse = {
            setup.client.postBody = if (setup.client.posts == 2) "<main id=main><div id=error><ul><li>Total refused</li></ul></div></main>"
                else "<main id=main><div class='flash notice'>Saved.</div></main>"
        }
        compose.setContent { KudosTheme(KudosThemeMode.Dark) {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                Column {
                    Row { chrome.trailingContent?.invoke(this) }
                    WritingWorkFormContent(parent, "AO3_Reader", "Edit work", {})
                }
            }
        } }
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Chapters"))
        compose.onNodeWithText("Chapters").performClick(); awaitText("Chapter 1")
        val name = io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexParser.parse(workFixture("ao3_demo_work_posted_navigate")).last().displayName
        compose.onNodeWithText(name).performClick(); awaitText("Title")
        if (action == "Delete chapter") {
            reach("Chapter text"); compose.onNodeWithText("Chapter text").performClick()
            awaitText("Recovery copy on this device · Save from the work form")
            compose.onNodeWithContentDescription("More").performClick(); compose.onNodeWithText("Delete chapter").performClick()
            compose.onNodeWithText("Delete on AO3").performClick()
        } else {
            if (retryTotal) {
                reach("This is the last chapter"); compose.onNodeWithContentDescription("This is the last chapter").performClick()
            }
            if (action == "Post chapter now") {
                reach("Post without preview"); compose.onNodeWithContentDescription("Post without preview").performClick()
            }
            reach(action); compose.onNodeWithText(action).performClick()
        }
        if (retryTotal) {
            awaitText("The chapter was saved, but the work total was not updated. Total refused")
            compose.waitForIdle()
            compose.waitUntil(15_000) { setup.client.gets.size == 6 && !parent.state.value.publicationNeedRefresh }
            assertEquals(2, setup.client.posts)
            compose.onNodeWithText("OK").performClick()
            reach("Retry updating the work total"); compose.onNodeWithText("Retry updating the work total").performClick()
        }
        if (leaveWhilePending) {
            compose.waitForIdle(); compose.waitUntil(15_000) { setup.client.posts == 1 }
            back(); awaitText("Chapter 1")
            back(); compose.onNodeWithTag("Writing work form").assertExists()
            compose.runOnIdle { release.complete(Unit) }
            compose.waitForIdle()
            compose.waitUntil(15_000) { setup.client.gets.count { it.endsWith("/995006/edit") } == 2 && !parent.state.value.publicationNeedRefresh }
            assertEquals(4, setup.client.gets.size)
            assertEquals(1, setup.client.posts); assertEquals("Unsaved owning work", parent.state.value.form!!.title)
            compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Chapters"))
            compose.onNodeWithText("Chapters").performClick(); awaitText("Chapter 2 · Changed tide")
            assertEquals(2, setup.client.gets.count { it.endsWith("/navigate") })
            return
        }
        awaitText(if (action == "Delete chapter") "Unsaved owning work · 1 chapter" else "Chapter 2 · Changed tide")
        compose.waitForIdle()
        val expectedReads = if (retryTotal) 9 else if (action == "Delete chapter") 6 else 5
        compose.waitUntil(15_000) { setup.client.gets.size == expectedReads && !parent.state.value.publicationNeedRefresh }
        assertEquals(expectedReads, setup.client.gets.size) // Delete also reads confirm_delete.
        assertEquals(if (retryTotal) 3 else 2, setup.client.gets.count { it.endsWith("/navigate") })
        assertEquals(if (retryTotal) 5 else 2, setup.client.gets.count { it.endsWith("/995006/edit") })
        assertEquals(if (retryTotal) 3 else 1, setup.client.posts)
        assertEquals(1, setup.client.recordedPosts.count { "/chapters/" in it.url })
        assertEquals("Unsaved owning work", parent.state.value.form!!.title)
        assertFalse(parent.state.value.publicationNeedRefresh)
        back(); compose.onNodeWithTag("Writing work form").assertExists()
    }

    @Test fun allThemesAtAccessibilitySizeKeepLabelsAndFailureWordsUnclipped() {
        show("posted", count = 2)
        compose.runOnIdle { scale = 2f }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            for (label in listOf("Title", "Expected chapter total", "This is the last chapter", "Save chapter changes", CHAPTER_LAST_NOTE, CHAPTER_POST_NOTE)) {
                reach(if (label == "Expected chapter total") "Chapter number" else label)
                val node = if (label == "Expected chapter total") compose.onNodeWithText("Chapter number") else compose.onNodeWithText(label)
                node.assertExists()
                val action = node.fetchSemanticsNode().config.getOrNull(SemanticsActions.GetTextLayoutResult)
                val layouts = mutableListOf<TextLayoutResult>(); action?.action?.invoke(layouts)
                assertTrue(label, layouts.isNotEmpty())
                for (layout in layouts) {
                    assertFalse(label, layout.didOverflowHeight)
                    if (layout.lineCount > 0) assertFalse(label, layout.isLineEllipsized(layout.lineCount - 1))
                }
            }
        }
        setup.client.postBody = "<main></main>"
        reach("Save chapter changes"); compose.onNodeWithText("Save chapter changes").performClick()
        awaitText(AO3CollectionFields.UNCONFIRMED)
        assertEquals(0, closes); assertEquals(0, changes)
    }
}
