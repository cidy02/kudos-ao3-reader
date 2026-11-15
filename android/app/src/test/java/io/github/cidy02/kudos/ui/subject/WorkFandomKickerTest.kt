package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.ui.unit.sp
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
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

    @Test fun theSpokenLabelNamesTheFandomAndHowManyMoreOnce() {
        assertEquals("Fandom: Doctor Who", fandomKicker(listOf("Doctor Who"))!!.spoken)
        assertEquals("Fandom: Doctor Who, plus 2 more", fandomKicker(listOf("Doctor Who", "A", "B"))!!.spoken)
        assertEquals("Fandom: Doctor Who", fandomKicker(listOf("Doctor Who", "A"), expanded = true)!!.spoken)
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
        compose.onNodeWithContentDescription("Fandom: Doctor Who, plus 1 more").performClick()
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

    @Test fun aQueueCardStacksAndUnclampsTitleAtTwoHundredPercent() {
        val longTitle = "A very long queued work title that wraps across multiple lines at large text sizes"
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = androidx.compose.ui.platform.LocalDensity.current
                CompositionLocalProvider(
                    androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density, 2f)
                ) {
                    Box(Modifier.width(320.dp)) {
                        QueueLedgerCard(
                            work = SavedWork(id = "queued-ax", title = longTitle, author = "A writer",
                                summary = "", wordCount = 1200, chapters = "1/1", comments = 0, bookmarks = 0,
                                workFandoms = listOf("Doctor Who")),
                            downloadFraction = null, obscured = false
                        )
                    }
                }
            }
        }
        val kicker = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText(longTitle, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val author = compose.onNodeWithText("A writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val titleLayout = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(longTitle, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(titleLayout) }
        assertTrue("title should wrap at 200% without ellipsis", titleLayout.single().lineCount > 1 && !titleLayout.single().hasVisualOverflow)
        assertTrue("stacked order kicker (${kicker.bottom}) -> title (${title.top}) -> author (${author.top})",
            kicker.bottom <= title.top + 0.5f && title.bottom <= author.top + 0.5f)
    }

    // --- item 5: a 48 dp target that overlaps nothing ----------------------------------------

    private var plain by mutableStateOf(true)
    private var linkOpened = 0
    private val palette get() = SubjectPalette.fromHue(0.5, ReaderTheme.Light)

    private fun kickerColumn() = compose.setContent {
        KudosTheme(KudosThemeMode.Light) {
            Box(Modifier.padding(top = 20.dp).clickable { rowTaps++ }) {
                Column {
                    if (plain) SubjectKicker("Dr", palette, size = 9.sp, ruleSpacing = 5.dp)
                    // A short name: 48 dp wide is the box's doing, not the text's.
                    else WorkFandomKicker(listOf("Dr"), palette, { linkOpened++ })
                    Text("the title", Modifier.testTag("title"))
                }
            }
        }
    }

    @Test fun theTargetIs48DpEachWayLeavesTheTextAndOverlapsNothingBelow() {
        kickerColumn()
        val plainText = compose.onNodeWithText("DR", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        compose.runOnIdle { plain = false }
        compose.waitForIdle()
        val link = compose.onNodeWithContentDescription("Fandom: Dr").fetchSemanticsNode().boundsInRoot
        val linkText = compose.onNodeWithText("DR", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithTag("title").fetchSemanticsNode().boundsInRoot
        val minimum = with(compose.density) { 48.dp.toPx() }
        assertTrue("height ${link.height}px < ${minimum}px", link.height >= minimum - 1f)
        assertTrue("width ${link.width}px < ${minimum}px", link.width >= minimum - 1f)
        assertEquals(plainText.top, linkText.top, 0.5f)
        assertEquals(plainText.left, linkText.left, 0.5f)
        // Reached up into the padding, not down over the title.
        assertTrue("link bottom ${link.bottom} over title top ${title.top}", link.bottom <= title.top + 0.5f)
    }

    @Test fun aTapOnTheTitleGoesToTheRowAndATapOnTheLabelOpensTheFandom() {
        kickerColumn()
        compose.runOnIdle { plain = false }
        compose.waitForIdle()
        compose.onNodeWithTag("title").performClick()
        assertEquals(1, rowTaps)
        assertEquals(0, linkOpened)
        compose.onNodeWithContentDescription("Fandom: Dr").performClick()
        assertEquals(1, linkOpened)
        assertEquals(1, rowTaps)
    }

    @Test fun theLabelIsAnnouncedOnceWithItsCount() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkFandomKicker(listOf("Doctor Who", "Torchwood"), palette, { })
            }
        }
        compose.onNodeWithContentDescription("Fandom: Doctor Who, plus 1 more").assertExists()
        // The drawn name and "+1" are cleared from the merged tree: no second announcement.
        compose.onAllNodes(hasText("DOCTOR WHO"), useUnmergedTree = false).assertCountEquals(0)
        compose.onAllNodes(hasText("+1"), useUnmergedTree = false).assertCountEquals(0)
    }

    @Test fun thePlusCountSurvivesALongNameAtTwoHundredPercent() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = androidx.compose.ui.platform.LocalDensity.current
                CompositionLocalProvider(
                    androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density, 2f)
                ) {
                    Box(Modifier.width(220.dp).testTag("box")) {
                        WorkFandomKicker(
                            listOf("A very long fandom name that cannot possibly fit on one line at all", "B", "C"),
                            palette, null
                        )
                    }
                }
            }
        }
        val plus = compose.onNodeWithText("+2", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val box = compose.onNodeWithTag("box").fetchSemanticsNode().boundsInRoot
        assertTrue("+2 ($plus) outside the ${box.width}px box", plus.right <= box.right + 0.5f && plus.left >= box.left)
    }
}
