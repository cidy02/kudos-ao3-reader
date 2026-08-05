package io.github.cidy02.kudos.works.converters

/**
 * Parses the label block that calibre / FanFicFare put at the top of an exported
 * work (iOS `CalibreMetadataPage`):
 *
 * ```
 * Story: In the Service of the Queen
 * Storylink: https://www.fanfiction.net/s/10251701/1/
 * Category: Frozen
 * Genre: Romance/Fantasy
 * Rating: M
 * Status: Complete
 * Summary: Anna lives a rugged life…
 * ```
 *
 * Recovering `Storylink` is the valuable part: it's what lets a converted PDF
 * know where it came from, so the work isn't stranded without a source URL.
 */
data class CalibreMetadata(
    val title: String? = null,
    val author: String? = null,
    val sourceUrl: String? = null,
    val fandoms: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val rating: String? = null,
    val isComplete: Boolean? = null,
    val summary: String? = null
) {
    companion object {
        /**
         * How many distinct labels a block must carry before we treat it as a
         * metadata page. Three keeps an ordinary chapter that happens to open
         * with "Summary:" from being mistaken for one.
         */
        private const val MIN_LABELS = 3

        /**
         * Longest label first, so `Storylink:` can never be swallowed by
         * `Story:`. Order here is load-bearing — don't sort it alphabetically.
         */
        private val LABELS: List<Pair<String, Field>> = listOf(
            "storylink" to Field.SourceUrl,
            "story url" to Field.SourceUrl,
            "storyurl" to Field.SourceUrl,
            "category" to Field.Fandom,
            "fandom" to Field.Fandom,
            "summary" to Field.Summary,
            "author" to Field.Author,
            "rating" to Field.Rating,
            "status" to Field.Status,
            "genre" to Field.Genre,
            "tags" to Field.Genre,
            "story" to Field.Title,
            "title" to Field.Title
        ).sortedByDescending { it.first.length }

        private enum class Field { Title, Author, SourceUrl, Fandom, Genre, Rating, Status, Summary }

        fun parse(lines: List<String>): CalibreMetadata? {
            val found = mutableMapOf<Field, String>()
            for (raw in lines) {
                val line = raw.trim()
                if (line.isEmpty() || !line.contains(':')) continue
                val lower = line.lowercase()
                val match = LABELS.firstOrNull { (label, _) -> lower.startsWith("$label:") } ?: continue
                val value = line.substring(match.first.length + 1).trim()
                if (value.isNotEmpty()) found.putIfAbsent(match.second, value)
            }
            if (found.size < MIN_LABELS) return null

            return CalibreMetadata(
                title = found[Field.Title],
                author = found[Field.Author],
                sourceUrl = found[Field.SourceUrl]?.takeIf { it.startsWith("http", ignoreCase = true) },
                fandoms = found[Field.Fandom].splitList(),
                freeforms = found[Field.Genre].splitList(),
                rating = found[Field.Rating],
                isComplete = found[Field.Status]?.let { it.equals("complete", ignoreCase = true) },
                summary = found[Field.Summary]
            )
        }

        /** Exporters write these slash- or comma-separated ("Romance/Fantasy"). */
        private fun String?.splitList(): List<String> =
            this?.split('/', ',')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
    }
}
