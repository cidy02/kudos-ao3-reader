package io.github.cidy02.kudos.ui.subject

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ParseStoredColorTest {
    @Test
    fun acceptsOnlySixHexDigitsWithOrWithoutHash() {
        assertNotNull(parseStoredColor("#1A2B3C"))
        assertNotNull(parseStoredColor("1a2b3c"))
        assertNull(parseStoredColor("-12345A"))
        assertNull(parseStoredColor("+12345A"))
        assertNull(parseStoredColor("#12345G"))
    }
}
