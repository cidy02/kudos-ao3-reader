package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.QueueLedgerCard
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-509c items 1 and 5 (iOS T-509): the fandom is the coloured label above the title and opens
 * that fandom; the grey line under the title is the author only; a work with no fandom draws no
 * label (not "Library", not a blank line); and the label's touch target is 48 dp without moving
 * the text.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class WorkFandomKickerTest {
    @get:Rule val compose = createComposeRule()
    private var searched: Pair<SearchSubjectField, String>? = null
    private var rowTaps = 0

    // --- pure logic --------------------------------------------------------------------------

    @Test fun noNamedFandomMeansNoKickerAtAll() {
        assertNull(fandomKicker(emptyList()))
        assertNull(fandomKicker(listOf("", "  ")))
    }

    @Test fun theKickerNamesTheFirstFandomAndCountsTheRest() {
        val kicker = fandomKicker(listOf("", "Doctor Who (TV)", "Torchwood"))!!
        assertEquals("Doctor Who (TV)", kicker.fandom)
        assertEquals(HomeFacts.primaryFandom(listOf("Doctor Who (TV)", "Torchwood")), kicker.text)
        assertEquals(1, kicker.additional)
        assertEquals(0, fandomKicker(listOf("Doctor Who (TV)", "Torchwood"), expanded = true)!!.additional)
    }

    @Test fun figuresLeaveTheAuthorToTheLineUnderTheTitle() {
        assertEquals(listOf("1.77K words", "3/3"), HomeFacts.localWorkFigures(1_773, "3/3"))
        assertEquals(emptyList<String>(), HomeFacts.localWorkFigures(0, "  "))
        assertTrue(HomeFacts.localWorkFigures(1_773, "3/3").none { it.contains("Rosalita") })
    }

    @Test fun aCardThatOwnsTheTapGivesTheLabelNoLink() {
        assertNull(fandomOpener(interactive = false) { _, _ -> })
        var got: Pair<SearchSubjectField, String>? = null
        fandomOpener(interactive = true) { field, value -> got = field to value }!!.invoke("Torchwood")
        assertEquals(SearchSubjectField.FANDOM to "Torchwood", got)
    }

    // --- ledger row --------------------------------------------------------------------------

    private fun ledger(fandoms: List<String>, selecting: Boolean = false, obscured: Boolean = false) =
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalTagSearch provides { field, value -> searched = field to value }) {
                    WorkLedgerRow(
                        title = "A ledger work", author = "A writer", fandoms = fandoms,
                        metadata = "1.2K words · 1/1", progress = 0.0, progressState = null,
                        rating = "General Audiences", categories = emptyList(), warnings = emptyList(),
                        isComplete = true, obscured = obscured, favorite = false, selected = false,
                        selecting = selecting, onClick = { rowTaps++ }, onLongClick = {}
                    )
                }
            }
        }

    @Test fun aLedgerRowWithNoFandomDrawsNoLabelAndNoInventedLibrary() {
        ledger(emptyList())
        compose.onAllNodesWithContentDescription("Fandom: ", substring = true, useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodes(hasText("LIBRARY", ignoreCase = true), useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("A ledger work", useUnmergedTree = true).assertExists()
    }

    @Test fun theLedgerFandomOpensThatFandomAndNotTheRow() {
        ledger(listOf("Doctor Who", "Torchwood"))
        compose.onNodeWithText("+1", useUnmergedTree = true).assertExists()
        compose.onNodeWithContentDescription("Fandom: Doctor Who").performClick()
        assertEquals(SearchSubjectField.FANDOM to "Doctor Who", searched)
        assertEquals(0, rowTaps)
    }

    @Test fun aSelectingLedgerRowLeavesTheLabelToTheCard() {
        ledger(listOf("Doctor Who"), selecting = true)
        compose.onAllNodesWithContentDescription("Fandom: Doctor Who", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).assertExists()
    }

    @Test fun theGreyLineUnderTheTitleIsTheAuthorAndTheFiguresKeepTheirOwnLine() {
        ledger(listOf("Doctor Who"))
        compose.onNodeWithText("A writer", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("1.2K words · 1/1", useUnmergedTree = true).assertExists()
        compose.onAllNodes(hasText("A writer ·", substring = true), useUnmergedTree = true).assertCountEquals(0)
    }

    // --- queue card --------------------------------------------------------------------------

    private fun queueCard(fandoms: List<String>) = compose.setContent {
        KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalTagSearch provides { field, value -> searched = field to value }) {
                QueueLedgerCard(
                    work = SavedWork(id = "queued", title = "A queued work", author = "A writer",
                        summary = "", wordCount = 1200, chapters = "1/1", comments = 0, bookmarks = 0,
                        workFandoms = fandoms),
                    downloadFraction = null, obscured = false
                )
            }
        }
    }

    @Test fun aQueueCardWithNoFandomDrawsNoLabelAndTheAuthorIsNotInTheFigures() {
        queueCard(emptyList())
        compose.onAllNodes(hasText("LIBRARY", ignoreCase = true), useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("A writer", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("1.2K words  ·  1/1", useUnmergedTree = true).assertExists()
    }

    @Test fun aQueueCardFandomOpensThatFandom() {
        queueCard(listOf("Doctor Who"))
        compose.onNodeWithContentDescription("Fandom: Doctor Who").performClick()
        assertEquals(SearchSubjectField.FANDOM to "Doctor Who", searched)
    }

    // --- item 5: the 48 dp target that moves nothing -----------------------------------------

    private var linked by mutableStateOf(false)
    private val palette get() = SubjectPalette.fromHue(0.5, ReaderTheme.Light)

    private fun kickerColumn() = compose.setContent {
        KudosTheme(KudosThemeMode.Light) {
            Column {
                Text("above", Modifier.testTag("above"))
                // No semantics modifier of the caller's before the link: bounds are read at the first.
                WorkFandomKicker(listOf("Doctor Who"), palette, if (linked) ({ }) else null)
                Text("below", Modifier.testTag("below"))
            }
        }
    }

    @Test fun theLinkIs48DpTallAndLeavesEverythingWhereItWas() {
        kickerColumn()
        val plain = compose.onNodeWithTag("below").fetchSemanticsNode().boundsInRoot.top
        val plainText = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        compose.runOnIdle { linked = true }
        compose.waitForIdle()
        val link = compose.onNodeWithContentDescription("Fandom: Doctor Who").fetchSemanticsNode().boundsInRoot
        val linkedText = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val minimum = with(compose.density) { 48.dp.toPx() }
        assertTrue("target ${link.height}px < ${minimum}px", link.height >= minimum - 1f)
        assertEquals(plain, compose.onNodeWithTag("below").fetchSemanticsNode().boundsInRoot.top, 0.5f)
        assertEquals(plainText.top, linkedText.top, 0.5f)
        assertEquals(plainText.left, linkedText.left, 0.5f)
    }
}
