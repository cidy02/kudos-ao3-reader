package io.github.cidy02.kudos.works

object WorkTags {
    fun ao3WorkIdFromUrl(url: String): Long? {
        val marker = "/works/"
        val index = url.indexOf(marker)
        if (index < 0) return null
        return url.substring(index + marker.length)
            .takeWhile(Char::isDigit)
            .toLongOrNull()
    }

    fun flattenedWorkTags(
        fandoms: List<String>,
        relationships: List<String>,
        characters: List<String>,
        freeforms: List<String>
    ): List<String> {
        return (fandoms + relationships + characters + freeforms).dedupeFirstSeen()
    }
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seen = linkedSetOf<String>()
    forEach { value ->
        val trimmed = value.trim()
        if (trimmed.isNotEmpty()) seen += trimmed
    }
    return seen.toList()
}
