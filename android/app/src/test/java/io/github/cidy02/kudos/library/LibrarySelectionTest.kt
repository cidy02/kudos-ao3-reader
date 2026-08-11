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

    @Test
    fun clearEmptiesSelection() {
        assertTrue(LibrarySelection.clear().isEmpty())
    }
}
