package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import io.github.cidy02.kudos.author.AO3AuthorHero
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.WorkFormToggle
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3heControlsTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private var mode by mutableStateOf(KudosThemeMode.Dark)
    private val themes = listOf(KudosThemeMode.Dark, KudosThemeMode.Oled, KudosThemeMode.Light, KudosThemeMode.Sepia)

    @Before fun resetGlobals() {
        io.github.cidy02.kudos.network.ao3.DemoNetwork.resetForTests()
        io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.clear()
        DebugShotRequests.clear()
    }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            content()
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

    @Test fun subscribeUsesTheExactPageFillAndItsContrastingLabelInEveryTheme() {
        val route = AO3AuthorRoute("Avery_Archive")
        val form = AO3AuthorSubscriptionForm("Subscribe", "unused", emptyList(), "", "unused")
        val header = AO3AuthorHeader("Avery_Archive", "Avery_Archive", null, null, emptyList(), emptyList(), form, emptyList())
        show { AO3AuthorHero(header, route, "", false, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val expected = tokens.scopePalette.tint
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("Subscribe", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(SubjectPalette.label(expected), layouts.single().layoutInput.style.color)
            val button = compose.onNodeWithText("Subscribe").fetchSemanticsNode().boundsInRoot
            val bitmap = snapshot()
            val matches = (button.top.toInt() until button.bottom.toInt()).sumOf { y ->
                (button.left.toInt() until button.right.toInt()).count { x -> close(expected, Color(bitmap.getPixel(x, y))) }
            }
            bitmap.recycle()
            assertTrue("Exact Subscribe fill in $theme", matches > 50)
        }
    }

    @Test fun defaultWritingAndColouredSheetSwitchesUseExactFillsInEveryTheme() {
        val green = Color(0xFF167343)
        show { Column {
            SubjectToggle(true, {}, contentDescription = "Default")
            WorkFormToggle("Publication date", true, true) {}
            val scoped = LocalKudosTokens.current.copy(
                scopePaletteOverride = SubjectPalette.fromColor(green, LocalKudosTokens.current.theme))
            CompositionLocalProvider(LocalKudosTokens provides scoped) {
                SubjectToggle(true, {}, contentDescription = "Sheet")
            }
        } }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val bitmap = snapshot()
            listOf("Default" to tokens.scopePalette.tint, "Publication date" to tokens.scopePalette.tint, "Sheet" to green).forEach { (label, fill) ->
                val node = compose.onNode(hasContentDescription(label) and isToggleable()).fetchSemanticsNode().boundsInRoot
                // On: the thumb is at the right. The left-middle pixel is unblended track.
                val actual = Color(bitmap.getPixel((node.left + node.width * 0.15f).toInt(), node.center.y.toInt()))
                assertTrue("$label in $theme: $actual != $fill", close(fill, actual))
            }
            bitmap.recycle()
        }
    }
}
