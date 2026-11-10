package io.github.cidy02.kudos.ui.subject

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UpdateMarkerTextTest {
    @Test
    fun plusFootersShowTheirCountOnly() {
        assertEquals("+3", updateMarkerText("+3 new"))
        assertEquals("+12", updateMarkerText("+12 CH"))
        assertEquals("+", updateMarkerText("+"))
        assertNull(updateMarkerText("Updated"))
    }

    @Test
    fun spokenLabelNamesChapters() {
        assertEquals("1 new chapter", newChaptersSpoken("+1"))
        assertEquals("4 new chapters", newChaptersSpoken("+4"))
        assertEquals("+", newChaptersSpoken("+"))
    }
}
