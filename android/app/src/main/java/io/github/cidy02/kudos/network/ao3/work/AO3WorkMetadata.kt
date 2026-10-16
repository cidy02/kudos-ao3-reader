package io.github.cidy02.kudos.network.ao3.work

data class AO3WorkMetadata(
    val rating: String = "",
    val fandoms: List<String> = emptyList(),
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val language: String = "",
    val words: Int? = null,
    val chapters: String = "",
    val kudos: Int? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val kudosGivenByCurrentUser: Boolean = false,
    /** The work's own byline by account (`AO3AuthorIdentities.json`); empty for Anonymous. */
    val authorIdentitiesJSON: String = "",
    /** The work's heading, byline and summary: all a page reached by its id alone has of them. */
    val title: String = "",
    val authors: List<String> = emptyList(),
    val summary: String = "",
    val datePublished: String = "",
    val dateUpdated: String = "",
    val isComplete: Boolean? = null
) {
    val flattenedTags: List<String>
        get() = (fandoms + relationships + characters + freeforms).dedupeFirstSeen()

    val isEmpty: Boolean
        get() = fandoms.isEmpty() &&
            relationships.isEmpty() &&
            characters.isEmpty() &&
            freeforms.isEmpty() &&
            warnings.isEmpty() &&
            categories.isEmpty() &&
            language.isBlank() &&
            words == null &&
            chapters.isBlank() &&
            kudos == null &&
            comments == null &&
            hits == null &&
            datePublished.isBlank() &&
            dateUpdated.isBlank() &&
            isComplete == null
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value ->
        val trimmed = value.trim()
        if (trimmed.isNotEmpty()) seen += trimmed
    }
    return seen.toList()
}
