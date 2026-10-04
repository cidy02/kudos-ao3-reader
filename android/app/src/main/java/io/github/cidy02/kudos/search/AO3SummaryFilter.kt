package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

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

    if (work.rating.contains("not rated", ignoreCase = true)) {
        if (!includeNotRated) return false
    } else if (rating != AO3Rating.ANY) {
        val ladder = listOf(AO3Rating.GENERAL, AO3Rating.TEEN, AO3Rating.MATURE, AO3Rating.EXPLICIT)
        val wanted = ladder.indexOf(rating)
        val found = listOf("general", "teen", "mature", "explicit")
            .indexOfFirst { work.rating.contains(it, ignoreCase = true) }
        if (wanted < 0 || found < 0) return false
        val matches = when (ratingMatch) {
            AO3RatingMatch.EXACT -> found == wanted
            AO3RatingMatch.OR_HIGHER -> found >= wanted
            AO3RatingMatch.OR_LOWER -> found <= wanted
        }
        if (!matches) return false
    }

    fun hasWarning(warning: AO3Warning): Boolean {
        val names = if (warning == AO3Warning.UNDERAGE) listOf(warning.title, "Underage") else listOf(warning.title)
        return names.any { name -> work.warnings.any { it.equals(name, ignoreCase = true) } }
    }
    if (!warnings.all(::hasWarning) || excludedWarnings.any(::hasWarning)) return false
    fun hasCategory(title: String) = work.categories.any { it.equals(title, ignoreCase = true) }
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
    if (language != AO3Language.ANY && !work.language.equals(language.title, ignoreCase = true)) return false
    work.wordCount?.let { words ->
        val from = wordsFrom.filter(Char::isDigit).toIntOrNull()
        val to = wordsTo.filter(Char::isDigit).toIntOrNull()
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
