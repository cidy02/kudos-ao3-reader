package io.github.cidy02.kudos.network.ao3.chapters

import org.jsoup.Jsoup

/**
 * One chapter from a work's `/navigate` index (iOS `AO3ChapterRef`).
 *
 * [position] is 1-based within the work, and is what the reader hands to the
 * comments screen; [chapterId] is AO3's own id (`/works/<wid>/chapters/<id>`).
 */
data class AO3ChapterRef(
    val chapterId: Long,
    val position: Int,
    val title: String,
    val dateText: String = ""
) {
    /** "Chapter 3 · Title", or just "Chapter 3" when AO3's default title repeats. */
    val displayName: String
        get() {
            val generic = "Chapter $position"
            return if (title.isBlank() || title == generic) generic else "$generic · $title"
        }
}

/**
 * Parses `/works/<id>/navigate` (iOS `AO3Client.parseChapterIndex`).
 *
 * AO3 renders the index as `ol.chapter.index` with one `li` per chapter, each
 * containing a `/chapters/<id>` link whose text is "3. Chapter title".
 */
object AO3ChapterIndexParser {

    fun parse(html: String): List<AO3ChapterRef> {
        val document = Jsoup.parse(html)
        val index = document.selectFirst("ol.chapter.index") ?: return emptyList()
        val rows = index.select("li")
        val chapters = mutableListOf<AO3ChapterRef>()

        for (row in rows) {
            val link = row.selectFirst("a[href*=/chapters/]") ?: continue
            val chapterId = link.attr("href")
                .trimEnd('/')
                .substringAfterLast('/')
                .toLongOrNull() ?: continue

            // AO3 writes "3. Title". Prefer its own number over our running count:
            // a work with a deleted chapter still numbers the rest correctly.
            val text = link.text().trim()
            val dot = text.indexOf('.')
            val declared = if (dot > 0) text.substring(0, dot).trim().toIntOrNull() else null
            val position = declared ?: (chapters.size + 1)
            val title = if (declared != null) text.substring(dot + 1).trim() else text

            chapters += AO3ChapterRef(
                chapterId = chapterId,
                position = position,
                title = title,
                dateText = row.selectFirst("span.datetime")?.text()?.trim()?.trim('(', ')').orEmpty()
            )
        }
        return chapters
    }
}
