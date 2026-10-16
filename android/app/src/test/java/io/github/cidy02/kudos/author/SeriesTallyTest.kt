package io.github.cidy02.kudos.author

import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesSummary
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS WritingScreensPresentationTests series-tally assertions. */
class SeriesTallyTest {
    private fun series(works: Int?, words: Int?) = AO3AuthorSeriesSummary(
        id = 1, title = "Series", creators = emptyList(), fandoms = emptyList(), summary = "",
        words = words, workCount = works, dateUpdated = "", isComplete = null, url = "")

    @Test fun sumsKnownFiguresAndQualifiesBothPartialTotals() {
        assertEquals(listOf("9 works", "219,300 words"),
            seriesTallyParts(listOf(series(3, 118600), series(6, 100700)), false))
        assertEquals(listOf("9 works, 300 words in the 2 loaded series"),
            seriesTallyParts(listOf(series(2, 100), series(7, 200)), true))
        assertEquals(listOf("1 work in the 1 loaded series"), seriesTallyParts(listOf(series(1, null)), true))
        assertEquals(emptyList<String>(), seriesTallyParts(listOf(series(null, null)), false))
        assertEquals(emptyList<String>(), seriesTallyParts(emptyList(), true))
    }
}
