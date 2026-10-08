package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
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

/** The work form's Chapters list (brief 3bm): iOS WritingChaptersView, reading only. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingChaptersTest {
    @get:Rule val compose = createComposeRule()
    private val chrome = PushedShellChrome()

    @Test fun theSubtitleIsIosWording() {
        assertEquals("Tide", writingChaptersSubtitle("Tide", null))
        assertEquals("Tide · 1 chapter", writingChaptersSubtitle("Tide", 1))
        assertEquals("Tide · 0 chapters", writingChaptersSubtitle("Tide", 0))
    }

    @Test fun oneSignedInReadOfTheWorksOwnIndexAndNothingSent() = runBlocking {
        val setup = workFormSetup()
        val model = setup.model(995006L)
        model.load()
        val chapters = (model.loadChapters() as AO3Result.Success).value
        assertEquals(listOf("Chapter 1", chapters[1].displayName), chapters.map { it.displayName })
        assertTrue(chapters[1].displayName.startsWith("Chapter 2 · This is a very long title"))
        assertEquals(listOf("2026-10-01", "2026-10-05"), chapters.map { it.dateText })
        assertEquals(2, setup.client.gets.size) // the form, then the index
        assertTrue(setup.client.gets.last().endsWith("/works/995006/navigate"))
        assertEquals(0, setup.client.posts)
        setup.client.failure = AO3Error.Forbidden
        assertTrue(model.loadChapters() is AO3Result.Failure)
        assertEquals(3, setup.client.gets.size) // one read per attempt, never a retry
    }

    @Test fun aNewWorkOrASignedOutReaderReadsNothing() = runBlocking {
        val fresh = workFormSetup()
        val unsaved = fresh.model(null)
        unsaved.load()
        assertTrue(unsaved.loadChapters() is AO3Result.Failure)
        assertEquals(1, fresh.client.gets.size) // only the new-work form
        val out = workFormSetup(signedIn = false)
        assertTrue(out.model(995006L).loadChapters() is AO3Result.Failure)
        assertEquals(0, out.client.gets.size)
    }

    @Test fun theListShowsEachChapterAndARowOpensNothingYet() {
        var reads = 0
        var fail = true
        compose.setContent {
            KudosTheme(KudosThemeMode.Dark) {
                CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                    WritingChaptersScreen("Tide", load = {
                        reads++
                        if (fail) AO3Result.Failure(AO3Error.Forbidden)
                        else AO3Result.Success(listOf(AO3ChapterRef(1, 1, "Chapter 1", "2026-10-01"),
                            AO3ChapterRef(2, 2, "Second", "2026-10-05")))
                    }, onBack = {})
                }
            }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Try Again").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Tide").assertExists() // no count before a list has arrived
        assertEquals(1, reads)
        fail = false
        compose.onNodeWithText("Try Again").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Tide · 2 chapters").fetchSemanticsNodes().isNotEmpty() }
        assertEquals(2, reads)
        compose.onNodeWithText("Chapter 1").assertHasNoClickAction()
        compose.onNodeWithText("Chapter 2 · Second").assertHasNoClickAction()
        compose.onNodeWithText("2026-10-05").assertExists()
        assertNotNull(chrome.onBack)
    }
}
