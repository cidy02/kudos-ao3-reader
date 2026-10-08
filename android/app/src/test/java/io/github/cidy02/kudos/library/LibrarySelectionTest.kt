package io.github.cidy02.kudos.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LibrarySelectionTest {
    @Test
    fun toggleAddsWhenMissing() {
        val next = LibrarySelection.toggle(emptySet(), "w1")
        assertEquals(setOf("w1"), next)
        assertTrue(LibrarySelection.isSelected(next, "w1"))
    }

    @Test
    fun toggleRemovesWhenPresent() {
        val next = LibrarySelection.toggle(setOf("w1", "w2"), "w1")
        assertEquals(setOf("w2"), next)
        assertFalse(LibrarySelection.isSelected(next, "w1"))
    }

    @Test
    fun selectOnlyReplacesSet() {
        assertEquals(setOf("w9"), LibrarySelection.selectOnly("w9"))
    }

    /** iOS `selectedWorks`: a bulk action reaches only rows still on screen (audits A5-5, A5-6). */
    @Test
    fun aRowAFilterHidesLeavesTheSelection() {
        val selected = setOf("complete", "wip")
        assertEquals(setOf("wip"), LibrarySelection.visible(selected, setOf("wip", "other")))
        assertTrue(LibrarySelection.visible(selected, emptySet()).isEmpty())
        // Nothing hidden: the same set, so nothing is rewritten.
        assertTrue(LibrarySelection.visible(selected, setOf("complete", "wip", "other")) === selected)
    }

    @Test
    fun clearEmptiesSelection() {
        assertTrue(LibrarySelection.clear().isEmpty())
    }
}
