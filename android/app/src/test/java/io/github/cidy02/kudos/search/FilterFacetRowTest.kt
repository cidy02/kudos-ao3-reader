package io.github.cidy02.kudos.search

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.WorkSymbolTile
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A-509c item 3 (iOS `FilterSymbolChipCard` for symbol cards, `TagPickerView.tagRows` for word rows).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
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

    @Test fun aRenderedWordRowHasPlainLabelColourWordAndNoColouredBorder() {
        var primary = Color.Unspecified
        var secondary = Color.Unspecified
        val includeGreen = Color(0.20f, 0.55f, 0.25f)
        val excludeRed = Color(0.80f, 0.15f, 0.15f)
        lateinit var view: View
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                view = LocalView.current
                val tokens = LocalKudosTokens.current
                primary = tokens.primaryInk
                secondary = tokens.secondaryInk
                FilterFacetRow("Found Family", state) { state = state.next }
            }
        }
        compose.onNodeWithText("Found Family").performClick()
        assertEquals(FilterSelectionState.INCLUDED, state)
        compose.onNodeWithText("Include", useUnmergedTree = true).assertExists()
        assertEquals(primary, labelLayout("Found Family").layoutInput.style.color)
        assertNotEquals(TextDecoration.LineThrough, labelLayout("Found Family").layoutInput.style.textDecoration)
        assertFalse("included word row should not draw a 1.5dp green border",
            hasTopEdgeBorder(view, "Found Family", includeGreen))

        compose.onNodeWithText("Found Family").performClick()
        assertEquals(FilterSelectionState.EXCLUDED, state)
        compose.onNodeWithText("Exclude", useUnmergedTree = true).assertExists()
        val excludedLayout = labelLayout("Found Family")
        assertEquals(secondary, excludedLayout.layoutInput.style.color)
        assertEquals(TextDecoration.LineThrough, excludedLayout.layoutInput.style.textDecoration)
        assertFalse("excluded word row should not draw a 1.5dp red border",
            hasTopEdgeBorder(view, "Found Family", excludeRed))
    }

    @Test fun aRenderedSymbolCardHasStateColouredBorderAndLabelWithNoStatusWord() {
        var primary = Color.Unspecified
        val includeGreen = Color(0.20f, 0.55f, 0.25f)
        val excludeRed = Color(0.80f, 0.15f, 0.15f)
        lateinit var view: View
        state = FilterSelectionState.INCLUDED
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                view = LocalView.current
                primary = LocalKudosTokens.current.primaryInk
                FilterFacetRow(
                    title = "Rape/Non-Con",
                    state = state,
                    symbol = WorkSymbolTile.warnings(listOf("Rape/Non-Con"), false),
                    accessibilityTitle = "Rape/Non-Consensual Sex"
                ) { state = state.next }
            }
        }
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
        val includedLayout = labelLayout("Rape/Non-Con")
        assertNotEquals(primary, includedLayout.layoutInput.style.color)
        assertEquals(includeGreen, includedLayout.layoutInput.style.color)
        assertNotEquals(TextDecoration.LineThrough, includedLayout.layoutInput.style.textDecoration)
        assertTrue("included symbol card should draw its 1.5dp green border",
            hasTopEdgeBorderByDescription(view, "Rape/Non-Consensual Sex", includeGreen))

        compose.onNodeWithContentDescription("Rape/Non-Consensual Sex").performClick()
        assertEquals(FilterSelectionState.EXCLUDED, state)
        compose.onAllNodesWithTag(FACET_STATUS_WORD_TAG, useUnmergedTree = true).assertCountEquals(0)
        val excludedLayout = labelLayout("Rape/Non-Con")
        assertEquals(excludeRed, excludedLayout.layoutInput.style.color)
        assertEquals(TextDecoration.LineThrough, excludedLayout.layoutInput.style.textDecoration)
        assertTrue("excluded symbol card should draw its 1.5dp red border",
            hasTopEdgeBorderByDescription(view, "Rape/Non-Consensual Sex", excludeRed))
    }

    private fun labelLayout(text: String): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single()
    }

    private fun hasTopEdgeBorder(view: View, text: String, expected: Color): Boolean =
        hasTopBorderPixel(view, compose.onNodeWithText(text).fetchSemanticsNode().boundsInRoot, expected)

    private fun hasTopEdgeBorderByDescription(view: View, description: String, expected: Color): Boolean =
        hasTopBorderPixel(view, compose.onNodeWithContentDescription(description).fetchSemanticsNode().boundsInRoot, expected)

    private fun hasTopBorderPixel(view: View, bounds: Rect, expected: Color): Boolean {
        var found = false
        compose.runOnIdle {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            val x = ((bounds.left + bounds.right) / 2f).toInt().coerceIn(0, bitmap.width - 1)
            val startY = bounds.top.toInt().coerceAtLeast(0)
            val endY = minOf(startY + 4, bitmap.height)
            found = (startY until endY).any { y ->
                val p = Color(bitmap.getPixel(x, y))
                p.alpha > 0.9f &&
                    abs(p.red - expected.red) < 0.08f &&
                    abs(p.green - expected.green) < 0.08f &&
                    abs(p.blue - expected.blue) < 0.08f
            }
            bitmap.recycle()
        }
        return found
    }
}
