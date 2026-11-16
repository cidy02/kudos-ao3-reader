package io.github.cidy02.kudos.library

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import org.junit.Assert.assertFalse
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
class YearChartCopyTest {
    @get:Rule val compose = createComposeRule()

    @Test fun yearKeyExplainsTheNumberAtTwoTimesFontScale() {
        val now = Instant.parse("2026-10-15T12:00:00Z")
        val zone = ZoneId.of("UTC")
        val timeline = ReadingHistoryTimeline.make(
            scope = ReadingHistoryScope.Year, reference = now, facts = emptyList(),
            now = now, zone = zone, weekFields = WeekFields.ISO
        )
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                KudosTheme(KudosThemeMode.Light) { YearChart(timeline, zone, Locale.US) }
            }
        }
        val key = compose.onNodeWithText("Number above a bar = works finished")
        key.assertExists()
        compose.onNodeWithText("Works finished").assertDoesNotExist()
        val layouts = mutableListOf<TextLayoutResult>()
        key.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { result ->
            assertFalse(result.didOverflowHeight)
            assertFalse(result.multiParagraph.didExceedMaxLines)
            (0 until result.lineCount).forEach { assertFalse(result.isLineEllipsized(it)) }
        }
    }
}
