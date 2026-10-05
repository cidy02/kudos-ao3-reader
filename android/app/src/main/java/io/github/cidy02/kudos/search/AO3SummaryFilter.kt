package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/** Shared with LibraryFilters: exact facet text, lenient rating text, and typed bounds. */
internal fun matchesFacetText(values: List<String>, value: String): Boolean =
    values.any { it.equals(value, ignoreCase = true) }

internal fun AO3Warning.matchesWarningText(values: List<String>): Boolean =
    matchesFacetText(values, title) || (this == AO3Warning.UNDERAGE && matchesFacetText(values, "Underage"))

internal fun AO3Rating.matchesRatingText(text: String): Boolean = when (this) {
    AO3Rating.ANY -> true
    AO3Rating.GENERAL -> text.contains("general", ignoreCase = true)
    AO3Rating.TEEN -> text.contains("teen", ignoreCase = true)
    AO3Rating.MATURE -> text.contains("mature", ignoreCase = true)
    AO3Rating.EXPLICIT -> text.contains("explicit", ignoreCase = true)
    AO3Rating.NOT_RATED -> text.contains("not rated", ignoreCase = true)
}

internal fun filterWordBound(text: String): Long? = text.filter(Char::isDigit).toLongOrNull()

/** iOS AO3SummaryFilter: refine the loaded page without searching or changing AO3's order. */
internal fun AO3SearchFilters.matchesSummary(work: AO3WorkSummary): Boolean {
    fun contains(value: String, tags: List<String>) = tags.any { it.contains(value, ignoreCase = true) }
    fun includes(field: String, tags: List<String>) =
        AO3SearchFilters.commaSeparatedValues(field).all { contains(it, tags) }

    if (!includes(fandom, work.fandoms) || !includes(characters, work.characters) ||
        !includes(relationships, work.relationships) || !includes(additionalTags, work.freeforms)) return false
    val everyTag = work.fandoms + work.characters + work.relationships + work.freeforms + work.warnings
    val excluded = listOf(excludedFandoms, excludedCharacters, excludedRelationships, excludedAdditionalTags)
        .flatMap { AO3SearchFilters.commaSeparatedValues(it) }
    if (excluded.any { contains(it, everyTag) }) return false

    if (AO3Rating.NOT_RATED.matchesRatingText(work.rating)) {
        if (!includeNotRated) return false
    } else if (rating != AO3Rating.ANY) {
        val ladder = listOf(AO3Rating.GENERAL, AO3Rating.TEEN, AO3Rating.MATURE, AO3Rating.EXPLICIT)
        val wanted = ladder.indexOf(rating)
        val found = ladder.indexOfFirst { it.matchesRatingText(work.rating) }
        if (wanted < 0 || found < 0) return false
        val matches = when (ratingMatch) {
            AO3RatingMatch.EXACT -> found == wanted
            AO3RatingMatch.OR_HIGHER -> found >= wanted
            AO3RatingMatch.OR_LOWER -> found <= wanted
        }
        if (!matches) return false
    }

    fun hasWarning(warning: AO3Warning) = warning.matchesWarningText(work.warnings)
    if (!warnings.all(::hasWarning) || excludedWarnings.any(::hasWarning)) return false
    fun hasCategory(title: String) = matchesFacetText(work.categories, title)
    if (!categories.all { hasCategory(it.title) } || excludedCategories.any { hasCategory(it.title) }) return false
    // The subscriptions metadata type carries posted/total, without an isComplete field.
    val complete = work.isComplete ?: work.chapters.split('/').takeIf { it.size == 2 }?.let { parts ->
        val posted = parts[0].trim().toIntOrNull()
        val total = parts[1].trim().toIntOrNull()
        if (posted == null) null else total != null && posted == total
    }
    when (completion) {
        AO3Completion.ANY -> Unit
        AO3Completion.COMPLETE -> if (complete != true) return false
        AO3Completion.IN_PROGRESS -> if (complete != false) return false
    }
    // iOS chapterCountMatches: 1/? is a WIP, not a finished one-shot.
    // Unreadable text (anything without exactly two slash-separated parts) stays visible.
    if (chapterCount == AO3ChapterCount.SINGLE_CHAPTER) {
        val parts = work.chapters.split('/')
        if (parts.size == 2 && (parts[0].trim() != "1" || parts[1].trim() != "1")) return false
    }
    if (language != AO3Language.ANY && !matchesFacetText(listOf(work.language), language.title)) return false
    work.wordCount?.let { words ->
        val from = filterWordBound(wordsFrom)
        val to = filterWordBound(wordsTo)
        if (from != null && words < from) return false
        if (to != null && words > to) return false
    }
    return true
}

/** iOS AO3SubscriptionsRefine: unknown index rows stay visible until metadata can judge them. */
internal fun AO3WorkSummary.isSubscriptionIndexOnly(): Boolean = rating.isBlank() && fandoms.isEmpty()

internal fun AO3WorkSummary.hasPostedChapterCount(): Boolean =
    chapters.substringBefore('/').trim().toIntOrNull() != null

internal fun AO3SearchFilters.includesAccountWork(work: AO3WorkSummary, subscriptions: Boolean): Boolean =
    (subscriptions && work.isSubscriptionIndexOnly()) || matchesSummary(work)

internal fun refineMatchText(total: Int, matching: Int, pending: Int): String {
    val works = if (total == 1) "work" else "works"
    val verb = if (matching == 1) "matches" else "match"
    val line = "$matching of the $total $works on this page $verb"
    return if (pending > 0) "$line · $pending not checked yet" else line
}
