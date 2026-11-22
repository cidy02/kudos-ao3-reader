package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkSymbolPlacement
import io.github.cidy02.kudos.library.QueueLedgerCard
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-509c items 2 and 4 (iOS T-509 / `AO3WorkRow.chipGroup("Fandoms", dropFirst)`, `WorkRow.symbols`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class SensitiveWorkRowFandomChipsAndTrayTest {
    @get:Rule val compose = createComposeRule()
    private var searched: Pair<SearchSubjectField, String>? = null

    private val groups = { saved: Boolean ->
        standardExpandedTagGroups(
            savedCard = saved, fandoms = listOf("Doctor Who", "", "Torchwood", "Sherlock"),
            warnings = listOf("No Archive Warnings Apply"), relationships = listOf("A/B"),
            characters = emptyList(), freeforms = emptyList(), discoveryTags = emptyList()
        )
    }

    @Test fun anAo3CardLeadsItsExpandedGroupsWithItsOtherFandomsAsTappableChips() {
        val all = groups(false)
        assertEquals(Triple("Fandoms", listOf("Torchwood", "Sherlock"), SearchSubjectField.FANDOM), all.first())
        assertEquals(listOf("Fandoms", "Archive Warnings", "Relationships"), all.map { it.first })
    }

    @Test fun aSavedCardNamesEveryFandomInTextSoItHasNoFandomChips() {
        assertTrue(groups(true).none { it.third == SearchSubjectField.FANDOM })
    }

    @Test fun anExpandedAo3CardsOtherFandomsAreChipsThatSearchThatFandom() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    id = "1", title = "Sodium Lights", author = "nine_of_wands",
                    fandoms = listOf("Doctor Who", "Torchwood"), summary = "A city that never sleeps.",
                    discoveryTags = emptyList(), warnings = emptyList(), categories = emptyList(),
                    rating = "General Audiences", isComplete = true, wordCount = 1200, chapters = "1/1",
                    kudos = 3, expandAll = true,
                    onClick = {}, onTagSearch = { field, tag -> searched = field to tag }
                )
            }
        }
        compose.onNodeWithText("Fandoms").assertExists()
        // Not "Doctor Who, Torchwood" in one plain line.
        compose.onAllNodesWithText("Doctor Who, Torchwood").assertCountEquals(0)
        compose.onNodeWithText("Torchwood").performClick()
        assertEquals(SearchSubjectField.FANDOM to "Torchwood", searched)
    }

    @Test fun aLocalStandardRowDrawsTheTwoByTwoSymbolGridBesideTheTitle() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalWorkSymbolPlacement provides WorkSymbolPlacement.Beside) {
                    SensitiveWorkRow(
                        work = SavedWork(id = "saved", title = "A saved work", author = "A writer",
                            summary = "A short summary.", wordCount = 1200, chapters = "1/1", comments = 0,
                            bookmarks = 0, workFandoms = listOf("Doctor Who"), rating = "Teen And Up Audiences"),
                        onOpenWork = {}
                    )
                }
            }
        }
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("A saved work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val twoTiles = with(compose.density) { (24.dp * 2).toPx() }
        assertTrue("expected 2x2 grid (${tray.width}x${tray.height})", tray.height >= twoTiles && abs(tray.width - tray.height) <= 2f)
        assertTrue("grid (${tray.left}) should sit beside title (${title.right})", tray.left >= title.right - 0.5f)
    }

    @Test fun aLocalStandardRowKeepsTheTwoByTwoGridAtTwoHundredPercentStackedAboveTheText() {
        var opened = 0
        var searchedFandom: Pair<SearchSubjectField, String>? = null
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = LocalDensity.current
                CompositionLocalProvider(
                    LocalDensity provides Density(density.density, 2f),
                    LocalWorkSymbolPlacement provides WorkSymbolPlacement.Beside
                ) {
                    SensitiveWorkRow(
                        work = SavedWork(id = "saved", title = "A saved work", author = "A writer",
                            summary = "A short summary.", wordCount = 1200, chapters = "1/1", comments = 0,
                            bookmarks = 0, workFandoms = listOf("Doctor Who"), rating = "Teen And Up Audiences"),
                        onOpenWork = { opened++ },
                        onTagSearch = { field, tag -> searchedFandom = field to tag }
                    )
                }
            }
        }
        val trayNode = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true)
        val tray = trayNode.fetchSemanticsNode().boundsInRoot
        val kickerText = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val kickerTarget = compose.onNodeWithContentDescription("Fandom: Doctor Who", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("A saved work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val scaledTwoTiles = with(compose.density) { (24.dp * 1.8f * 2).toPx() }
        assertTrue("expected 2x2 grid (${tray.width}x${tray.height}) at 200%", tray.height >= scaledTwoTiles && abs(tray.width - tray.height) <= 2f)
        assertTrue("grid ${tray.bottom} overlaps kicker target ${kickerTarget.top}", tray.bottom <= kickerTarget.top + 0.5f)
        assertTrue("grid ${tray.bottom} not above kicker text ${kickerText.top}", tray.bottom <= kickerText.top + 0.5f)
        assertTrue("grid ${tray.bottom} not above title ${title.top}", tray.bottom <= title.top + 0.5f)
        // Tapping the bottom edge of the stacked grid opens the work, not the fandom link below it.
        trayNode.performTouchInput { click(Offset(width / 2f, height - 1f)) }
        assertEquals(1, opened)
        assertNull(searchedFandom)
    }

    @Test fun aLocalStandardRowDrawsTheSymbolRowUnderTheTitleAtTwoHundredPercent() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = LocalDensity.current
                CompositionLocalProvider(
                    LocalDensity provides Density(density.density, 2f),
                    LocalWorkSymbolPlacement provides WorkSymbolPlacement.UnderTitle
                ) {
                    SensitiveWorkRow(
                        work = SavedWork(id = "saved", title = "A saved work", author = "A writer",
                            summary = "A short summary.", wordCount = 1200, chapters = "1/1", comments = 0,
                            bookmarks = 0, workFandoms = listOf("Doctor Who"), rating = "Teen And Up Audiences"),
                        onOpenWork = {}
                    )
                }
            }
        }
        val kicker = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("A saved work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val author = compose.onNodeWithText("A writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val summary = compose.onNodeWithText("A short summary.", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("expected 1x4 row (${tray.width}x${tray.height})", tray.width > tray.height * 2f)
        assertTrue("title ${title.top} not below kicker ${kicker.bottom}", title.top >= kicker.bottom - 0.5f)
        assertTrue("row ${tray.top} not below title ${title.bottom}", tray.top >= title.bottom - 0.5f)
        assertTrue("author ${author.top} not below row ${tray.bottom}", author.top >= tray.bottom - 0.5f)
        assertTrue("summary ${summary.top} not below author ${author.bottom}", summary.top >= author.bottom - 0.5f)
    }

    @Test fun anUnchosenRowDefaultsToUnderTheTitleSymbolRow() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    work = SavedWork(id = "default", title = "Default row", author = "Default writer",
                        summary = "Default summary.", wordCount = 1200, chapters = "1/1",
                        workFandoms = listOf("Doctor Who"), rating = "Teen And Up Audiences"),
                    onOpenWork = {}
                )
            }
        }
        val title = compose.onNodeWithText("Default row", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val author = compose.onNodeWithText("Default writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("expected 1x4 row by default (${tray.width}x${tray.height})", tray.width > tray.height * 2f)
        assertTrue("row ${tray.top} not below title ${title.bottom}", tray.top >= title.bottom - 0.5f)
        assertTrue("author ${author.top} not below row ${tray.bottom}", author.top >= tray.bottom - 0.5f)
    }

    @Test fun underTitleStandardRowOrderIsFandomTitleSymbolsAuthorFigures() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalWorkSymbolPlacement provides WorkSymbolPlacement.UnderTitle) {
                    SensitiveWorkRow(
                        work = SavedWork(
                            id = "std", title = "Standard work", author = "Standard writer",
                            summary = "Short summary.", wordCount = 1200, chapters = "1/1",
                            workFandoms = listOf("Doctor Who"), workFreeforms = listOf("Found Family"),
                            rating = "Teen And Up Audiences", isFavorite = true
                        ),
                        onOpenWork = {}
                    )
                }
            }
        }
        val kicker = compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("Standard work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val author = compose.onNodeWithText("Standard writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val figures = compose.onNodeWithText("1,200", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(kicker.bottom <= title.top + 0.5f)
        assertTrue(title.bottom <= tray.top + 0.5f)
        assertTrue(tray.bottom <= author.top + 0.5f)
        assertTrue(author.bottom <= figures.top + 0.5f)
    }

    @Test fun underTitleTrailingStarAndExpandDoNotPushTheStripDownFromTitle() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalWorkSymbolPlacement provides WorkSymbolPlacement.UnderTitle) {
                    SensitiveWorkRow(
                        work = SavedWork(
                            id = "gap", title = "One line", author = "Gap writer",
                            summary = "", wordCount = 1200, chapters = "1/1",
                            workFandoms = emptyList(), workFreeforms = listOf("Found Family"),
                            rating = "General Audiences", isFavorite = true
                        ),
                        onOpenWork = {}
                    )
                }
            }
        }
        val title = compose.onNodeWithText("One line", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val unfold = compose.onNodeWithContentDescription("Show more", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val star = compose.onNodeWithContentDescription("Favorite", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val gapPx = tray.top - title.bottom
        val sixDp = with(compose.density) { 6.dp.toPx() }
        assertTrue("strip gap $gapPx px should stay near 6 dp ($sixDp px)", abs(gapPx - sixDp) <= 2.5f)
        assertTrue("star (${star.left}) should sit beside title (${title.right})", star.left >= title.right - 0.5f)
        assertTrue("unfold (${unfold.left}) should sit beside title (${title.right})", unfold.left >= title.right - 0.5f)
    }

    @Test fun underTitleLedgerAndQueueRowsOrderFandomTitleSymbolsAuthorFigures() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalWorkSymbolPlacement provides WorkSymbolPlacement.UnderTitle) {
                    androidx.compose.foundation.layout.Column {
                        SensitiveWorkRow(
                            id = "ao3-ledger", title = "AO3 ledger", author = "AO3 writer",
                            fandoms = listOf("Torchwood"), summary = "",
                            discoveryTags = emptyList(), warnings = emptyList(), categories = emptyList(),
                            rating = "General Audiences", isComplete = true, wordCount = 1200, chapters = "1/1",
                            kudos = 3, language = "English", showsZeroStats = false, ledger = true,
                            onClick = {}
                        )
                        WorkLedgerRow(
                            title = "Ledger work", author = "Ledger writer", fandoms = listOf("Sherlock"),
                            metadata = "1.2K words · 1/1", progress = 0.25, progressState = "Reading",
                            rating = "General Audiences", categories = emptyList(), warnings = emptyList(),
                            isComplete = true, obscured = false, favorite = true, selected = false,
                            onClick = {}, onLongClick = {}
                        )
                        QueueLedgerCard(
                            work = SavedWork(
                                id = "q", title = "Queued work", author = "Queued writer",
                                summary = "", wordCount = 1200, chapters = "1/1",
                                workFandoms = listOf("Good Omens"), rating = "General Audiences"
                            ),
                            downloadFraction = null, obscured = false
                        )
                    }
                }
            }
        }
        val trays = compose.onAllNodes(androidx.compose.ui.test.hasTestTag(WORK_STATUS_TRAY_TAG), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.boundsInRoot }
        assertEquals(3, trays.size)

        val ao3Kicker = compose.onNodeWithText("TORCHWOOD", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val ao3Title = compose.onNodeWithText("AO3 ledger", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val ao3Tray = trays[0]
        val ao3Author = compose.onNodeWithText("by AO3 writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val ao3Figures = compose.onNodeWithText("English  ·  1,200 words  ·  1/1  ·  3 kudos", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        assertTrue(ao3Kicker.bottom <= ao3Title.top + 0.5f)
        assertTrue(ao3Title.bottom <= ao3Tray.top + 0.5f)
        assertTrue(ao3Tray.bottom <= ao3Author.top + 0.5f)
        assertTrue(ao3Author.bottom <= ao3Figures.top + 0.5f)

        val wlKicker = compose.onNodeWithText("SHERLOCK", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val wlTitle = compose.onNodeWithText("Ledger work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val wlTray = trays[1]
        val wlAuthor = compose.onNodeWithText("Ledger writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val wlFigures = compose.onNodeWithText("1.2K words · 1/1", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val wlStar = compose.onNodeWithText("★", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(wlKicker.bottom <= wlTitle.top + 0.5f)
        assertTrue(wlTitle.bottom <= wlTray.top + 0.5f)
        assertTrue(wlTray.bottom <= wlAuthor.top + 0.5f)
        assertTrue(wlAuthor.bottom <= wlFigures.top + 0.5f)
        assertTrue(wlStar.left >= wlTitle.right - 0.5f)

        val qKicker = compose.onNodeWithText("GOOD OMENS", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val qTitle = compose.onNodeWithText("Queued work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val qTray = trays[2]
        val qAuthor = compose.onNodeWithText("Queued writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val qFigures = compose.onNodeWithText("1.2K words  ·  1/1", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(qKicker.bottom <= qTitle.top + 0.5f)
        assertTrue(qTitle.bottom <= qTray.top + 0.5f)
        assertTrue(qTray.bottom <= qAuthor.top + 0.5f)
        assertTrue(qAuthor.bottom <= qFigures.top + 0.5f)
    }
}
