package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.network.ao3.AO3URLResolver

object WorkTags {
    fun ao3WorkIdFromUrl(url: String): Long? {
        val marker = "/works/"
        val index = url.indexOf(marker)
        if (index < 0) return null
        return url.substring(index + marker.length)
            .takeWhile(Char::isDigit)
            .toLongOrNull()
    }

    /** Apple `canonicalAO3WorkURL` — stable identity for merge/dedup. */
    fun canonicalAO3WorkURL(url: String): String? {
        val id = ao3WorkIdFromUrl(url) ?: return null
        return AO3URLResolver.canonicalWorkUrl(id)
    }

    fun flattenedWorkTags(
        fandoms: List<String>,
        relationships: List<String>,
        characters: List<String>,
        freeforms: List<String>
    ): List<String> {
        return (fandoms + relationships + characters + freeforms).dedupeFirstSeen()
    }

    fun ao3WorkUrl(workId: Long): String {
        return "https://archiveofourown.org/works/$workId?view_adult=true"
    }
}

internal fun Iterable<String>.dedupeFirstSeen(): List<String> {
    val seenKeys = mutableSetOf<String>()
    val result = mutableListOf<String>()
    forEach { value ->
        val trimmed = value.trim()
        if (trimmed.isNotEmpty() && seenKeys.add(trimmed.lowercase())) {
            result.add(trimmed)
        }
    }
    return result
}
