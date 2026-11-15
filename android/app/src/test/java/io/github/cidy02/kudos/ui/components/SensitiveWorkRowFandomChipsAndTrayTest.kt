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
import io.github.cidy02.kudos.search.SearchSubjectField
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
                SensitiveWorkRow(
                    work = SavedWork(id = "saved", title = "A saved work", author = "A writer",
                        summary = "A short summary.", wordCount = 1200, chapters = "1/1", comments = 0,
                        bookmarks = 0, workFandoms = listOf("Doctor Who"), rating = "Teen And Up Audiences"),
                    onOpenWork = {}
                )
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
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
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
        val tray = compose.onNodeWithTag(WORK_STATUS_TRAY_TAG, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val author = compose.onNodeWithText("A writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val summary = compose.onNodeWithText("A short summary.", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("expected 1x4 row (${tray.width}x${tray.height})", tray.width > tray.height * 2f)
        assertTrue("row ${tray.top} not below author ${author.bottom}", tray.top >= author.bottom - 0.5f)
        assertTrue("row ${tray.bottom} not above summary ${summary.top}", tray.bottom <= summary.top + 0.5f)
    }
}
