package io.github.cidy02.kudos.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/** Brief 3dr: the Settings hub names the chosen font; it always said "System". */
class ReaderFontNameTest {
    @Test fun theChosenFontIsNamedAndAMissingOneIsSystem() {
        assertEquals("Georgia", ReaderFontCatalog.name("georgia", emptyList()))
        assertEquals("System", ReaderFontCatalog.name("custom:gone.ttf", emptyList()))
    }
}
