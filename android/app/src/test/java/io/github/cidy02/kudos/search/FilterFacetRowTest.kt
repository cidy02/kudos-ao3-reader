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

/** A-509c item 3 (iOS `FilterSymbolChipCard` and `TagPickerView.selectionLabel`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class FilterFacetRowTest {
    @get:Rule val compose = createComposeRule()
    private var state by mutableStateOf(FilterSelectionState.CLEAR)

    @Test fun aSetFacetHasA1Point5DpBorderAndAClearOneNone() {
        assertEquals(0.dp, facetBorderWidth(FilterSelectionState.CLEAR))
        assertEquals(1.5.dp, facetBorderWidth(FilterSelectionState.INCLUDED))
        assertEquals(1.5.dp, facetBorderWidth(FilterSelectionState.EXCLUDED))
    }

    @Test fun onlyAnExcludedFacetsSymbolIsDimmedTo0Point4() {
        assertEquals(1f, facetSymbolAlpha(FilterSelectionState.CLEAR))
        assertEquals(1f, facetSymbolAlpha(FilterSelectionState.INCLUDED))
        assertEquals(0.4f, facetSymbolAlpha(FilterSelectionState.EXCLUDED))
    }

    @Test fun theStatusWordIsIncludeOrExcludeAndNoneWhileClear() {
        assertNull(facetStatusWord(FilterSelectionState.CLEAR))
        assertEquals("Include", facetStatusWord(FilterSelectionState.INCLUDED))
        assertEquals("Exclude", facetStatusWord(FilterSelectionState.EXCLUDED))
    }

    @Test fun aTagRowPrintsTheWordOnceSetAndTalkBackHearsTheLabelOnce() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { FilterFacetRow("Found Family", state) { state = state.next } }
        }
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
        for (expected in listOf(FilterSelectionState.INCLUDED, FilterSelectionState.EXCLUDED)) {
            compose.onNodeWithText("Found Family").performClick()
            assertEquals(expected, state)
            compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(1)
            val config = compose.onNodeWithText("Found Family").fetchSemanticsNode().config
            // The label once in the description and once as text, never a third time as the word.
            assertEquals(listOf("Found Family"), config.getOrNull(SemanticsProperties.ContentDescription))
            assertEquals(listOf("Found Family"), config.getOrNull(SemanticsProperties.Text)?.map { it.text })
        }
        compose.onNodeWithText("Found Family").performClick()
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun aSymbolCardKeepsIosIndicatorAndDrawsNoWord() {
        state = FilterSelectionState.INCLUDED
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                FilterFacetRow("Graphic Violence", state, symbol = WorkSymbolTile.warnings(listOf("Graphic Depictions Of Violence"), false)) {}
            }
        }
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
    }
}
