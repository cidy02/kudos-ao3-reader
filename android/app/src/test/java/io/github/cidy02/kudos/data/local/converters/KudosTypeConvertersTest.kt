package io.github.cidy02.kudos.data.local.converters

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KudosTypeConvertersTest {
    private val converters = KudosTypeConverters()

    @Test
    fun roundTripsAStringList() {
        val json = converters.stringListToJson(listOf("Angst", "Fluff"))
        assertEquals(listOf("Angst", "Fluff"), converters.jsonToStringList(json))
    }

    @Test
    fun blankOrNullDecodesToEmptyList() {
        assertTrue(converters.jsonToStringList(null).isEmpty())
        assertTrue(converters.jsonToStringList("").isEmpty())
    }

    @Test
    fun corruptedJsonDegradesToEmptyListInsteadOfThrowing() {
        // A partial write or format drift must not crash every query touching
        // this column (WorkEntity has seven of them) — see KudosTypeConverters.
        assertTrue(converters.jsonToStringList("""["Angst", "Fl""").isEmpty())
        assertTrue(converters.jsonToStringList("not json at all").isEmpty())
    }
}
