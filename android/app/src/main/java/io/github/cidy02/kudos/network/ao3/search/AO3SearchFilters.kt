package io.github.cidy02.kudos.network.ao3.search

data class AO3SearchFilters(
    val query: String = "",
    val fandom: String = "",
    val characters: String = "",
    val relationships: String = "",
    val additionalTags: String = "",
    val excludedFandoms: String = "",
    val excludedCharacters: String = "",
    val excludedRelationships: String = "",
    val excludedAdditionalTags: String = "",
    val rating: AO3Rating = AO3Rating.ANY,
    val ratingMatch: AO3RatingMatch = AO3RatingMatch.EXACT,
    val includeNotRated: Boolean = true,
    val warnings: Set<AO3Warning> = emptySet(),
    val excludedWarnings: Set<AO3Warning> = emptySet(),
    val categories: Set<AO3Category> = emptySet(),
    val excludedCategories: Set<AO3Category> = emptySet(),
    val crossover: AO3Crossover = AO3Crossover.ANY,
    val completion: AO3Completion = AO3Completion.ANY,
    val wordsFrom: String = "",
    val wordsTo: String = "",
    val updated: AO3Updated = AO3Updated.ANY,
    val language: AO3Language = AO3Language.ANY,
    val sort: AO3SearchSort = AO3SearchSort.RELEVANCE
) {
    val hasActiveFilters: Boolean
        get() = fandom.isNotBlank() ||
            characters.isNotBlank() ||
            relationships.isNotBlank() ||
            additionalTags.isNotBlank() ||
            excludedFandoms.isNotBlank() ||
            excludedCharacters.isNotBlank() ||
            excludedRelationships.isNotBlank() ||
            excludedAdditionalTags.isNotBlank() ||
            rating != AO3Rating.ANY ||
            !includeNotRated ||
            warnings.isNotEmpty() ||
            excludedWarnings.isNotEmpty() ||
            categories.isNotEmpty() ||
            excludedCategories.isNotEmpty() ||
            crossover != AO3Crossover.ANY ||
            completion != AO3Completion.ANY ||
            wordsFrom.isNotBlank() ||
            wordsTo.isNotBlank() ||
            updated != AO3Updated.ANY ||
            language != AO3Language.ANY ||
            sort != AO3SearchSort.RELEVANCE

    val isSearchable: Boolean
        get() = query.isNotBlank() || hasActiveFilters

    val searchQuery: String
        get() {
            val clauses = mutableListOf<String>()
            query.trim().takeIf { it.isNotEmpty() }?.let(clauses::add)
            clauses += excludedTags().map { "-\"$it\"" }
            clauses += AO3Warning.entries
                .filter(excludedWarnings::contains)
                .map { "-archive_warning_ids:${it.ao3Id}" }
            clauses += AO3Category.entries
                .filter(excludedCategories::contains)
                .map { "-category_ids:${it.ao3Id}" }
            ratingSearchClause()?.let(clauses::add)
            return clauses.joinToString(" ")
        }

    val structuredRatingId: String?
        get() {
            val ratings = selectedRatings()
            return ratings.singleOrNull()?.ao3Id
        }

    private fun excludedTags(): List<String> {
        return listOf(
            excludedFandoms,
            excludedCharacters,
            excludedRelationships,
            excludedAdditionalTags
        ).flatMap(::commaSeparatedValues).dedupeFirstSeen()
    }

    private fun ratingSearchClause(): String? {
        if (rating == AO3Rating.ANY) {
            return if (includeNotRated) null else "-rating_ids:${AO3Rating.NOT_RATED.ao3Id}"
        }

        val ratings = selectedRatings()
        if (ratings.size <= 1) return null
        return ratings.joinToString(
            separator = " OR ",
            prefix = "(",
            postfix = ")"
        ) { "rating_ids:${it.ao3Id}" }
    }

    private fun selectedRatings(): List<AO3Rating> {
        if (rating == AO3Rating.ANY) return emptyList()
        if (rating == AO3Rating.NOT_RATED) return listOf(AO3Rating.NOT_RATED)

        val ranked = listOf(
            AO3Rating.GENERAL,
            AO3Rating.TEEN,
            AO3Rating.MATURE,
            AO3Rating.EXPLICIT
        )
        val index = ranked.indexOf(rating)
        if (index < 0) return emptyList()

        val selected = when (ratingMatch) {
            AO3RatingMatch.EXACT -> ranked.subList(index, index + 1)
            AO3RatingMatch.OR_HIGHER -> ranked.subList(index, ranked.size)
            AO3RatingMatch.OR_LOWER -> ranked.subList(0, index + 1)
        }.toMutableList()

        if (includeNotRated) selected += AO3Rating.NOT_RATED
        return selected
    }

    companion object {
        fun commaSeparatedValues(field: String): List<String> {
            return field.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
        }
    }
}

enum class AO3Rating(
    val appleCaseName: String,
    val title: String,
    val ao3Id: String?
) {
    ANY("any", "Any rating", null),
    GENERAL("general", "General Audiences", "10"),
    TEEN("teen", "Teen And Up", "11"),
    MATURE("mature", "Mature", "12"),
    EXPLICIT("explicit", "Explicit", "13"),
    NOT_RATED("notRated", "Not Rated", "9");

    companion object {
        val searchCases = listOf(ANY, GENERAL, TEEN, MATURE, EXPLICIT)
    }
}

enum class AO3RatingMatch(val appleCaseName: String, val title: String) {
    EXACT("exact", "Exact"),
    OR_HIGHER("orHigher", "Rating+"),
    OR_LOWER("orLower", "Rating-")
}

enum class AO3Warning(val appleCaseName: String, val ao3Id: String, val title: String) {
    NO_WARNINGS("noWarnings", "16", "No Archive Warnings Apply"),
    CHOOSE_NOT_TO("chooseNotTo", "14", "Creator Chose Not To Use Archive Warnings"),
    VIOLENCE("violence", "17", "Graphic Depictions Of Violence"),
    DEATH("death", "18", "Major Character Death"),
    NON_CON("nonCon", "19", "Rape/Non-Con"),
    UNDERAGE("underage", "20", "Underage Sex")
}

enum class AO3Category(val appleCaseName: String, val ao3Id: String, val title: String) {
    FF("ff", "116", "F/F"),
    FM("fm", "22", "F/M"),
    GEN("gen", "21", "Gen"),
    MM("mm", "23", "M/M"),
    MULTI("multi", "2246", "Multi"),
    OTHER("other", "24", "Other")
}

enum class AO3Crossover(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "Include", null),
    EXCLUDE("exclude", "Exclude", "F"),
    ONLY("only", "Only crossovers", "T")
}

enum class AO3Completion(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "All", null),
    COMPLETE("complete", "Complete", "T"),
    IN_PROGRESS("inProgress", "In Progress", "F")
}

enum class AO3Updated(val appleCaseName: String, val title: String, val ao3Value: String?) {
    ANY("any", "Any time", null),
    WEEK("week", "Past week", "< 1 week ago"),
    MONTH("month", "Past month", "< 1 month ago"),
    SIX_MONTHS("sixMonths", "Past 6 months", "< 6 months ago"),
    YEAR("year", "Past year", "< 1 year ago")
}

enum class AO3Language(val appleCaseName: String, val title: String, val code: String?) {
    ANY("any", "Any language", null),
    ENGLISH("english", "English", "en"),
    SPANISH("spanish", "Spanish", "es"),
    FRENCH("french", "French", "fr"),
    GERMAN("german", "German", "de"),
    CHINESE("chinese", "Chinese", "zh"),
    JAPANESE("japanese", "Japanese", "ja"),
    KOREAN("korean", "Korean", "ko"),
    RUSSIAN("russian", "Russian", "ru"),
    PORTUGUESE("portuguese", "Portuguese (BR)", "ptBR"),
    ITALIAN("italian", "Italian", "it"),
    ARABIC("arabic", "Arabic", "ar"),
    INDONESIAN("indonesian", "Indonesian", "id"),
    DUTCH("dutch", "Dutch", "nl"),
    POLISH("polish", "Polish", "pl"),
    FILIPINO("filipino", "Filipino", "fil"),
    HINDI("hindi", "Hindi", "hi"),
    THAI("thai", "Thai", "th"),
    VIETNAMESE("vietnamese", "Vietnamese", "vi"),
    TURKISH("turkish", "Turkish", "tr")
}

enum class AO3SearchSort(
    val appleCaseName: String,
    val title: String,
    val sortColumn: String?
) {
    RELEVANCE("relevance", "Best Match", null),
    DATE_UPDATED("dateUpdated", "Date Updated", "revised_at"),
    DATE_POSTED("datePosted", "Date Posted", "created_at"),
    WORDS("words", "Word Count", "word_count"),
    KUDOS("kudos", "Kudos", "kudos_count"),
    HITS("hits", "Hits", "hits"),
    COMMENTS("comments", "Comments", "comments_count"),
    BOOKMARKS("bookmarks", "Bookmarks", "bookmarks_count")
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value ->
        if (value.isNotBlank()) seen += value.trim()
    }
    return seen.toList()
}
