package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import io.github.cidy02.kudos.ui.subject.HomeStatusArrangement
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.math.abs
import kotlin.math.pow

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class WorkSymbolTileTest {
    @get:Rule val compose = createComposeRule()
    @Test fun ratingsUseTheBoardPaletteAndTeenContrast() {
        assertEquals(
            WorkSymbolTile(WorkSymbolMark.Shield("G"), Color(0xFF2F8F3A), Color.White),
            WorkSymbolTile.rating("General Audiences", dark = false)
        )
        assertEquals(
            WorkSymbolTile(WorkSymbolMark.Shield("T"), Color(0xFFF5C400), Color(0xFF3A2C00)),
            WorkSymbolTile.rating("Teen And Up Audiences", dark = true)
        )
        assertEquals(Color(0xFFE07000), WorkSymbolTile.rating("Mature", false).fill)
        assertEquals(Color(0xFFC8102E), WorkSymbolTile.rating("Explicit", true).fill)
    }

    @Test fun absentStatesUseTheThemeSpecificGreys() {
        val light = WorkSymbolTile.rating(null, dark = false)
        assertEquals(WorkSymbolMark.Shield("?"), light.mark)
        assertEquals(Color(0xFFE6E6EB), light.fill)
        assertEquals(Color(0xFF6C6C70), light.ink)

        val dark = WorkSymbolTile.category(emptyList(), dark = true)
        assertEquals(WorkSymbolMark.Dash, dark.mark)
        assertEquals(Color(0xFF3A3A3C), dark.fill)
        assertEquals(Color(0xFFAEAEB2), dark.ink)
    }

    @Test fun categoriesUseTheirOwnMarksAndCollapseToMulti() {
        assertEquals(WorkSymbolMark.FemaleFemale, WorkSymbolTile.category(listOf("F/F"), false).mark)
        assertEquals(Color(0xFFD2264B), WorkSymbolTile.category(listOf("F/F"), false).fill)
        assertEquals(WorkSymbolMark.FemaleMale, WorkSymbolTile.category(listOf("F/M"), false).mark)
        assertEquals(WorkSymbolMark.MaleMale, WorkSymbolTile.category(listOf("M/M"), false).mark)
        assertEquals(WorkSymbolMark.Gen, WorkSymbolTile.category(listOf("Gen"), false).mark)
        assertEquals(Color(0xFF48484A), WorkSymbolTile.category(listOf("Other"), true).fill)
        assertEquals(WorkSymbolMark.Multi, WorkSymbolTile.category(listOf("F/F", "M/M"), false).mark)
        assertEquals(WorkSymbolMark.Multi, WorkSymbolTile.category(listOf("Multi"), false).mark)
        assertEquals(WorkSymbolMark.MaleMale, WorkSymbolTile.category(listOf("M/M", "Not A Category"), false).mark)
        assertEquals(Color(0xFFB3127A), WorkSymbolTile.category(listOf("F/M"), false).fill)
        assertEquals(Color(0xFF1E63C8), WorkSymbolTile.category(listOf("M/M"), false).fill)
        assertEquals(Color.White, WorkSymbolTile.category(listOf("F/F"), false).ink)
        assertEquals(Color.White, WorkSymbolTile.rating("Explicit", true).ink)
        assertEquals(
            WorkSymbolTile.rating("Explicit", false),
            WorkSymbolTile.rating("Explicit", true)
        )
    }

    @Test fun notRatedIsAnAbsentShield() {
        val tile = WorkSymbolTile.rating("Not Rated", dark = false)
        assertEquals(WorkSymbolMark.Shield("?"), tile.mark)
        assertEquals(Color(0xFFE6E6EB), tile.fill)
        assertEquals(Color(0xFF6C6C70), tile.ink)
    }

    @Test fun everyGlyphHoldsThreeToOneOnItsTile() {
        for (dark in listOf(false, true)) {
            for (tile in sampleTiles(dark)) {
                assertTrue(
                    "${tile.mark} dark=$dark contrast ${contrastRatio(tile.ink, tile.fill)}",
                    contrastRatio(tile.ink, tile.fill) >= 3.0
                )
            }
        }
    }

    @Test fun drawnMarksAreCentredOnTheirInk() {
        val centred = listOf(
            WorkSymbolMark.Shield("G"),
            WorkSymbolMark.Gen,
            WorkSymbolMark.Dash,
            WorkSymbolMark.HalfRing
        )
        centred.forEach { mark ->
            val shift = WorkSymbolGeometry.inkShift(mark)
            assertEquals("$mark x", 0f, shift.x, 0.001f)
            assertEquals("$mark y", 0f, shift.y, 0.001f)
        }
        assertEquals(0f, WorkSymbolGeometry.inkShift(WorkSymbolMark.FemaleFemale).x, 0.001f)
        assertEquals(0.8f, WorkSymbolGeometry.inkShift(WorkSymbolMark.FemaleFemale).y, 0.001f)
        assertEquals(0f, WorkSymbolGeometry.inkShift(WorkSymbolMark.Other).x, 0.001f)
        assertEquals(-0.7f, WorkSymbolGeometry.inkShift(WorkSymbolMark.Other).y, 0.001f)
        val maleMale = WorkSymbolGeometry.inkShift(WorkSymbolMark.MaleMale)
        assertEquals(0.7766f, maleMale.x, 0.001f)
        assertEquals(-0.9766f, maleMale.y, 0.001f)
        val femaleMale = WorkSymbolGeometry.inkShift(WorkSymbolMark.FemaleMale)
        assertEquals(-0.2491f, femaleMale.x, 0.001f)
        assertEquals(-0.4509f, femaleMale.y, 0.001f)
        val check = WorkSymbolGeometry.inkShift(WorkSymbolMark.Check)
        assertEquals(-0.1f, check.x, 0.001f)
        assertEquals(-0.25f, check.y, 0.001f)
        assertEquals(androidx.compose.ui.geometry.Offset.Zero, WorkSymbolGeometry.inkShift(WorkSymbolMark.Multi))
    }

    @Test fun gridHeightIsTwoTilesAndOneGap() {
        assertEquals(0.12f, WorkSymbolGeometry.GapRatio, 0f)
        assertEquals(0.24f, WorkSymbolGeometry.CornerRadiusRatio, 0f)
        assertTrue(abs(WorkSymbolGeometry.gridExtent(24f) - 50.88f) < 0.001f)
    }

    @Test fun backingPaddingAndRadiusRoundTheTileFraction() {
        val cases = listOf(
            Triple(22f, 6f, 13f),
            Triple(24f, 6f, 14f),
            Triple(26f, 7f, 15f)
        )
        for ((tile, pad, radius) in cases) {
            assertEquals(pad, WorkSymbolGeometry.backingPadding(tile), 0f)
            assertEquals(radius, WorkSymbolGeometry.backingCornerRadius(tile), 0f)
        }
    }

    @Test fun backingFollowsTheVariantAndPlainDefaultGridIsBackedAndSilent() {
        assertTrue(WorkSymbolGeometry.drawsBacking(HomeStatusArrangement.Grid, backed = true))
        assertFalse(WorkSymbolGeometry.drawsBacking(HomeStatusArrangement.Grid, backed = false))
        assertFalse(WorkSymbolGeometry.drawsBacking(HomeStatusArrangement.Strip, backed = true))
        assertFalse(WorkSymbolGeometry.drawsBacking(HomeStatusArrangement.Strip, backed = false))
        assertTrue(abs(WorkSymbolGeometry.outerSide(24f) - 62.88f) < 0.001f)
        assertTrue(abs(WorkSymbolGeometry.outerSide(24f, backed = false) - 50.88f) < 0.001f)

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                androidx.compose.foundation.layout.Column {
                    HomeStatusTray(
                        rating = "General Audiences",
                        categories = listOf("Gen"),
                        warnings = emptyList(),
                        isComplete = true,
                        modifier = Modifier.testTag("defaultGrid")
                    )
                    HomeStatusTray(
                        rating = "General Audiences",
                        categories = listOf("Gen"),
                        warnings = emptyList(),
                        isComplete = true,
                        backed = false,
                        announces = true,
                        modifier = Modifier.testTag("unbackedAnnouncingGrid")
                    )
                }
            }
        }
        val defaultNode = compose.onNodeWithTag("defaultGrid", useUnmergedTree = true).fetchSemanticsNode()
        val unbackedNode = compose.onNodeWithTag("unbackedAnnouncingGrid", useUnmergedTree = true).fetchSemanticsNode()
        val defaultWidthDp = with(compose.density) { defaultNode.size.width.toDp().value }
        val unbackedWidthDp = with(compose.density) { unbackedNode.size.width.toDp().value }
        assertEquals(62.88f, defaultWidthDp, 1.0f)
        assertEquals(50.88f, unbackedWidthDp, 1.0f)
        assertFalse(defaultNode.config.contains(SemanticsProperties.ContentDescription))
        assertTrue(unbackedNode.config.contains(SemanticsProperties.ContentDescription))
    }

    @Test fun backingColoursMatchTheBoard() {
        val sepia = WorkSymbolBackingColor.board(ReaderTheme.Sepia)
        assertEquals(120f / 255f, sepia.red, 0.0001f)
        assertEquals(92f / 255f, sepia.green, 0.0001f)
        assertEquals(56f / 255f, sepia.blue, 0.0001f)
        assertEquals(0.12f, sepia.alpha, 0.0001f)

        val light = WorkSymbolBackingColor.board(ReaderTheme.Light)
        assertEquals(118f / 255f, light.red, 0.0001f)
        assertEquals(118f / 255f, light.green, 0.0001f)
        assertEquals(128f / 255f, light.blue, 0.0001f)
        assertEquals(0.12f, light.alpha, 0.0001f)

        for (theme in listOf(ReaderTheme.Dark, ReaderTheme.Oled)) {
            val fill = WorkSymbolBackingColor.board(theme)
            assertEquals(light.red, fill.red, 0.0001f)
            assertEquals(light.green, fill.green, 0.0001f)
            assertEquals(light.blue, fill.blue, 0.0001f)
            assertEquals(0.24f, fill.alpha, 0.0001f)
        }
    }

    @Test fun warningAndCompletionMarksMatchIos() {
        assertEquals(WorkSymbolMark.Dash, WorkSymbolTile.warnings(emptyList(), false).mark)
        assertEquals(
            WorkSymbolMark.Question,
            WorkSymbolTile.warnings(listOf("Creator Chose Not To Use Archive Warnings"), false).mark
        )
        assertEquals(
            WorkSymbolMark.Exclamation,
            WorkSymbolTile.warnings(listOf("Major Character Death"), false).mark
        )
        assertEquals(WorkSymbolMark.Check, WorkSymbolTile.completion(true, false).mark)
        assertEquals(WorkSymbolMark.HalfRing, WorkSymbolTile.completion(false, false).mark)
        assertEquals(Color(0xFFFFE6C2), WorkSymbolTile.completion(false, false).fill)
        assertEquals(Color(0xFF4A2E0A), WorkSymbolTile.completion(false, true).fill)
        assertEquals(WorkSymbolMark.Question, WorkSymbolTile.completion(null, true).mark)
    }

    private fun sampleTiles(dark: Boolean): List<WorkSymbolTile> {
        val ratings = listOf("General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated", null)
        val categories = listOf(listOf("F/F"), listOf("F/M"), listOf("M/M"), listOf("Gen"), listOf("Other"), emptyList())
        val warnings = listOf(
            emptyList(),
            listOf("Creator Chose Not To Use Archive Warnings"),
            listOf("Major Character Death")
        )
        val completions = listOf(true, false, null)
        return ratings.map { WorkSymbolTile.rating(it, dark) } +
            categories.map { WorkSymbolTile.category(it, dark) } +
            warnings.map { WorkSymbolTile.warnings(it, dark) } +
            completions.map { WorkSymbolTile.completion(it, dark) }
    }

    /** WCAG relative-luminance contrast. Same bar as iOS `everyGlyphHoldsThreeToOneOnItsTile`. */
    private fun contrastRatio(ink: Color, fill: Color): Double {
        fun channel(value: Float): Double {
            val v = value.toDouble()
            return if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        }
        fun luminance(color: Color) =
            0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        val lighter = maxOf(luminance(ink), luminance(fill))
        val darker = minOf(luminance(ink), luminance(fill))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
