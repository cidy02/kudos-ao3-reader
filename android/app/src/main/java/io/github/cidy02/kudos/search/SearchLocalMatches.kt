package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.works.WorkSearchIndex

/**
 * On-device matches for the query being typed. Caps match iOS
 * `SearchView.computeLocalMatches` and `FandomCatalog.cachedFandoms` (limit 12).
 */
data class SearchLocalMatches(
    val works: List<SavedWork> = emptyList(),
    val libraryFandoms: List<String> = emptyList(),
    val ao3Fandoms: List<AO3Fandom> = emptyList(),
    val tags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList()
) {
    val isEmpty: Boolean
        get() = works.isEmpty() && libraryFandoms.isEmpty() && ao3Fandoms.isEmpty() &&
            tags.isEmpty() && collections.isEmpty()
}

fun computeSearchLocalMatches(
    query: String,
    works: List<SavedWork>,
    tags: List<Tag>,
    collections: List<WorkCollection>,
    catalogFandoms: List<AO3Fandom>
): SearchLocalMatches {
    val trimmed = query.trim()
    if (trimmed.isEmpty()) return SearchLocalMatches()
    val terms = WorkSearchIndex.terms(trimmed)
    val normalizedQuery = WorkSearchIndex.normalize(trimmed)

    val matchedWorks = works.filter { WorkSearchIndex.matches(it, terms) }.take(20)

    val seenFandoms = LinkedHashSet<String>()
    val libraryFandoms = mutableListOf<String>()
    for (work in works) {
        for (fandom in work.workFandoms) {
            val key = WorkSearchIndex.normalize(fandom)
            if (key.isEmpty() || normalizedQuery !in key || !seenFandoms.add(key)) continue
            libraryFandoms += fandom
            if (libraryFandoms.size >= 12) break
        }
        if (libraryFandoms.size >= 12) break
    }

    val ao3Fandoms = rankedCachedFandoms(catalogFandoms, normalizedQuery, limit = 12)
        .filter { WorkSearchIndex.normalize(it.name) !in seenFandoms }

    val matchedTags = tags
        .filter { WorkSearchIndex.normalize(it.name).contains(normalizedQuery) }
        .take(12)
    val matchedCollections = collections
        .filter { WorkSearchIndex.normalize(it.name).contains(normalizedQuery) }
        .take(12)

    return SearchLocalMatches(
        works = matchedWorks,
        libraryFandoms = libraryFandoms,
        ao3Fandoms = ao3Fandoms,
        tags = matchedTags,
        collections = matchedCollections
    )
}

/**
 * Cached AO3 fandoms whose name contains [normalizedQuery]. Prefix matches
 * outrank substrings. Within a bucket, the higher work count wins, then the
 * name. A fandom listed under several categories keeps the copy with the
 * highest count. Port of `FandomCatalog.rankedMatches`.
 */
fun rankedCachedFandoms(
    fandoms: List<AO3Fandom>,
    normalizedQuery: String,
    limit: Int = 12
): List<AO3Fandom> {
    if (normalizedQuery.isEmpty() || limit <= 0) return emptyList()
    val bestByName = LinkedHashMap<String, AO3Fandom>()
    for (fandom in fandoms) {
        val key = WorkSearchIndex.normalize(fandom.name)
        if (key.isEmpty()) continue
        val existing = bestByName[key]
        if (existing != null && (existing.workCount ?: 0) >= (fandom.workCount ?: 0)) continue
        bestByName[key] = fandom
    }
    val ranked = bestByName.entries.sortedWith(
        compareByDescending<Map.Entry<String, AO3Fandom>> { it.value.workCount ?: 0 }
            .thenBy { it.key }
    )
    val prefix = mutableListOf<AO3Fandom>()
    val contains = mutableListOf<AO3Fandom>()
    for ((key, fandom) in ranked) {
        if (key.startsWith(normalizedQuery)) {
            prefix += fandom
            if (prefix.size >= limit) break
        } else if (contains.size < limit && normalizedQuery in key) {
            contains += fandom
        }
    }
    return (prefix + contains).take(limit)
}

/** What a search is of. One tag field holding one name wins over the query. */
data class SearchSubject(
    val text: String,
    val field: SearchSubjectField?
)

enum class SearchSubjectField { FANDOM, CHARACTER, RELATIONSHIP, FREEFORM }

const val SEARCH_RESULTS_FALLBACK = "Search Results"

fun AO3SearchFilters.searchSubject(): SearchSubject {
    val fields = listOf(
        fandom to SearchSubjectField.FANDOM,
        characters to SearchSubjectField.CHARACTER,
        relationships to SearchSubjectField.RELATIONSHIP,
        additionalTags to SearchSubjectField.FREEFORM
    )
    val filled = fields.filter { it.first.isNotBlank() }
    if (filled.size == 1) {
        val names = AO3SearchFilters.commaSeparatedValues(filled.first().first)
        if (names.size == 1) return SearchSubject(names.first(), filled.first().second)
    }
    val text = query.trim()
    return SearchSubject(text.ifEmpty { SEARCH_RESULTS_FALLBACK }, null)
}

/** Puts [name] in the included-fandom field and drops it from the excluded list. */
fun withIncludedFandom(filters: AO3SearchFilters, name: String): AO3SearchFilters {
    val excluded = AO3SearchFilters.commaSeparatedValues(filters.excludedFandoms)
        .filter { !it.equals(name, ignoreCase = true) }
        .joinToString(", ")
    return filters.copy(fandom = name, excludedFandoms = excluded)
}

/**
 * Page Try Again reloads. With results on screen, retry the page that failed.
 * With nothing on screen, null means run the search again from the top.
 */
fun searchRetryPage(requested: Int?, current: Int, hasResults: Boolean): Int? {
    if (!hasResults) return null
    return requested ?: current
}
