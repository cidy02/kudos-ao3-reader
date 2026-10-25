package io.github.cidy02.kudos.library

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.view.View
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.time.Instant
import kotlin.math.abs
import kotlin.math.ceil
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3hiInsightsTest {
    @get:Rule val compose = createComposeRule()
    private val now = Instant.parse("2026-10-25T12:00:00Z")
    private val statistics = ReadingStatistics.from(
        listOf(SavedWork(title = "Finished", author = "A", isFinished = true, wordCount = 202_600)), now
    )

    @Test fun libraryBlockRendersThePagePalettesRowWashOverTheCardSurface() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        lateinit var view: View
        lateinit var palette: SubjectPalette
        var density = 1f
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            palette = LocalKudosTokens.current.scopePalette
            density = LocalDensity.current.density
            ReadingStatisticsContent(ReadingStatisticsUiState(loading = false, statistics = statistics, now = now), {})
        } }
        for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val bounds = compose.onNodeWithTag("insightsLibraryCard").assertIsDisplayed()
                .fetchSemanticsNode().boundsInRoot
            compose.runOnIdle {
                val actual = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(actual))
                // Independent Android-canvas reference: opaque card first, then the palette's
                // two row-wash stops. No production card/panel modifier is used for the oracle.
                val expected = Bitmap.createBitmap(ceil(bounds.width).toInt(), ceil(bounds.height).toInt(), Bitmap.Config.ARGB_8888)
                val canvas = Canvas(expected)
                canvas.drawColor(palette.theme.cardSurface.toArgb())
                val stops = palette.rowWashColors
                val paint = Paint().apply {
                    shader = LinearGradient(0f, 0f, bounds.width, bounds.height,
                        stops.map { it.toArgb() }.toIntArray(), null, Shader.TileMode.CLAMP)
                }
                canvas.drawRect(0f, 0f, bounds.width, bounds.height, paint)
                // The top padding is empty and well inside the rounded border.
                val y = (8f * density).toInt()
                for (fraction in listOf(0.25f, 0.5f, 0.75f)) {
                    val x = (bounds.width * fraction).toInt()
                    val target = Color(expected.getPixel(x, y))
                    val pixel = Color(actual.getPixel(bounds.left.toInt() + x, bounds.top.toInt() + y))
                    assertTrue("Tinted card in $theme at $fraction: expected $target, got $pixel",
                        maxOf(abs(pixel.red - target.red), abs(pixel.green - target.green),
                            abs(pixel.blue - target.blue)) < 0.012f)
                }
                expected.recycle()
                actual.recycle()
            }
        }
    }

    @Test fun wordsReadDisplays203KOnTheInsightsPage() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            ReadingStatisticsContent(ReadingStatisticsUiState(loading = false, statistics = statistics, now = now), {})
        } }
        compose.onNodeWithText("words read").assertIsDisplayed()
        compose.onNodeWithText("203K").assertIsDisplayed()
        compose.onNodeWithText("202.6K").assertDoesNotExist()
    }
}
