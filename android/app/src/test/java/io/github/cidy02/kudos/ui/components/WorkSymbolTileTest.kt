package io.github.cidy02.kudos.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

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
}
