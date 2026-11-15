package io.github.cidy02.kudos.search

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.WorkSymbolTile
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-509c item 3 (iOS `FilterSymbolChipCard` for symbol cards, `TagPickerView.tagRows` for word rows).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class FilterFacetRowTest {
    @get:Rule val compose = createComposeRule()
    private var state by mutableStateOf(FilterSelectionState.CLEAR)

    @Test fun aSymbolCardHasABorderLabelColourAndADimmedExcludedSymbolButNoWord() {
        val clear = facetLook(FilterSelectionState.CLEAR, rowHasSymbol = true)
        val included = facetLook(FilterSelectionState.INCLUDED, rowHasSymbol = true)
        val excluded = facetLook(FilterSelectionState.EXCLUDED, rowHasSymbol = true)
        assertEquals(0.dp, clear.borderWidth)
        assertEquals(1.5.dp, included.borderWidth)
        assertEquals(1.5.dp, excluded.borderWidth)
        assertEquals(listOf(0f, 0.12f, 0.08f), listOf(clear, included, excluded).map { it.fillAlpha })
        assertEquals(listOf(false, true, true), listOf(clear, included, excluded).map { it.labelInStateColour })
        assertEquals(listOf(1f, 1f, 0.4f), listOf(clear, included, excluded).map { it.symbolAlpha })
        assertEquals(listOf(null, null, null), listOf(clear, included, excluded).map { it.word })
    }

    @Test fun aWordRowHasNoBorderNoColouredLabelAndTheWordOnceSet() {
        val clear = facetLook(FilterSelectionState.CLEAR, rowHasSymbol = false)
        val included = facetLook(FilterSelectionState.INCLUDED, rowHasSymbol = false)
        val excluded = facetLook(FilterSelectionState.EXCLUDED, rowHasSymbol = false)
        assertEquals(listOf(0.dp, 0.dp, 0.dp), listOf(clear, included, excluded).map { it.borderWidth })
        assertEquals(listOf(false, false, false), listOf(clear, included, excluded).map { it.labelInStateColour })
        // iOS washes an included row at 0.10 and leaves an excluded one plain.
        assertEquals(listOf(0f, 0.10f, 0f), listOf(clear, included, excluded).map { it.fillAlpha })
        assertEquals(listOf(null, "Include", "Exclude"), listOf(clear, included, excluded).map { it.word })
    }

    @Test fun aWordRowPrintsTheWordOnceSetAndTalkBackHearsTheLabelOnce() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { FilterFacetRow("Found Family", state) { state = state.next } }
        }
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
        for (expected in listOf(FilterSelectionState.INCLUDED, FilterSelectionState.EXCLUDED)) {
            compose.onNodeWithText("Found Family").performClick()
            assertEquals(expected, state)
            compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(1)
            val config = compose.onNodeWithText("Found Family").fetchSemanticsNode().config
            // The title is the text; there is no description repeating it, and the word is not read.
            assertNull(config.getOrNull(SemanticsProperties.ContentDescription))
            assertEquals(listOf("Found Family"), config.getOrNull(SemanticsProperties.Text)?.map { it.text })
        }
        compose.onNodeWithText("Found Family").performClick()
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun aShortDrawnTitleIsReadAsTheFullNameAloneNotAsBoth() {
        state = FilterSelectionState.INCLUDED
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                FilterFacetRow("Rape/Non-Con", state, symbol = WorkSymbolTile.warnings(listOf("Rape/Non-Con"), false),
                    accessibilityTitle = "Rape/Non-Consensual Sex") {}
            }
        }
        val config = compose.onNodeWithContentDescription("Rape/Non-Consensual Sex").fetchSemanticsNode().config
        assertEquals(listOf("Rape/Non-Consensual Sex"), config.getOrNull(SemanticsProperties.ContentDescription))
        // The drawn short title is cleared from the merged node: one name, not two.
        assertNull(config.getOrNull(SemanticsProperties.Text))
        assertEquals("Included", config.getOrNull(SemanticsProperties.StateDescription))
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
    }
}
