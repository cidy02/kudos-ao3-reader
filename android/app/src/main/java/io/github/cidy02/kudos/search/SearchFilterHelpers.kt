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
import androidx.compose.ui.graphics.vector.ImageVector

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
/**
 * How many settings the filter button's badge should report.
 *
 * Not `summaryLabels().size`: that list always ends with the sort so the results
 * card is never empty, whereas the badge must mean "you have narrowed this" — and a
 * default sort has narrowed nothing. Counting the card's rows here would light the
 * badge on a screen with no filters at all.
 */
fun activeFilterCount(filters: AO3SearchFilters): Int {
    if (!filters.hasActiveFilters) return 0
    val labels = summaryLabels(filters)
    return if (filters.sort == AO3SearchSort.RELEVANCE) labels.size - 1 else labels.size
}

/**
 * The results card's chips: everything currently narrowing or ordering the list.
 *
 * Only *non-default* settings appear. "Any rating" and "All" are the absence of a
 * filter, and listing them would spend the card's height saying nothing, loudest in
 * the commonest state. Sort is the exception and is always shown: unlike every other
 * entry there is always an order in effect, so it is never noise.
 *
 * [excluding] names the one thing this would otherwise repeat: on a fandom's page the
 * card's own heading is already the fandom.
 */
fun summaryLabels(filters: AO3SearchFilters, excluding: String? = null): List<SummaryLabel> {
    val chips = mutableListOf<SummaryLabel>()
    fun add(text: String, icon: ImageVector? = null) {
        chips += SummaryLabel(text, icon)
    }

    fun addTagField(icon: ImageVector, included: String, excluded: String) {
        AO3SearchFilters.commaSeparatedValues(included)
            .filter { it != excluding }
            .forEach { add(it, icon) }
        AO3SearchFilters.commaSeparatedValues(excluded).forEach { add("−$it", icon) }
    }

    addTagField(SummaryLabel.fandomIcon, filters.fandom, filters.excludedFandoms)
    addTagField(SummaryLabel.characterIcon, filters.characters, filters.excludedCharacters)
    addTagField(SummaryLabel.relationshipIcon, filters.relationships, filters.excludedRelationships)
    addTagField(SummaryLabel.freeformIcon, filters.additionalTags, filters.excludedAdditionalTags)

    if (filters.rating != AO3Rating.ANY) {
        val match = when (filters.ratingMatch) {
            AO3RatingMatch.EXACT -> filters.rating.title
            AO3RatingMatch.OR_HIGHER -> "${filters.rating.title}+"
            AO3RatingMatch.OR_LOWER -> "${filters.rating.title}−"
        }
        add(match)
    }
    if (!filters.includeNotRated) {
        add("No Not Rated")
    }

    AO3Warning.entries.filter { it in filters.warnings }.forEach {
        add(it.title, SummaryLabel.warningIcon)
    }
    AO3Warning.entries.filter { it in filters.excludedWarnings }.forEach {
        add("−${it.title}", SummaryLabel.warningIcon)
    }

    // AO3 categories (Gen, M/M …) are a facet, not a tag category, so no glyph.
    AO3Category.entries.filter { it in filters.categories }.forEach { add(it.title) }
    AO3Category.entries.filter { it in filters.excludedCategories }.forEach { add("−${it.title}") }

    if (filters.crossover != AO3Crossover.ANY) {
        add("Crossover: ${filters.crossover.title}")
    }
    if (filters.completion != AO3Completion.ANY) {
        add(filters.completion.title)
    }

    val from = filters.wordsFrom.trim()
    val to = filters.wordsTo.trim()
    when {
        from.isNotEmpty() && to.isNotEmpty() -> add("Words $from–$to")
        from.isNotEmpty() -> add("Words ≥ $from")
        to.isNotEmpty() -> add("Words ≤ $to")
    }

    if (filters.updated != AO3Updated.ANY) {
        add(filters.updated.title)
    }
    if (filters.language != AO3Language.ANY) {
        add(filters.language.title)
    }
    // Sort last, and unconditionally: unlike every entry above there is always an
    // order in effect, so this is the one label that is never noise — and it is the
    // setting users most often forget they changed.
    add("Sort: ${filters.sort.title}")

    return chips
}

/**
 * Local (library-only) tag pools for search-filter autocomplete.
 * Built from [SavedWork] categorized tag fields + optional user tags.
 */
data class LocalTagSuggestions(
    val fandoms: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val relationships: List<String> = emptyList(),
    val freeforms: List<String> = emptyList()
) {
    fun forKind(kind: LocalTagKind): List<String> = when (kind) {
        LocalTagKind.FANDOM -> fandoms
        LocalTagKind.CHARACTER -> characters
        LocalTagKind.RELATIONSHIP -> relationships
        LocalTagKind.FREEFORM -> freeforms
    }
}

enum class LocalTagKind {
    FANDOM,
    CHARACTER,
    RELATIONSHIP,
    FREEFORM
}

/**
 * Collect unique, case-insensitively de-duplicated tag names from saved works.
 * [userTagNames] are folded into freeforms (additional tags) only.
 */
fun collectLocalTagSuggestions(
    works: List<SavedWork>,
    userTagNames: List<String> = emptyList()
): LocalTagSuggestions {
    val fandoms = linkedMapOf<String, String>()
    val characters = linkedMapOf<String, String>()
    val relationships = linkedMapOf<String, String>()
    val freeforms = linkedMapOf<String, String>()

    fun put(target: MutableMap<String, String>, raw: String) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return
        val key = trimmed.lowercase()
        if (key !in target) target[key] = trimmed
    }

    works.forEach { work ->
        work.workFandoms.forEach { put(fandoms, it) }
        work.workCharacters.forEach { put(characters, it) }
        work.workRelationships.forEach { put(relationships, it) }
        work.workFreeforms.forEach { put(freeforms, it) }
        // Uncategorized blurb tags feed the freeform/additional-tags field.
        work.workTags.forEach { put(freeforms, it) }
    }
    userTagNames.forEach { put(freeforms, it) }

    fun sorted(values: Map<String, String>): List<String> =
        values.values.sortedWith(String.CASE_INSENSITIVE_ORDER)

    return LocalTagSuggestions(
        fandoms = sorted(fandoms),
        characters = sorted(characters),
        relationships = sorted(relationships),
        freeforms = sorted(freeforms)
    )
}

/**
 * Tags already committed in a comma-separated field (everything except the
 * in-progress trailing token when the value does not end with a comma).
 */
fun committedTagValues(fieldValue: String): List<String> {
    val parts = AO3SearchFilters.commaSeparatedValues(fieldValue)
    if (parts.isEmpty()) return emptyList()
    val endsWithSeparator = fieldValue.trimEnd().endsWith(',')
    return if (endsWithSeparator) parts else parts.dropLast(1)
}

/**
 * Partial token the user is currently typing (after the last comma, or the
 * whole field when there is no comma yet). Empty when the field ends with `,`.
 */
fun currentTagToken(fieldValue: String): String {
    if (fieldValue.isBlank()) return ""
    if (fieldValue.trimEnd().endsWith(',')) return ""
    return AO3SearchFilters.commaSeparatedValues(fieldValue).lastOrNull().orEmpty()
}

/**
 * Filter local candidates by the current token; exclude already-committed tags.
 * Prefers prefix matches, then substring matches; case-insensitive.
 */
fun filterLocalTagSuggestions(
    candidates: List<String>,
    fieldValue: String,
    limit: Int = 8
): List<String> {
    if (limit <= 0 || candidates.isEmpty()) return emptyList()

    val committed = committedTagValues(fieldValue)
        .map { it.lowercase() }
        .toSet()
    val token = currentTagToken(fieldValue).trim()
    val needle = token.lowercase()

    val prefix = mutableListOf<String>()
    val contains = mutableListOf<String>()

    for (candidate in candidates) {
        val trimmed = candidate.trim()
        if (trimmed.isEmpty()) continue
        val lower = trimmed.lowercase()
        if (lower in committed) continue
        if (needle.isEmpty()) {
            prefix += trimmed
        } else if (lower.startsWith(needle)) {
            prefix += trimmed
        } else if (lower.contains(needle)) {
            contains += trimmed
        }
        if (prefix.size >= limit) break
    }

    if (prefix.size >= limit) return prefix.take(limit)
    val remaining = limit - prefix.size
    return prefix + contains.take(remaining)
}

/**
 * Replace the in-progress token with [suggestion] and leave a trailing
 * `", "` so the user can keep adding tags.
 */
fun applyTagSuggestion(fieldValue: String, suggestion: String): String {
    val tag = suggestion.trim()
    if (tag.isEmpty()) return fieldValue

    val committed = committedTagValues(fieldValue)
    val already = committed.any { it.equals(tag, ignoreCase = true) }
    val next = if (already) committed else committed + tag
    return if (next.isEmpty()) {
        "$tag, "
    } else {
        next.joinToString(separator = ", ", postfix = ", ")
    }
}

fun defaultSavedSearchName(filters: AO3SearchFilters): String {
    val query = filters.query.trim()
    if (query.isNotEmpty()) return query
    val fandom = filters.fandom.trim()
    if (fandom.isNotEmpty()) {
        return AO3SearchFilters.commaSeparatedValues(fandom).firstOrNull() ?: fandom
    }
    return "Saved Search"
}

fun savedSearchSubtitle(filters: AO3SearchFilters): String? {
    val parts = mutableListOf<String>()
    val query = filters.query.trim()
    if (query.isNotEmpty()) parts += "“$query”"
    val fandom = filters.fandom.trim()
    if (fandom.isNotEmpty()) {
        parts += AO3SearchFilters.commaSeparatedValues(fandom).firstOrNull() ?: fandom
    }
    if (filters.rating != AO3Rating.ANY) parts += filters.rating.title
    if (filters.completion != AO3Completion.ANY) parts += filters.completion.title
    if (filters.sort != AO3SearchSort.RELEVANCE) parts += filters.sort.title
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}
