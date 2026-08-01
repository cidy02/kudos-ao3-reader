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

/**
 * Three-state selection for warnings/categories, matching Apple's
 * `FilterSelectionState` (clear → include → exclude → clear).
 */
enum class FilterSelectionState {
    CLEAR,
    INCLUDED,
    EXCLUDED;

    val next: FilterSelectionState
        get() = when (this) {
            CLEAR -> INCLUDED
            INCLUDED -> EXCLUDED
            EXCLUDED -> CLEAR
        }
}

fun warningSelection(
    filters: AO3SearchFilters,
    warning: AO3Warning
): FilterSelectionState {
    return when {
        warning in filters.warnings -> FilterSelectionState.INCLUDED
        warning in filters.excludedWarnings -> FilterSelectionState.EXCLUDED
        else -> FilterSelectionState.CLEAR
    }
}

fun cycleWarning(filters: AO3SearchFilters, warning: AO3Warning): AO3SearchFilters {
    return when (warningSelection(filters, warning).next) {
        FilterSelectionState.INCLUDED -> filters.copy(
            warnings = filters.warnings + warning,
            excludedWarnings = filters.excludedWarnings - warning
        )
        FilterSelectionState.EXCLUDED -> filters.copy(
            warnings = filters.warnings - warning,
            excludedWarnings = filters.excludedWarnings + warning
        )
        FilterSelectionState.CLEAR -> filters.copy(
            warnings = filters.warnings - warning,
            excludedWarnings = filters.excludedWarnings - warning
        )
    }
}

fun categorySelection(
    filters: AO3SearchFilters,
    category: AO3Category
): FilterSelectionState {
    return when {
        category in filters.categories -> FilterSelectionState.INCLUDED
        category in filters.excludedCategories -> FilterSelectionState.EXCLUDED
        else -> FilterSelectionState.CLEAR
    }
}

fun cycleCategory(filters: AO3SearchFilters, category: AO3Category): AO3SearchFilters {
    return when (categorySelection(filters, category).next) {
        FilterSelectionState.INCLUDED -> filters.copy(
            categories = filters.categories + category,
            excludedCategories = filters.excludedCategories - category
        )
        FilterSelectionState.EXCLUDED -> filters.copy(
            categories = filters.categories - category,
            excludedCategories = filters.excludedCategories + category
        )
        FilterSelectionState.CLEAR -> filters.copy(
            categories = filters.categories - category,
            excludedCategories = filters.excludedCategories - category
        )
    }
}

/**
 * Apple-matching side effects when the rating picker changes: picking a specific
 * rating starts exact and excludes Not Rated; returning to Any resets match.
 */
fun withRatingSelected(filters: AO3SearchFilters, rating: AO3Rating): AO3SearchFilters {
    if (filters.rating == rating) return filters
    return when {
        filters.rating == AO3Rating.ANY && rating != AO3Rating.ANY -> filters.copy(
            rating = rating,
            ratingMatch = AO3RatingMatch.EXACT,
            includeNotRated = false
        )
        rating == AO3Rating.ANY -> filters.copy(
            rating = rating,
            ratingMatch = AO3RatingMatch.EXACT
        )
        else -> filters.copy(rating = rating)
    }
}

/**
 * Clears every filter facet while preserving the free-text query.
 * Sort returns to Best Match.
 */
fun clearedFiltersPreservingQuery(filters: AO3SearchFilters): AO3SearchFilters {
    return AO3SearchFilters(query = filters.query)
}

/**
 * Compact chip labels for the Search screen summary row. Order mirrors the
 * filter sheet sections. Empty when [AO3SearchFilters.hasActiveFilters] is false.
 */
fun activeFilterChips(filters: AO3SearchFilters): List<String> {
    if (!filters.hasActiveFilters) return emptyList()

    val chips = mutableListOf<String>()

    fun addTagField(label: String, included: String, excluded: String) {
        AO3SearchFilters.commaSeparatedValues(included).forEach { chips += "$label: $it" }
        AO3SearchFilters.commaSeparatedValues(excluded).forEach { chips += "−$label: $it" }
    }

    addTagField("Fandom", filters.fandom, filters.excludedFandoms)
    addTagField("Character", filters.characters, filters.excludedCharacters)
    addTagField("Relationship", filters.relationships, filters.excludedRelationships)
    addTagField("Tag", filters.additionalTags, filters.excludedAdditionalTags)

    if (filters.rating != AO3Rating.ANY) {
        val match = when (filters.ratingMatch) {
            AO3RatingMatch.EXACT -> filters.rating.title
            AO3RatingMatch.OR_HIGHER -> "${filters.rating.title}+"
            AO3RatingMatch.OR_LOWER -> "${filters.rating.title}−"
        }
        chips += match
    }
    if (!filters.includeNotRated) {
        chips += "No Not Rated"
    }

    AO3Warning.entries.filter { it in filters.warnings }.forEach {
        chips += it.title
    }
    AO3Warning.entries.filter { it in filters.excludedWarnings }.forEach {
        chips += "−${it.title}"
    }

    AO3Category.entries.filter { it in filters.categories }.forEach {
        chips += it.title
    }
    AO3Category.entries.filter { it in filters.excludedCategories }.forEach {
        chips += "−${it.title}"
    }

    if (filters.crossover != AO3Crossover.ANY) {
        chips += "Crossover: ${filters.crossover.title}"
    }
    if (filters.completion != AO3Completion.ANY) {
        chips += filters.completion.title
    }

    val from = filters.wordsFrom.trim()
    val to = filters.wordsTo.trim()
    when {
        from.isNotEmpty() && to.isNotEmpty() -> chips += "Words $from–$to"
        from.isNotEmpty() -> chips += "Words ≥ $from"
        to.isNotEmpty() -> chips += "Words ≤ $to"
    }

    if (filters.updated != AO3Updated.ANY) {
        chips += filters.updated.title
    }
    if (filters.language != AO3Language.ANY) {
        chips += filters.language.title
    }
    if (filters.sort != AO3SearchSort.RELEVANCE) {
        chips += "Sort: ${filters.sort.title}"
    }

    return chips
}
