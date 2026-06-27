package io.github.cidy02.kudos.network.ao3.search

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SearchUrlBuilderTest {
    private val builder = AO3SearchUrlBuilder()

    @Test
    fun buildsAppleCompatibleSearchUrl() {
        val filters = AO3SearchFilters(
            query = "found family",
            fandom = "Naruto",
            characters = "Hinata Hyuuga",
            relationships = "Naruto/Hinata",
            additionalTags = "Fluff",
            rating = AO3Rating.MATURE,
            includeNotRated = false,
            warnings = setOf(AO3Warning.NO_WARNINGS, AO3Warning.UNDERAGE),
            categories = setOf(AO3Category.GEN),
            crossover = AO3Crossover.EXCLUDE,
            completion = AO3Completion.COMPLETE,
            wordsFrom = "1000",
            wordsTo = "50000",
            updated = AO3Updated.WEEK,
            language = AO3Language.ENGLISH,
            sort = AO3SearchSort.KUDOS
        )

        val url = builder.buildSearchUrl(filters, page = 1).toHttpUrl()

        assertEquals("https", url.scheme)
        assertEquals("archiveofourown.org", url.host)
        assertEquals("/works/search", url.encodedPath)
        assertEquals("found family", url.queryParameter("work_search[query]"))
        assertEquals("Naruto", url.queryParameter("work_search[fandom_names]"))
        assertEquals("Hinata Hyuuga", url.queryParameter("work_search[character_names]"))
        assertEquals("Naruto/Hinata", url.queryParameter("work_search[relationship_names]"))
        assertEquals("Fluff", url.queryParameter("work_search[freeform_names]"))
        assertEquals("12", url.queryParameter("work_search[rating_ids]"))
        assertEquals(
            listOf("16", "20"),
            url.queryParameterValues("work_search[archive_warning_ids][]")
        )
        assertEquals(listOf("21"), url.queryParameterValues("work_search[category_ids][]"))
        assertEquals("F", url.queryParameter("work_search[crossover]"))
        assertEquals("T", url.queryParameter("work_search[complete]"))
        assertEquals("1000-50000", url.queryParameter("work_search[word_count]"))
        assertEquals("< 1 week ago", url.queryParameter("work_search[revised_at]"))
        assertEquals("en", url.queryParameter("work_search[language_id]"))
        assertEquals("kudos_count", url.queryParameter("work_search[sort_column]"))
        assertEquals("1", url.queryParameter("page"))
    }
}

class AO3SearchQueryBuilderTest {
    @Test
    fun exactRatingUsesStructuredFieldWhenNotRatedIsExcluded() {
        val filters = AO3SearchFilters(
            query = "slow burn",
            rating = AO3Rating.MATURE,
            includeNotRated = false
        )

        assertEquals("slow burn", filters.searchQuery)
        assertEquals("12", filters.structuredRatingId)
    }

    @Test
    fun ratingPlusUsesSearchExpression() {
        val filters = AO3SearchFilters(
            rating = AO3Rating.MATURE,
            ratingMatch = AO3RatingMatch.OR_HIGHER,
            includeNotRated = false
        )

        assertEquals("(rating_ids:12 OR rating_ids:13)", filters.searchQuery)
        assertNull(filters.structuredRatingId)
    }

    @Test
    fun ratingMinusCanIncludeUnratedWorks() {
        val filters = AO3SearchFilters(
            rating = AO3Rating.TEEN,
            ratingMatch = AO3RatingMatch.OR_LOWER,
            includeNotRated = true
        )

        assertEquals("(rating_ids:10 OR rating_ids:11 OR rating_ids:9)", filters.searchQuery)
        assertNull(filters.structuredRatingId)
    }

    @Test
    fun anyRatingCanExcludeUnratedWorks() {
        val filters = AO3SearchFilters(includeNotRated = false)

        assertTrue(filters.hasActiveFilters)
        assertEquals("-rating_ids:9", filters.searchQuery)
    }
}

class AO3SearchSortMappingTest {
    @Test
    fun matchesCurrentAppleSortEnum() {
        val mapping = AO3SearchSort.entries.associate { it.appleCaseName to it.sortColumn }

        assertEquals(null, mapping["relevance"])
        assertEquals("revised_at", mapping["dateUpdated"])
        assertEquals("created_at", mapping["datePosted"])
        assertEquals("word_count", mapping["words"])
        assertEquals("kudos_count", mapping["kudos"])
        assertEquals("hits", mapping["hits"])
        assertEquals("comments_count", mapping["comments"])
        assertEquals("bookmarks_count", mapping["bookmarks"])
        assertFalse(mapping.containsKey("title"))
        assertFalse(mapping.containsKey("author"))
    }
}

class AO3SearchWordCountTest {
    private val builder = AO3SearchUrlBuilder()

    @Test
    fun buildsWordCountExpressions() {
        assertEquals(
            "1000-5000",
            builder.wordCountExpression(AO3SearchFilters(wordsFrom = "1000", wordsTo = "5000"))
        )
        assertEquals("> 1000", builder.wordCountExpression(AO3SearchFilters(wordsFrom = "1000")))
        assertEquals("< 5000", builder.wordCountExpression(AO3SearchFilters(wordsTo = "5000")))
        assertNull(builder.wordCountExpression(AO3SearchFilters()))
    }

    @Test
    fun passesRawValuesThroughLikeApple() {
        // Apple trims and forwards the raw strings, so comma-formatted values must
        // survive and only blank sides are dropped.
        assertEquals(
            "10,000-50,000",
            builder.wordCountExpression(AO3SearchFilters(wordsFrom = "10,000", wordsTo = "50,000"))
        )
        assertEquals("> 1000", builder.wordCountExpression(AO3SearchFilters(wordsFrom = " 1000 ")))
        assertEquals("< 5000", builder.wordCountExpression(AO3SearchFilters(wordsFrom = "   ", wordsTo = "5000")))
        assertNull(builder.wordCountExpression(AO3SearchFilters(wordsFrom = "  ", wordsTo = "")))
    }
}

class AO3SearchIncludeExcludeTest {
    @Test
    fun exclusionsBecomeDeduplicatedQueryClauses() {
        val filters = AO3SearchFilters(
            excludedFandoms = "Naruto, Star Wars",
            excludedCharacters = "Naruto",
            excludedRelationships = "Alice/Bob",
            excludedWarnings = setOf(AO3Warning.NO_WARNINGS, AO3Warning.UNDERAGE),
            excludedCategories = setOf(AO3Category.MM, AO3Category.OTHER)
        )

        assertEquals(
            "-\"Naruto\" -\"Star Wars\" -\"Alice/Bob\" " +
                "-archive_warning_ids:16 -archive_warning_ids:20 " +
                "-category_ids:23 -category_ids:24",
            filters.searchQuery
        )
    }
}

class AO3SearchEmptyFieldOmissionTest {
    @Test
    fun omitsEmptyFieldsButAlwaysIncludesPage() {
        val url = AO3SearchUrlBuilder()
            .buildSearchUrl(AO3SearchFilters(query = "  "), page = 1)
            .toHttpUrl()

        assertNull(url.queryParameter("work_search[query]"))
        assertNull(url.queryParameter("work_search[sort_column]"))
        assertNull(url.queryParameter("work_search[rating_ids]"))
        assertEquals("1", url.queryParameter("page"))
    }
}

class AO3SearchPaginationTest {
    @Test
    fun pageIsOneBasedAndClamped() {
        val builder = AO3SearchUrlBuilder()

        assertEquals(
            "1",
            builder.buildSearchUrl(AO3SearchFilters(query = "test"), page = 1)
                .toHttpUrl()
                .queryParameter("page")
        )
        assertEquals(
            "1",
            builder.buildSearchUrl(AO3SearchFilters(query = "test"), page = -3)
                .toHttpUrl()
                .queryParameter("page")
        )
    }
}
