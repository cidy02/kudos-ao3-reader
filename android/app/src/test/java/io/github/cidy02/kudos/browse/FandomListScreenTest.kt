package io.github.cidy02.kudos.browse

import org.junit.Assert.assertEquals
import org.junit.Test

class FoldDiacriticsTest {
    @Test
    fun foldsAccentsAndCaseSoPlainAsciiQueryMatches() {
        assertEquals("pokemon", foldDiacritics("Pokémon"))
        assertEquals(foldDiacritics("pokemon"), foldDiacritics("Pokémon"))
        assertEquals("naruto", foldDiacritics("Naruto"))
    }
}
