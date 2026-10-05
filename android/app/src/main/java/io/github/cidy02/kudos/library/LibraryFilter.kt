package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.network.ao3.search.AO3Rating

enum class LibraryFinishedFilter { Any, Finished, Unfinished }

enum class LibraryDownloadFilter { Any, Downloaded, NotDownloaded }

enum class LibraryCompletionFilter { Any, Complete, InProgress }

data class LibraryFilterState(
    val favoriteOnly: Boolean = false,
    val finished: LibraryFinishedFilter = LibraryFinishedFilter.Any,
    val download: LibraryDownloadFilter = LibraryDownloadFilter.Any,
    val completion: LibraryCompletionFilter = LibraryCompletionFilter.Any,
    val userTagIds: Set<String> = emptySet(),
    val collectionIds: Set<String> = emptySet(),
    val ratings: Set<String> = emptySet(),
    val warnings: Set<String> = emptySet(),
    val categories: Set<String> = emptySet(),
    val fandoms: Set<String> = emptySet(),
    val relationships: Set<String> = emptySet(),
    val characters: Set<String> = emptySet(),
    val freeforms: Set<String> = emptySet(),
    val rating: AO3Rating = AO3Rating.ANY,
    val language: String = "",
    val wordsFrom: String = "",
    val wordsTo: String = "",
    val excludeTags: Set<String> = emptySet()
) {
    val activeCount: Int
        get() = listOf(
            favoriteOnly,
            finished != LibraryFinishedFilter.Any,
            download != LibraryDownloadFilter.Any,
            completion != LibraryCompletionFilter.Any,
            rating != AO3Rating.ANY,
            language.isNotEmpty(),
            wordsFrom.isNotBlank() || wordsTo.isNotBlank()
        ).count { it } + userTagIds.size + collectionIds.size + ratings.size + warnings.size +
            categories.size + fandoms.size + relationships.size + characters.size + freeforms.size + excludeTags.size

    val hasActiveFilters: Boolean
        get() = activeCount > 0
}

/** iOS LibraryFilters.FilterDrop; sort deliberately lives outside the predicates. */
data class LibraryFilterDrop(
    val id: String,
    val filterLabel: String,
    val remainingCount: Int,
    val remainingFilters: LibraryFilterState
)

private data class LibraryFilterMember(
    val id: String,
    val label: String,
    val facet: String,
    val clear: (LibraryFilterState) -> LibraryFilterState
)

/** Same member order and same one-predicate removal as LibraryFilters.swift:217–259. */
private fun LibraryFilterState.activeMembers(
    userTagNames: Map<String, String>,
    collectionNames: Map<String, String>
): List<LibraryFilterMember> {
    val members = mutableListOf<LibraryFilterMember>()
    fun add(facet: String, key: String, label: String, clear: (LibraryFilterState) -> LibraryFilterState) {
        members += LibraryFilterMember("$facet:$key", label, facet, clear)
    }
    for (id in userTagIds.sortedBy { userTagNames[it] ?: it }) {
        add("your tag", id, userTagNames[id] ?: id) { it.copy(userTagIds = it.userTagIds - id) }
    }
    for (name in fandoms.sorted()) add("fandom", name, name) { it.copy(fandoms = it.fandoms - name) }
    for (name in characters.sorted()) add("character", name, name) { it.copy(characters = it.characters - name) }
    for (name in relationships.sorted()) add("relationship", name, name) { it.copy(relationships = it.relationships - name) }
    for (name in freeforms.sorted()) add("tag", name, name) { it.copy(freeforms = it.freeforms - name) }
    for (name in excludeTags.sorted()) add("excluded tag", name, "−$name") { it.copy(excludeTags = it.excludeTags - name) }
    if (rating != AO3Rating.ANY) add("rating", rating.appleCaseName, rating.title) { it.copy(rating = AO3Rating.ANY) }
    val warningOrder = io.github.cidy02.kudos.network.ao3.search.AO3Warning.entries.map { it.title }
    for (name in warnings.sortedWith(compareBy<String> { warningOrder.indexOf(it) }.thenBy { it })) {
        add("warning", name, name) { it.copy(warnings = it.warnings - name) }
    }
    val categoryOrder = io.github.cidy02.kudos.network.ao3.search.AO3Category.entries.map { it.title }
    for (name in categories.sortedWith(compareBy<String> { categoryOrder.indexOf(it) }.thenBy { it })) {
        add("category", name, name) { it.copy(categories = it.categories - name) }
    }
    if (completion != LibraryCompletionFilter.Any) {
        val label = if (completion == LibraryCompletionFilter.Complete) "Complete" else "In Progress"
        add("status", completion.name, label) { it.copy(completion = LibraryCompletionFilter.Any) }
    }
    if (language.isNotEmpty()) add("language", language, language) { it.copy(language = "") }
    val lower = wordsFrom.trim()
    val upper = wordsTo.trim()
    val wordLabel = when {
        lower.isNotEmpty() && upper.isNotEmpty() -> "Words $lower–$upper"
        lower.isNotEmpty() -> minimumLibraryWordsLabel(lower)
        upper.isNotEmpty() -> "Words ≤ $upper"
        else -> null
    }
    if (wordLabel != null) add("words", wordLabel, wordLabel) { it.copy(wordsFrom = "", wordsTo = "") }
    // Android's retained pre-3af predicates still need truthful drops if present.
    if (favoriteOnly) add("favorite", "only", "Favorites") { it.copy(favoriteOnly = false) }
    if (finished != LibraryFinishedFilter.Any) add("reading state", finished.name, finished.name) {
        it.copy(finished = LibraryFinishedFilter.Any)
    }
    if (download != LibraryDownloadFilter.Any) {
        val label = if (download == LibraryDownloadFilter.Downloaded) "Downloaded" else "Not Downloaded"
        add("download", download.name, label) { it.copy(download = LibraryDownloadFilter.Any) }
    }
    for (id in collectionIds.sortedBy { collectionNames[it] ?: it }) {
        add("collection", id, collectionNames[id] ?: id) { it.copy(collectionIds = it.collectionIds - id) }
    }
    for (name in ratings.sorted()) add("rating", name, name) { it.copy(ratings = it.ratings - name) }
    val repeated = members.groupingBy { it.label }.eachCount().filterValues { it > 1 }.keys
    return members.map { if (it.label in repeated) it.copy(label = "${it.label} (${it.facet})") else it }
}

private fun minimumLibraryWordsLabel(bound: String): String {
    val value = bound.toLongOrNull() ?: return "Words ≥ $bound"
    val formatter = android.icu.text.CompactDecimalFormat.getInstance(
        java.util.Locale.getDefault(), android.icu.text.CompactDecimalFormat.CompactStyle.SHORT
    )
    return "${formatter.format(value)}+ words"
}

fun LibraryFilterState.droppingEachActiveFilter(
    works: List<LibraryDisplayItem>,
    userTagNames: Map<String, String> = emptyMap(),
    collectionNames: Map<String, String> = emptyMap()
): List<LibraryFilterDrop> = activeMembers(userTagNames, collectionNames).map { member ->
    val remaining = member.clear(this)
    LibraryFilterDrop(member.id, member.label, LibraryQuery.filterOnly(works, filters = remaining).size, remaining)
}

/** iOS LibraryFilters.collidingFilterLabels: singleton, first disjoint pair, then all. */
fun LibraryFilterState.collidingFilterLabels(
    works: List<LibraryDisplayItem>,
    userTagNames: Map<String, String> = emptyMap(),
    collectionNames: Map<String, String> = emptyMap()
): List<String> {
    val members = activeMembers(userTagNames, collectionNames)
    val alone = members.indices.map { index ->
        members.indices.filter { it != index }.fold(this) { only, other -> members[other].clear(only) }
    }
    val matchingIds = alone.map { only ->
        LibraryQuery.filterOnly(works, filters = only).mapTo(mutableSetOf()) { it.item.work.id }
    }
    for (index in members.indices) if (matchingIds[index].isEmpty()) return listOf(members[index].label)
    for (first in members.indices) {
        for (second in first + 1 until members.size) {
            if (matchingIds[first].none { it in matchingIds[second] }) {
                return listOf(members[first].label, members[second].label)
            }
        }
    }
    return members.map { it.label }
}

fun libraryCollisionTitle(activeCount: Int): String = when (activeCount) {
    0 -> "Nothing matches."
    1 -> "Nothing matches this filter."
    2 -> "Nothing matches both filters."
    3 -> "Nothing matches all three filters."
    4 -> "Nothing matches all four filters."
    5 -> "Nothing matches all five filters."
    else -> "Nothing matches all $activeCount filters."
}

fun libraryCollisionDetail(sectionTitle: String, hiddenCount: Int, activeCount: Int, colliding: List<String>): String {
    val hidden = if (hiddenCount == 1) "Your 1 work in $sectionTitle is hidden by this filter."
        else "All $hiddenCount of your works in $sectionTitle are hidden by these filters."
    if (activeCount < 2) return hidden
    if (colliding.size == 1) return "$hidden ${colliding[0]} matches no works here."
    val joined = when (colliding.size) {
        0 -> ""
        1 -> colliding[0]
        2 -> "${colliding[0]} and ${colliding[1]}"
        else -> colliding.dropLast(1).joinToString(", ") + ", and " + colliding.last()
    }
    return "$hidden $joined have no works in common here."
}
