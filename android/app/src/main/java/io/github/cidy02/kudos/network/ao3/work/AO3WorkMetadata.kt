package io.github.cidy02.kudos.network.ao3.work

data class AO3WorkMetadata(
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
    val hits: Int? = null
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
            hits == null
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value ->
        val trimmed = value.trim()
        if (trimmed.isNotEmpty()) seen += trimmed
    }
    return seen.toList()
}
