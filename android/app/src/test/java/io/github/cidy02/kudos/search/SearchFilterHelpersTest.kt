package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.core.model.SavedWork
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
    fun activeFilterCountReportsWhatTheUserChanged() {
        // The badge means "you have narrowed this". `summaryLabels` always ends with
        // the sort so the results card is never empty — counting its rows here would
        // light the badge on a screen with no filters at all.
        assertEquals(0, activeFilterCount(AO3SearchFilters()))
        assertEquals(0, activeFilterCount(AO3SearchFilters(query = "only query")))

        val filters = AO3SearchFilters(
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
        // Every label counts here because the sort is non-default too.
        assertEquals(summaryLabels(filters).size, activeFilterCount(filters))

        // With a default sort the card still shows "Sort: Best Match", but the badge
        // must not count it.
        val defaultSort = filters.copy(sort = AO3SearchSort.RELEVANCE)
        assertEquals(summaryLabels(defaultSort).size - 1, activeFilterCount(defaultSort))
    }

    @Test
    fun summaryLabelsDescribeEveryActiveFacet() {
        val labels = summaryLabels(
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
        val texts = labels.map { it.text }
        // Tag chips carry their category as a glyph now, so the text is the tag
        // itself rather than a "Fandom: " prefix.
        assertTrue(texts.contains("Naruto"))
        assertTrue(texts.contains("−Sasuke"))
        assertTrue(texts.contains("Mature+"))
        assertTrue(texts.contains("No Not Rated"))
        assertTrue(texts.contains(AO3Warning.NO_WARNINGS.title))
        assertTrue(texts.contains("−${AO3Category.OTHER.title}"))
        assertTrue(texts.contains("Crossover: Exclude"))
        assertTrue(texts.contains("Complete"))
        assertTrue(texts.contains("Words 1000–5000"))
        assertTrue(texts.contains(AO3Updated.WEEK.title))
        assertTrue(texts.contains(AO3Language.ENGLISH.title))
        assertEquals("Sort: ${AO3SearchSort.KUDOS.title}", texts.last())

        assertEquals(SummaryLabel.fandomIcon, labels.first { it.text == "Naruto" }.icon)
        assertEquals(SummaryLabel.characterIcon, labels.first { it.text == "−Sasuke" }.icon)
        // Facets are not tag categories, so they get no glyph rather than a
        // misleading one.
        assertEquals(null, labels.last().icon)
    }

    @Test
    fun anUntouchedFilterSetStillNamesItsSort() {
        // The card must never be empty, and there is always an order in effect.
        assertEquals(listOf("Sort: Best Match"), summaryLabels(AO3SearchFilters()).map { it.text })
    }

    @Test
    fun theCardsOwnSubjectIsNotRepeatedAsAChip() {
        // On a fandom's page the heading already says it.
        val filters = AO3SearchFilters(fandom = "Naruto, Bleach")
        val texts = summaryLabels(filters, excluding = "Naruto").map { it.text }
        assertTrue(!texts.contains("Naruto"))
        assertTrue(texts.contains("Bleach"))
    }

    @Test
    fun collectLocalTagSuggestionsDedupesAndSortsByKind() {
        val works = listOf(
            SavedWork(
                title = "A",
                author = "X",
                workFandoms = listOf("Naruto", "naruto", " Bleach "),
                workCharacters = listOf("Sasuke", "Ichigo"),
                workRelationships = listOf("Sasuke/Naruto"),
                workFreeforms = listOf("Fluff"),
                workTags = listOf("Hurt/Comfort")
            ),
            SavedWork(
                title = "B",
                author = "Y",
                workFandoms = listOf("One Piece"),
                workCharacters = listOf("Luffy"),
                workFreeforms = listOf("Angst", "fluff")
            )
        )

        val suggestions = collectLocalTagSuggestions(
            works = works,
            userTagNames = listOf(" Comfort ", "comfort", "reread")
        )

        assertEquals(listOf("Bleach", "Naruto", "One Piece"), suggestions.fandoms)
        assertEquals(listOf("Ichigo", "Luffy", "Sasuke"), suggestions.characters)
        assertEquals(listOf("Sasuke/Naruto"), suggestions.relationships)
        assertEquals(
            listOf("Angst", "Comfort", "Fluff", "Hurt/Comfort", "reread"),
            suggestions.freeforms
        )
        assertEquals(suggestions.freeforms, suggestions.forKind(LocalTagKind.FREEFORM))
    }


    @Test
    fun currentTokenAndCommittedTagsSplitOnComma() {
        assertEquals(emptyList<String>(), committedTagValues(""))
        assertEquals(emptyList<String>(), committedTagValues("Nar"))
        assertEquals(listOf("Naruto"), committedTagValues("Naruto,"))
        assertEquals(listOf("Naruto"), committedTagValues("Naruto, Sa"))
        assertEquals(listOf("Naruto", "Sasuke"), committedTagValues("Naruto, Sasuke, "))

        assertEquals("", currentTagToken(""))
        assertEquals("Nar", currentTagToken("Nar"))
        assertEquals("", currentTagToken("Naruto,"))
        assertEquals("Sa", currentTagToken("Naruto, Sa"))
        assertEquals("", currentTagToken("Naruto, Sasuke, "))
    }


    @Test
    fun filterLocalTagSuggestionsPrefersPrefixAndExcludesCommitted() {
        val candidates = listOf(
            "Naruto",
            "Naruto Shippuuden",
            "Bleach",
            "One Piece",
            "Harry Potter"
        )

        assertEquals(
            listOf("Naruto", "Naruto Shippuuden"),
            filterLocalTagSuggestions(candidates, "Nar", limit = 8)
        )
        assertEquals(
            listOf("Bleach"),
            filterLocalTagSuggestions(candidates, "Naruto, Bl", limit = 8)
        )
        // Empty token: candidates in source order, excluding committed, capped by limit.
        assertEquals(
            listOf("Naruto Shippuuden", "Bleach", "One Piece", "Harry Potter"),
            filterLocalTagSuggestions(candidates, "Naruto, ", limit = 8)
        )
        assertEquals(
            listOf("Naruto", "Naruto Shippuuden", "Bleach"),
            filterLocalTagSuggestions(candidates, "", limit = 3)
        )
        // Substring match when no prefix hits.
        assertEquals(
            listOf("Harry Potter"),
            filterLocalTagSuggestions(candidates, "Pot", limit = 8)
        )
    }


    @Test
    fun applyTagSuggestionReplacesTokenAndAppendsSeparator() {
        assertEquals("Naruto, ", applyTagSuggestion("", "Naruto"))
        assertEquals("Naruto, ", applyTagSuggestion("Nar", "Naruto"))
        assertEquals("Naruto, Sasuke, ", applyTagSuggestion("Naruto, Sa", "Sasuke"))
        assertEquals("Naruto, Sasuke, ", applyTagSuggestion("Naruto, ", "Sasuke"))
        // Selecting an already-committed tag does not duplicate it.
        assertEquals("Naruto, ", applyTagSuggestion("Naruto, Nar", "Naruto"))
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
