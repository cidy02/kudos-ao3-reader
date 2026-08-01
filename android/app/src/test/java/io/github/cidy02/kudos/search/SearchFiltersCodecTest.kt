package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchFiltersCodecTest {
    @Test
    fun roundTripsFullFilterSet() {
        val original = AO3SearchFilters(
            query = "slow burn",
            fandom = "Naruto",
            characters = "Naruto, Sasuke",
            relationships = "Naruto/Sasuke",
            additionalTags = "Fluff",
            excludedFandoms = "Crossover",
            excludedCharacters = "Sakura",
            excludedRelationships = "Naruto/Hinata",
            excludedAdditionalTags = "Angst",
            rating = AO3Rating.MATURE,
            ratingMatch = AO3RatingMatch.OR_HIGHER,
            includeNotRated = false,
            warnings = setOf(AO3Warning.VIOLENCE, AO3Warning.DEATH),
            excludedWarnings = setOf(AO3Warning.UNDERAGE),
            categories = setOf(AO3Category.MM),
            excludedCategories = setOf(AO3Category.OTHER),
            crossover = AO3Crossover.EXCLUDE,
            completion = AO3Completion.COMPLETE,
            wordsFrom = "1000",
            wordsTo = "50000",
            updated = AO3Updated.YEAR,
            language = AO3Language.ENGLISH,
            sort = AO3SearchSort.KUDOS
        )

        val encoded = SearchFiltersCodec.encode(original)
        val decoded = SearchFiltersCodec.decode(encoded)

        assertEquals(original, decoded)
        assertTrue(encoded.contains("\"rating\":\"mature\""))
        assertTrue(encoded.contains("\"ratingMatch\":\"orHigher\""))
        assertTrue(encoded.contains("\"sort\":\"kudos\""))
        assertTrue(encoded.contains("\"violence\""))
        assertTrue(encoded.contains("\"mm\""))
    }

    @Test
    fun roundTripsEmptyDefaults() {
        val original = AO3SearchFilters()
        assertEquals(original, SearchFiltersCodec.decode(SearchFiltersCodec.encode(original)))
    }

    @Test
    fun decodesAppleStylePayload() {
        val appleJson = """
            {
              "query": "found family",
              "fandom": "The Untamed",
              "characters": "",
              "relationships": "",
              "additionalTags": "",
              "excludedFandoms": "",
              "excludedCharacters": "",
              "excludedRelationships": "",
              "excludedAdditionalTags": "",
              "rating": "teen",
              "ratingMatch": "exact",
              "includeNotRated": true,
              "warnings": ["noWarnings"],
              "excludedWarnings": [],
              "categories": ["mm"],
              "excludedCategories": [],
              "crossover": "any",
              "completion": "complete",
              "wordsFrom": "",
              "wordsTo": "",
              "updated": "any",
              "language": "english",
              "sort": "dateUpdated"
            }
        """.trimIndent()

        val filters = SearchFiltersCodec.decode(appleJson)
        assertEquals("found family", filters.query)
        assertEquals("The Untamed", filters.fandom)
        assertEquals(AO3Rating.TEEN, filters.rating)
        assertEquals(setOf(AO3Warning.NO_WARNINGS), filters.warnings)
        assertEquals(setOf(AO3Category.MM), filters.categories)
        assertEquals(AO3Completion.COMPLETE, filters.completion)
        assertEquals(AO3SearchSort.DATE_UPDATED, filters.sort)
    }

    @Test
    fun blankOrInvalidJsonFallsBackToEmptyFilters() {
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode(""))
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode("not-json"))
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode("{}"))
    }

    @Test
    fun unknownEnumValuesUseDefaults() {
        val json = """
            {
              "query": "x",
              "rating": "not-a-rating",
              "sort": "mystery",
              "warnings": ["noWarnings", "unknownWarning"]
            }
        """.trimIndent()

        val filters = SearchFiltersCodec.decode(json)
        assertEquals("x", filters.query)
        assertEquals(AO3Rating.ANY, filters.rating)
        assertEquals(AO3SearchSort.RELEVANCE, filters.sort)
        assertEquals(setOf(AO3Warning.NO_WARNINGS), filters.warnings)
        // Known warning is kept; unknown enum token is dropped.
        assertTrue(filters.hasActiveFilters)
    }
}
