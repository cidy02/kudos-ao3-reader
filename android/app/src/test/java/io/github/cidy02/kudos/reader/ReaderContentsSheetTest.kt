package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.reader.readium.ReadiumTocAdapter
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Brief 3dl: the reader's Contents sheet has what its sibling sheets and iOS's have. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReaderContentsSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun chapterActionsAreRevealedBySwipeAndNeedAKnownPosition() {
        val ready = ReaderTocEntry("Chapter 1: The Arcade", "ch1.xhtml")
        val pending = ReaderTocEntry("Chapter 2: Nine Minutes", "ch2.xhtml")
        val selected = mutableListOf<ReaderTocEntry>()
        val bookmarked = mutableListOf<ReaderTocEntry>()
        val noted = mutableListOf<ReaderTocEntry>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f)) {
                    ReaderContentsSheet(listOf(ready, pending), emptyList(), emptyList(),
                        onSelectEntry = { selected += it }, onSelectAnnotation = {}, onDeleteAnnotation = {},
                        onBookmarkEntry = { bookmarked += it }, onAddNoteToEntry = { noted += it },
                        startPercent = { if (it == ready) 0 else null })
                }
            }
        }
        compose.onNodeWithText("Bookmark").assertDoesNotExist()
        compose.onNodeWithText("Add Note").assertDoesNotExist()
        compose.onNodeWithText(ready.title).performTouchInput { swipeLeft() }
        compose.onNodeWithText("Bookmark").assertIsDisplayed().performClick()
        assertEquals(listOf(ready), bookmarked)
        compose.onNodeWithText(ready.title).performTouchInput { swipeLeft() }
        compose.onNodeWithText("Add Note").performClick()
        assertEquals(listOf(ready), noted)
        compose.onNodeWithText(pending.title).performTouchInput { swipeLeft() }
        compose.onNodeWithText("Bookmark").assertDoesNotExist()
        compose.onNodeWithText("Add Note").assertDoesNotExist()
        compose.onNodeWithText("Go").performClick()
        assertEquals(listOf(pending), selected)
    }

    /** A86: TalkBack can't swipe a row open, so the row offers the same actions in its menu. */
    @Test fun chapterActionsAreInTalkBacksActionsMenu() {
        val ready = ReaderTocEntry("Chapter 1: The Arcade", "ch1.xhtml")
        val pending = ReaderTocEntry("Chapter 2: Nine Minutes", "ch2.xhtml")
        val bookmarked = mutableListOf<ReaderTocEntry>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ReaderContentsSheet(listOf(ready, pending), emptyList(), emptyList(),
                    onSelectEntry = {}, onSelectAnnotation = {}, onDeleteAnnotation = {},
                    onBookmarkEntry = { bookmarked += it }, onAddNoteToEntry = {},
                    startPercent = { if (it == ready) 0 else null })
            }
        }
        fun actions(title: String) = compose.onNodeWithText(title).fetchSemanticsNode()
            .config.getOrNull(SemanticsActions.CustomActions).orEmpty()
        assertEquals(listOf("Go", "Bookmark", "Add Note"), actions(ready.title).map { it.label })
        assertEquals(listOf("Go"), actions(pending.title).map { it.label })
        compose.runOnIdle { actions(ready.title).first { it.label == "Bookmark" }.action() }
        assertEquals(listOf(ready), bookmarked)
    }

    @Test fun theSheetHasATitleADoneAndEachChaptersStart() {
        var done = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ReaderContentsSheet(
                    entries = listOf(ReaderTocEntry("Chapter 1: The Arcade", "OEBPS/ch1.xhtml"),
                        ReaderTocEntry("Chapter 2: Nine Minutes", "OEBPS/ch2.xhtml#start")),
                    bookmarks = emptyList(), highlights = emptyList(),
                    onSelectEntry = {}, onSelectAnnotation = {}, onDeleteAnnotation = {},
                    onDone = { done++ },
                    startPercent = { mapOf("ch1.xhtml" to 0, "ch2.xhtml" to 50)[ReaderSectionBuilder.hrefKey(it.href)] }
                )
            }
        }
        compose.onNodeWithText("0%").assertExists()
        compose.onNodeWithText("50%").assertExists()
        compose.onNodeWithContentDescription("Done").performClick()
        assertEquals(1, done)
        compose.onNodeWithText("Bookmarks").performClick()
        compose.onNodeWithText("No Bookmarks Yet").assertExists()
    }

    @Test fun aFileStartsWhereItsFirstPositionDoes() {
        assertEquals(
            mapOf("ch1.xhtml" to 0, "ch2.xhtml" to 50),
            ReadiumTocAdapter.startPercents(listOf(
                "OEBPS/ch1.xhtml" to 0.0, "OEBPS/ch1.xhtml" to 0.25,
                "OEBPS/ch2.xhtml" to 0.496, "OEBPS/ch2.xhtml" to 0.75, "OEBPS/nav.xhtml" to null
            ))
        )
    }
}
