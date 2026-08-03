package io.github.cidy02.kudos.reader

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.search.isSearchable
import org.readium.r2.shared.publication.services.search.search

data class ReaderSearchHit(
    val locator: Locator,
    val snippet: String,
    val chapterTitle: String
)

/**
 * Full-text Find-in-Work via Readium's [SearchService] (StringSearchService).
 * Port of Apple `ReaderSearchModel` / `SearchIterator` pacing.
 */
@OptIn(ExperimentalReadiumApi::class)
object ReaderSearch {
    fun isAvailable(publication: Publication): Boolean = publication.isSearchable

    suspend fun search(
        publication: Publication,
        query: String,
        maxResults: Int = 200
    ): List<ReaderSearchHit> = withContext(Dispatchers.IO) {
        val trimmed = query.trim()
        if (trimmed.isEmpty() || !publication.isSearchable) return@withContext emptyList()
        val iterator = publication.search(trimmed) ?: return@withContext emptyList()
        try {
            val hits = mutableListOf<ReaderSearchHit>()
            while (hits.size < maxResults) {
                val page = iterator.next()
                val collection = page.getOrNull() ?: break
                for (locator in collection.locators) {
                    val highlight = locator.text.highlight.orEmpty()
                    val before = locator.text.before.orEmpty().takeLast(40)
                    val after = locator.text.after.orEmpty().take(40)
                    val snippet = buildString {
                        if (before.isNotBlank()) append("…").append(before)
                        append(highlight)
                        if (after.isNotBlank()) append(after).append("…")
                    }.ifBlank { highlight.ifBlank { trimmed } }
                    hits.add(
                        ReaderSearchHit(
                            locator = locator,
                            snippet = snippet.replace(Regex("\\s+"), " ").trim(),
                            chapterTitle = locator.title.orEmpty()
                        )
                    )
                    if (hits.size >= maxResults) break
                }
            }
            hits
        } finally {
            iterator.close()
        }
    }
}
