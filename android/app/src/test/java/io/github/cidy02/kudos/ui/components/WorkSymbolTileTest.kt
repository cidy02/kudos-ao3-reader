package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

class WorkSymbolTileTest {
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
