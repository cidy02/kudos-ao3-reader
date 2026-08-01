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

class SearchFilterHelpersTest {
    @Test
    fun filterSelectionStateCyclesClearIncludeExclude() {
        assertEquals(FilterSelectionState.INCLUDED, FilterSelectionState.CLEAR.next)
        assertEquals(FilterSelectionState.EXCLUDED, FilterSelectionState.INCLUDED.next)
        assertEquals(FilterSelectionState.CLEAR, FilterSelectionState.EXCLUDED.next)
    }

    @Test
    fun cycleWarningMovesThroughThreeStates() {
        var filters = AO3SearchFilters()
        assertEquals(FilterSelectionState.CLEAR, warningSelection(filters, AO3Warning.VIOLENCE))

        filters = cycleWarning(filters, AO3Warning.VIOLENCE)
        assertEquals(setOf(AO3Warning.VIOLENCE), filters.warnings)
        assertTrue(filters.excludedWarnings.isEmpty())
        assertEquals(FilterSelectionState.INCLUDED, warningSelection(filters, AO3Warning.VIOLENCE))

        filters = cycleWarning(filters, AO3Warning.VIOLENCE)
        assertTrue(filters.warnings.isEmpty())
        assertEquals(setOf(AO3Warning.VIOLENCE), filters.excludedWarnings)
        assertEquals(FilterSelectionState.EXCLUDED, warningSelection(filters, AO3Warning.VIOLENCE))

        filters = cycleWarning(filters, AO3Warning.VIOLENCE)
        assertTrue(filters.warnings.isEmpty())
        assertTrue(filters.excludedWarnings.isEmpty())
        assertEquals(FilterSelectionState.CLEAR, warningSelection(filters, AO3Warning.VIOLENCE))
    }

    @Test
    fun cycleCategoryMovesThroughThreeStates() {
        var filters = AO3SearchFilters()
        filters = cycleCategory(filters, AO3Category.MM)
        assertEquals(setOf(AO3Category.MM), filters.categories)

        filters = cycleCategory(filters, AO3Category.MM)
        assertEquals(setOf(AO3Category.MM), filters.excludedCategories)
        assertTrue(filters.categories.isEmpty())

        filters = cycleCategory(filters, AO3Category.MM)
        assertTrue(filters.categories.isEmpty())
        assertTrue(filters.excludedCategories.isEmpty())
    }

    @Test
    fun withRatingSelectedAppliesAppleSideEffects() {
        val fromAny = withRatingSelected(AO3SearchFilters(), AO3Rating.MATURE)
        assertEquals(AO3Rating.MATURE, fromAny.rating)
        assertEquals(AO3RatingMatch.EXACT, fromAny.ratingMatch)
        assertFalse(fromAny.includeNotRated)

        val backToAny = withRatingSelected(fromAny, AO3Rating.ANY)
        assertEquals(AO3Rating.ANY, backToAny.rating)
        assertEquals(AO3RatingMatch.EXACT, backToAny.ratingMatch)

        val between = withRatingSelected(
            AO3SearchFilters(
                rating = AO3Rating.TEEN,
                ratingMatch = AO3RatingMatch.OR_HIGHER,
                includeNotRated = true
            ),
            AO3Rating.EXPLICIT
        )
        assertEquals(AO3Rating.EXPLICIT, between.rating)
        assertEquals(AO3RatingMatch.OR_HIGHER, between.ratingMatch)
        assertTrue(between.includeNotRated)
    }

    @Test
    fun clearedFiltersPreservesQueryOnly() {
        val filters = AO3SearchFilters(
            query = "found family",
            fandom = "Naruto",
            rating = AO3Rating.EXPLICIT,
            includeNotRated = false,
            warnings = setOf(AO3Warning.DEATH),
            categories = setOf(AO3Category.GEN),
            completion = AO3Completion.COMPLETE,
            wordsFrom = "1000",
            language = AO3Language.ENGLISH,
            sort = AO3SearchSort.KUDOS
        )

        val cleared = clearedFiltersPreservingQuery(filters)
        assertEquals("found family", cleared.query)
        assertFalse(cleared.hasActiveFilters)
        assertEquals(AO3SearchFilters(query = "found family"), cleared)
    }

    @Test
    fun activeFilterChipsSummarizesFacets() {
        assertTrue(activeFilterChips(AO3SearchFilters()).isEmpty())
        assertTrue(activeFilterChips(AO3SearchFilters(query = "only query")).isEmpty())

        val chips = activeFilterChips(
            AO3SearchFilters(
                fandom = "Naruto",
                excludedCharacters = "Sasuke",
                rating = AO3Rating.MATURE,
                ratingMatch = AO3RatingMatch.OR_HIGHER,
                includeNotRated = false,
                warnings = setOf(AO3Warning.NO_WARNINGS),
                excludedCategories = setOf(AO3Category.OTHER),
                crossover = AO3Crossover.EXCLUDE,
                completion = AO3Completion.COMPLETE,
                wordsFrom = "1000",
                wordsTo = "5000",
                updated = AO3Updated.WEEK,
                language = AO3Language.ENGLISH,
                sort = AO3SearchSort.KUDOS
            )
        )

        assertTrue(chips.contains("Fandom: Naruto"))
        assertTrue(chips.contains("−Character: Sasuke"))
        assertTrue(chips.contains("Mature+"))
        assertTrue(chips.contains("No Not Rated"))
        assertTrue(chips.contains(AO3Warning.NO_WARNINGS.title))
        assertTrue(chips.contains("−${AO3Category.OTHER.title}"))
        assertTrue(chips.contains("Crossover: Exclude"))
        assertTrue(chips.contains("Complete"))
        assertTrue(chips.contains("Words 1000–5000"))
        assertTrue(chips.contains(AO3Updated.WEEK.title))
        assertTrue(chips.contains(AO3Language.ENGLISH.title))
        assertTrue(chips.contains("Sort: Kudos"))
    }

    @Test
    fun defaultSavedSearchNamePrefersQueryThenFandom() {
        assertEquals(
            "slow burn",
            defaultSavedSearchName(AO3SearchFilters(query = "slow burn", fandom = "Naruto"))
        )
        assertEquals(
            "Naruto",
            defaultSavedSearchName(AO3SearchFilters(fandom = "Naruto, Boruto"))
        )
        assertEquals("Saved Search", defaultSavedSearchName(AO3SearchFilters()))
    }

    @Test
    fun savedSearchSubtitleJoinsSalientParts() {
        assertEquals(null, savedSearchSubtitle(AO3SearchFilters()))
        assertEquals(
            "“found family” · Naruto · Mature · Complete · Kudos",
            savedSearchSubtitle(
                AO3SearchFilters(
                    query = "found family",
                    fandom = "Naruto",
                    rating = AO3Rating.MATURE,
                    completion = AO3Completion.COMPLETE,
                    sort = AO3SearchSort.KUDOS
                )
            )
        )
    }
}
