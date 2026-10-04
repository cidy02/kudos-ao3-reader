package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchLocalMatchesTest {

    @Test
    fun searchSubjectPrefersOneTagNameOverTheQuery() {
        val single = AO3SearchFilters(query = "slow burn", fandom = "Naruto")
        assertEquals("Naruto", single.searchSubject().text)
        assertEquals(SearchSubjectField.FANDOM, single.searchSubject().field)

        val character = AO3SearchFilters(characters = "Sasuke")
        assertEquals(SearchSubjectField.CHARACTER, character.searchSubject().field)

        val twoFields = AO3SearchFilters(fandom = "Naruto", characters = "Sasuke", query = "slow burn")
        assertEquals("slow burn", twoFields.searchSubject().text)
        assertNull(twoFields.searchSubject().field)

        val twoNames = AO3SearchFilters(fandom = "Naruto, Boruto")
        assertEquals(SEARCH_RESULTS_FALLBACK, twoNames.searchSubject().text)

        assertEquals(SEARCH_RESULTS_FALLBACK, AO3SearchFilters().searchSubject().text)
    }

    @Test
    fun emptyQueryReturnsNoLocalMatches() {
        val matches = computeSearchLocalMatches(
            query = "   ",
            works = listOf(work("Alpha")),
            tags = listOf(Tag(name = "Alpha")),
            collections = listOf(WorkCollection(name = "Alpha")),
            catalogFandoms = listOf(AO3Fandom("Alpha", 10))
        )
        assertTrue(matches.isEmpty)
    }

    @Test
    fun localMatchesCapAndFoldDiacritics() {
        val works = (1..21).map { work("Alpha $it") } + work("Other")
        val tags = (1..13).map { Tag(name = "Alpha tag $it") }
        val collections = (1..13).map { WorkCollection(name = "Alpha set $it") }
        val matches = computeSearchLocalMatches(
            query = "alpha",
            works = works,
            tags = tags,
            collections = collections,
            catalogFandoms = emptyList()
        )
        assertEquals(20, matches.works.size)
        assertEquals("Alpha 1", matches.works.first().title)
        assertEquals(12, matches.tags.size)
        assertEquals(12, matches.collections.size)

        val folded = computeSearchLocalMatches(
            query = "pokemon",
            works = listOf(work("Pokémon Adventure")),
            tags = emptyList(),
            collections = emptyList(),
            catalogFandoms = emptyList()
        )
        assertEquals(listOf("Pokémon Adventure"), folded.works.map { it.title })
    }

    @Test
    fun ao3FandomsDropNamesAlreadyInTheLibrary() {
        val matches = computeSearchLocalMatches(
            query = "naru",
            works = listOf(work("Tale", fandoms = listOf("Naruto"))),
            tags = emptyList(),
            collections = emptyList(),
            catalogFandoms = listOf(
                AO3Fandom("Naruto", 100),
                AO3Fandom("Naruto Shippuden", 40)
            )
        )
        assertEquals(listOf("Naruto"), matches.libraryFandoms)
        assertEquals(listOf("Naruto Shippuden"), matches.ao3Fandoms.map { it.name })
    }

    @Test
    fun rankedFandomsPreferPrefixThenCount() {
        val ranked = rankedCachedFandoms(
            fandoms = listOf(
                AO3Fandom("The Warm Place", 500),
                AO3Fandom("Warm Blanket", 2),
                AO3Fandom("Warm Blanket", 9),
                AO3Fandom("Unrelated", 1000)
            ),
            normalizedQuery = "warm"
        )
        assertEquals(listOf("Warm Blanket", "The Warm Place"), ranked.map { it.name })
        assertEquals(9, ranked.first().workCount)

        val capped = rankedCachedFandoms(
            fandoms = (1..13).map { AO3Fandom("Warm $it", it) },
            normalizedQuery = "warm",
            limit = 12
        )
        assertEquals(12, capped.size)
    }

    @Test
    fun retryPageFollowsResultsOnScreen() {
        assertNull(searchRetryPage(requested = 7, current = 1, hasResults = false))
        assertEquals(7, searchRetryPage(requested = 7, current = 1, hasResults = true))
        assertEquals(3, searchRetryPage(requested = null, current = 3, hasResults = true))
    }

    @Test
    fun includedFandomDropsTheSameExcludedName() {
        val next = withIncludedFandom(
            AO3SearchFilters(excludedFandoms = "naruto, Bleach"),
            "Naruto"
        )
        assertEquals("Naruto", next.fandom)
        assertEquals("Bleach", next.excludedFandoms)
    }

    @Test
    fun tappedTagsUseTheirAo3SearchFields() {
        assertEquals("Naruto", tagSearchFilters(SearchSubjectField.FANDOM, "Naruto").fandom)
        assertEquals("Sasuke", tagSearchFilters(SearchSubjectField.CHARACTER, "Sasuke").characters)
        assertEquals(
            "Naruto/Sasuke",
            tagSearchFilters(SearchSubjectField.RELATIONSHIP, "Naruto/Sasuke").relationships
        )
        assertEquals("Slow Burn", tagSearchFilters(SearchSubjectField.FREEFORM, "Slow Burn").additionalTags)
        assertEquals(
            setOf(AO3Warning.DEATH),
            tagSearchFilters(SearchSubjectField.WARNING, "Major Character Death").warnings
        )
        assertEquals(
            "Unrecognized warning",
            tagSearchFilters(SearchSubjectField.WARNING, "Unrecognized warning").additionalTags
        )
    }

    private fun work(title: String, fandoms: List<String> = emptyList()) =
        SavedWork(title = title, author = "A", workFandoms = fandoms)
}
