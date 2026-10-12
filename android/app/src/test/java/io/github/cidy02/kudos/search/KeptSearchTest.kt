package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import org.junit.Assert.*
import org.junit.Test

class KeptSearchTest {
    @Test fun aPageOfASearchComesBackAsItWas() {
        val filters = AO3SearchFilters(query = "lanterns \"at\" dawn\nsecond line", fandom = "Star Wars - All Media Types")
        val (page, back) = KeptSearch.read(KeptSearch.write(3, filters))!!
        assertEquals(3, page)
        assertEquals(filters.query, back.query)
        assertEquals(filters.fandom, back.fandom)
    }

    @Test fun nothingToRunIsNothingKept() {
        assertNull(KeptSearch.read(KeptSearch.write(1, AO3SearchFilters())))
        assertNull(KeptSearch.read("not a page"))
        assertNull(KeptSearch.read("2\nnot json"))
    }
}
