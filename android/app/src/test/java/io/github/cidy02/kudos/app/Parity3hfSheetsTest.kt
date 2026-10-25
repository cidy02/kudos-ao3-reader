package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.matcher.RootMatchers.isDialog
import androidx.test.espresso.matcher.ViewMatchers.withClassName
import org.hamcrest.Matchers.endsWith
import io.github.cidy02.kudos.account.AO3CollectionsFilter
import io.github.cidy02.kudos.account.AO3CollectionsFilterContent
import io.github.cidy02.kudos.comments.CommentComposerContent
import io.github.cidy02.kudos.comments.CommentFormattingContent
import io.github.cidy02.kudos.library.CollectionReorderContent
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.works.detail.DownloadedDateEditorDialog
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "en-rUS-w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3hfSheetsTest {
    @get:Rule val compose = createComposeRule()
    private var mode by mutableStateOf(KudosThemeMode.Dark)
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private lateinit var app: SubjectPalette
    private lateinit var purple: SubjectPalette
    private var density = 1f
    private val themes = listOf(KudosThemeMode.Dark, KudosThemeMode.Oled, KudosThemeMode.Light, KudosThemeMode.Sepia)

    @Before fun resetGlobals() { DebugShotRequests.clear() }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            app = LocalAppPalette.current
            purple = SubjectPalette.fromColor(Color(0xFF733AB5), tokens.theme)
            density = LocalDensity.current.density
            SubjectPaletteTheme(purple, content)
        } }
    }

    private fun snapshot(): Bitmap {
        compose.waitForIdle()
        lateinit var bitmap: Bitmap
        compose.runOnIdle {
            bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
        }
        return bitmap
    }

    private fun close(a: Color, b: Color) = maxOf(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue)) < 0.012f

    private fun checkWash(palette: SubjectPalette, height: Int) {
        val bitmap = snapshot()
        val top = Color(bitmap.getPixel(2, 2))
        val ground = Color(bitmap.getPixel(2, ((height + 8) * density).toInt()))
        val expected = palette.washStops.first().color.compositeOver(palette.theme.cardBackdrop)
        assertTrue("Wash top in $mode: $top != $expected", close(top, expected))
        assertTrue("Wash ends at ${height}dp in $mode: $ground", close(ground, palette.theme.cardBackdrop))
        bitmap.recycle()
    }

    private fun textColor(label: String): Color {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(label, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.color
    }

    @Test fun composerWashesBehindItsHeaderWithTheCommentsPalette() {
        show { CommentComposerContent(null, null, "", {}, false, null, false, purple, {}, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            checkWash(purple, 320)
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("10,000 left", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertNotEquals(FontFamily.Monospace, layouts.single().layoutInput.style.fontFamily)
        }
    }

    @Test fun formattingTrayUsesTheAppWashEvenOverPurpleComments() {
        show { CommentFormattingContent(TextFieldValue(""), {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            checkWash(app, 320)
        }
    }

    @Test fun collectionsFilterUsesTheAppWashInEveryTheme() {
        show { AO3CollectionsFilterContent(AO3CollectionsFilter(), {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            checkWash(app, 380)
            assertEquals(tokens.theme.accentInk(app.tint), textColor("AO3 order"))
        }
    }

    @Test fun downloadedDateUsesWorkFillLabelAndActionInkOnTheSheetGround() {
        show { DownloadedDateEditorDialog(Instant.parse("2025-10-10T12:00:00Z"), purple, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val expectedInk = tokens.theme.accentInk(purple.tint)
            assertEquals(expectedInk, textColor("Save"))
            assertEquals(expectedInk, textColor("Cancel"))
            val layouts = mutableListOf<TextLayoutResult>()
            val day = compose.onNodeWithText("10", useUnmergedTree = true)
            day.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(SubjectPalette.label(purple.tint), layouts.single().layoutInput.style.color)
            val dayBounds = day.fetchSemanticsNode().boundsInRoot
            // Draw the dialog's Compose root so pixel and semantics coordinates share an origin.
            onView(withClassName(endsWith("AndroidComposeView"))).inRoot(isDialog()).check { root, failure ->
                if (failure != null) throw failure
                val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
                root.draw(Canvas(bitmap))
                val fill = Color(bitmap.getPixel((dayBounds.center.x - 16 * density).toInt(), dayBounds.center.y.toInt()))
                var groundPixels = 0
                for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
                    val pixel = Color(bitmap.getPixel(x, y))
                    if (close(pixel, tokens.formSheetGround)) groundPixels++
                }
                bitmap.recycle()
                assertTrue("Exact selected-day fill in $theme: $fill", close(fill, purple.tint))
                assertTrue("Flat sheet ground in $theme", groundPixels > 500)
            }
        }
    }

    @Test fun reorderHeaderAlignsWithItsReadingOrderLabel() {
        show { CollectionReorderContent(WorkCollection(name = "Green", colorHex = "#167343"),
            emptyList(), false, {}, {}, { _, _ -> }) }
        compose.waitForIdle()
        val header = compose.onNodeWithText("Reorder", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val group = compose.onNodeWithText("READING ORDER", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals(group.left, header.left, 1f)
    }
}
