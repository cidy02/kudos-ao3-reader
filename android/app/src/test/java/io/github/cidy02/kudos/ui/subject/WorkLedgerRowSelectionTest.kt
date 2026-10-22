package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Selection must stay crisp while the work itself is blurred (A73 finding 5). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WorkLedgerRowSelectionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun selectionChromeStaysSharpAtNormalTextSize() = selectionChromeStaysSharp(1f)

    @Test fun selectionChromeStaysSharpAtAccessibilityTextSize() = selectionChromeStaysSharp(1.5f)

    private fun selectionChromeStaysSharp(fontScale: Float) {
        val obscured = mutableStateOf(false)
        var accent = Color.Unspecified
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale)) {
                KudosTheme(KudosThemeMode.Light) {
                    accent = LocalKudosTokens.current.accent
                    Box(Modifier.width(360.dp)) {
                        WorkLedgerRow(
                            title = "Private work", author = "Private author", fandoms = listOf("Private fandom"),
                            metadata = "Private author · 1,200 words · 1/1", progress = 0.4, progressState = "Reading",
                            rating = "Explicit", categories = listOf("F/M"), warnings = emptyList(), isComplete = true,
                            obscured = obscured.value, favorite = false, selected = true, selecting = true,
                            onClick = {}, onLongClick = {}, modifier = Modifier.testTag("row")
                        )
                    }
                }
            }
        }
        val clearRow = compose.onNodeWithTag("row").captureToImage().toPixelMap()
        val clearCheckbox = compose.onNode(isToggleable(), useUnmergedTree = true).captureToImage().toPixelMap()
        compose.runOnIdle { obscured.value = true }
        val blurredRow = compose.onNodeWithTag("row").captureToImage().toPixelMap()
        val blurredCheckbox = compose.onNode(isToggleable(), useUnmergedTree = true).captureToImage().toPixelMap()

        // The straight top edge of a selected row is solid accent, with or without hidden content.
        for (x in clearRow.width / 3 until clearRow.width * 2 / 3) {
            assertTrue("Visible reference border must be accent", distance(accent, clearRow[x, 1]) < 0.05f)
            assertTrue("Blur must not reach the selection border", distance(clearRow[x, 1], blurredRow[x, 1]) < 0.05f)
        }
        assertEquals(clearCheckbox.width, blurredCheckbox.width)
        assertEquals(clearCheckbox.height, blurredCheckbox.height)
        // Include the check mark and its square, avoiding the empty touch-target margin.
        var checkedPixels = 0
        for (y in clearCheckbox.height / 3 until clearCheckbox.height * 2 / 3) {
            for (x in clearCheckbox.width / 3 until clearCheckbox.width * 2 / 3) {
                if (distance(accent, clearCheckbox[x, y]) < 0.05f) checkedPixels++
                assertTrue("Blur must not reach the checkbox", distance(clearCheckbox[x, y], blurredCheckbox[x, y]) < 0.05f)
            }
        }
        assertTrue("Reference must contain a drawn checked box", checkedPixels > 0)
    }

    private fun distance(a: Color, b: Color): Float = maxOf(
        kotlin.math.abs(a.red - b.red), kotlin.math.abs(a.green - b.green),
        kotlin.math.abs(a.blue - b.blue), kotlin.math.abs(a.alpha - b.alpha)
    )
}
