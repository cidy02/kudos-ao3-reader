package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.compose.ui.test.longClick
import androidx.compose.ui.geometry.Offset
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Audit A18-5: a blurred row gives nothing of the work away, to the eye or to a screen reader. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SensitiveWorkRowPrivacyTest {
    @get:Rule val compose = createComposeRule()

    private val work = SavedWork(
        id = "w1", title = "A Private Title", author = "someone",
        rating = "Explicit", workFandoms = listOf("A Fandom")
    )

    @Test fun fallbackRemoteCopyLinkWritesTheActualUrl() {
        val remote = io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary(
            id = 123, title = "Remote work", authors = listOf("A"), fandoms = emptyList(),
            rating = "", warnings = emptyList(), categories = emptyList())
        var clipboard: androidx.compose.ui.platform.ClipboardManager? = null
        compose.setContent {
            clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
            KudosTheme(KudosThemeMode.Light) { SensitiveWorkRow(remote, onOpenWork = {}) }
        }
        compose.onNodeWithText("Remote work").performTouchInput { longClick() }
        compose.onNodeWithText("Copy Link").performClick()
        assertEquals(remote.workUrl, clipboard!!.getText()!!.text)
    }

    @Test fun aBlurredRowIsOneRevealButtonThatNamesNothing() {
        var revealed = 0
        var opened = 0
        var searched = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    work = work, onOpenWork = { opened++ }, obscured = true,
                    onReveal = { revealed++ }, onTagSearch = { _, _ -> searched++ }
                )
            }
        }
        // Nothing of the work is in what a screen reader is given.
        compose.onAllNodesWithText("A Private Title", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("A Fandom", substring = true).assertCountEquals(0)
        // The row is still a button, and activating it reveals.
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.")
            .performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, revealed)
        assertEquals(0, opened)
        assertEquals(0, searched)
    }

    @Test fun aTapAnywhereOnABlurredRowRevealsAndNeverSearches() {
        var revealed = 0
        var searched = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    work = work, onOpenWork = {}, obscured = true,
                    onReveal = { revealed++ }, onTagSearch = { _, _ -> searched++ }
                )
            }
        }
        // The fandom line has no semantics of its own any more, so tap down the row's left
        // side, where it is drawn.
        val taps = 12
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").performTouchInput {
            repeat(taps) { i -> click(Offset(width / 4f, height * (i + 0.5f) / taps)) }
        }
        assertEquals(0, searched)
        assertEquals(taps, revealed)
    }

    @Test fun aFandomTapWhileSelectingSelectsInsteadOfSearching() {
        var selections = 0
        var searched = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    work = work, onOpenWork = {}, selecting = true,
                    onSelect = { selections++ }, onTagSearch = { _, _ -> searched++ }
                )
            }
        }
        compose.onNodeWithText("A Fandom", substring = true, useUnmergedTree = true).performClick()
        assertEquals(1, selections)
        assertEquals(0, searched)
    }

    /** The same for a cover (Home, the Library's grids): audit A19-8's rule on Android. */
    @Test fun aBlurredCoverNamesNothing() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard(work = work, obscured = true, downloadFraction = null)
            }
        }
        // The tree a screen reader is given (the unmerged one keeps cleared nodes, for tools).
        compose.onAllNodesWithText("A Private Title", substring = true).assertCountEquals(0)
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").assertExists()
    }

    @Test fun blurredSelectionStatesAndHintsReachRowsLedgerRowsAndCovers() {
        var chosen by mutableStateOf(false)
        var toggles = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Column {
                    SensitiveWorkRow(work = work, onOpenWork = {}, obscured = true,
                        selecting = true, selected = chosen, onSelect = { toggles++ })
                    io.github.cidy02.kudos.ui.subject.WorkLedgerRow(
                        title = work.title, author = work.author, fandoms = emptyList(), metadata = "",
                        progress = 0.0, progressState = null, rating = "Explicit", categories = emptyList(),
                        warnings = emptyList(), isComplete = null, obscured = true, favorite = false,
                        selected = chosen, selecting = true, onClick = { toggles++ }, onLongClick = {})
                    io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard(work, true, null,
                        isSelecting = true, isSelected = chosen)
                }
            }
        }
        for (selected in listOf(false, true)) {
            compose.runOnIdle { chosen = selected }
            compose.onAllNodesWithText("A Private Title", substring = true).assertCountEquals(0)
            val nodes = compose.onAllNodesWithContentDescription("Hidden mature work").fetchSemanticsNodes()
            assertEquals(3, nodes.size)
            for (node in nodes) {
                assertEquals(selected, node.config[SemanticsProperties.Selected])
                assertEquals(if (selected) "Selected" else "Not selected", node.config[SemanticsProperties.StateDescription])
                assertEquals("${if (selected) "deselect" else "select"} this work",
                    node.config[SemanticsActions.OnClick].label)
            }
        }
        // clearAndSetSemantics must keep the real row/ledger click action.
        compose.onAllNodesWithContentDescription("Hidden mature work")[0].performSemanticsAction(SemanticsActions.OnClick)
        compose.onAllNodesWithContentDescription("Hidden mature work")[1].performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(2, toggles)
    }

    @Test fun aRowInTheClearStillOpensAFandomSearch() {
        var searched = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(work = work, onOpenWork = {}, onTagSearch = { _, _ -> searched++ })
            }
        }
        compose.onNodeWithText("A Fandom", substring = true, useUnmergedTree = true).performClick()
        assertEquals(1, searched)
    }
}
