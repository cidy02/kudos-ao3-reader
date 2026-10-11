package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AvatarInitialTest {
    @Test
    fun theFirstVisibleCharacterUppercased() {
        assertEquals("R", avatarInitial("ReaderOne"))
        assertEquals("T", avatarInitial("  tagfan"))
        // A character outside the basic plane is one letter, not half of one.
        assertEquals("😀", avatarInitial("😀fan"))
    }

    @Test
    fun aNameWithNothingInItHasNone() {
        assertNull(avatarInitial(null))
        assertNull(avatarInitial("   "))
    }
}
