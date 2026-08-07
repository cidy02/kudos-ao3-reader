package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants

data class AO3WorkSummary(
    val id: Long,
    val title: String,
    val authors: List<String>,
    val fandoms: List<String>,
    val rating: String,
    val warnings: List<String>,
    val categories: List<String>,
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val summary: String = "",
    val language: String = "",
    val wordCount: Int? = null,
    val chapters: String = "",
    val kudos: Int? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val bookmarks: Int? = null,
    val seriesTitle: String? = null,
    val seriesPosition: Int? = null,
    val seriesUrl: String? = null,
    val isComplete: Boolean? = null,
    val isRestricted: Boolean = false,
    val updatedDate: String = "",
    val publishedDate: String? = null
) {
    val workUrl: String
        get() = "${AO3Constants.BASE_URL}/works/$id"

    val authorText: String
        get() = authors.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: "Anonymous"
}

data class AO3SearchPage(
    val works: List<AO3WorkSummary>,
    val currentPage: Int,
    val totalPages: Int,
    /** AO3's own result-count heading, when the page carries one. */
    val summary: AO3ResultSummary? = null
)

/**
 * The count line AO3 prints above a works list — "92,495 Found",
 * "1 - 20 of 142,322 Works in Naruto (Anime & Manga)", "1 - 20 of 535 Works by
 * astolat".
 *
 * The total is the part worth having: it is the only place AO3 states how many
 * works match, and it is not derivable from a page of 20 blurbs.
 */
data class AO3ResultSummary(
    /** Total matching works across every page. */
    val total: Int,
    /**
     * AO3's own qualifier, verbatim and including its preposition — "in Naruto
     * (Anime & Manga)", "by astolat". Null on `/works/search`, whose heading is
     * just "<n> Found" and names no subject. Kept whole because it is what the
     * spoken label reads out; the card shows [subject] instead.
     */
    val scope: String? = null,
    /**
     * Which works this page is showing — 1..20 from AO3's "1 - 20 of …". Null on
     * `/works/search`, which states a total and no range.
     */
    val range: IntRange? = null
) {
    /**
     * The subject with AO3's preposition removed — "Naruto (Anime & Manga)",
     * "astolat" — for use as a heading, where "in Naruto" would read oddly.
     */
    val subject: String?
        get() {
            val value = scope ?: return null
            for (preposition in listOf("in ", "by ")) {
                if (value.startsWith(preposition)) return value.removePrefix(preposition)
            }
            return value
        }

    /**
     * Fills in what a `/works/search` heading leaves out.
     *
     * A tag or user list heading states its subject and its range; a search states
     * only "142,327 Found". A screen scoped to one fandom knows it *is* that
     * fandom's works list and knows which page it asked for, so it can complete its
     * own card rather than showing a bare number. Anything AO3 actually said wins:
     * this only ever fills a null.
     *
     * [onPageCount] is how many works came back, which is what makes the last
     * (short) page come out right. Only the *start* of the range depends on
     * [WORKS_PER_PAGE], so if AO3 ever changed its page size, page 1 would still be
     * correct and later pages would drift — bounded and visible, not silent.
     */
    fun completing(subject: String?, page: Int, onPageCount: Int): AO3ResultSummary {
        var derived: IntRange? = null
        if (range == null && onPageCount > 0 && page > 0) {
            val first = (page - 1) * WORKS_PER_PAGE + 1
            derived = first..maxOf(first, minOf(first + onPageCount - 1, total))
        }
        return copy(
            scope = scope ?: subject?.let { "in $it" },
            range = range ?: derived
        )
    }

    /**
     * Which tag category this list's subject is, for the heading's glyph.
     *
     * Read off the works already on screen rather than asked of AO3: every work here
     * carries the subject tag by definition, and the blurb parser has already sorted
     * each work's tags into fandoms / relationships / characters / freeforms using
     * AO3's own markup classes. So the answer is sitting in the page just parsed — no
     * `/tags/<name>` round-trip, no guessing from the name.
     *
     * A user list ("by astolat") is not a tag at all, hence the `by` short-circuit.
     * Null when nothing matches — a work tagged with a *synonym* displays the synonym
     * while the heading shows the canonical name, and no icon beats a wrong one.
     */
    fun subjectCategory(works: List<AO3WorkSummary>): SubjectCategory? {
        val name = subject ?: return null
        if (scope?.startsWith("by ") == true) return SubjectCategory.CHARACTER
        val needle = name.lowercase()
        fun List<String>.hit() = any { it.lowercase() == needle }
        for (work in works) {
            if (work.fandoms.hit()) return SubjectCategory.FANDOM
            if (work.relationships.hit()) return SubjectCategory.RELATIONSHIP
            if (work.characters.hit()) return SubjectCategory.CHARACTER
            if (work.freeforms.hit()) return SubjectCategory.FREEFORM
        }
        return null
    }

    enum class SubjectCategory { FANDOM, CHARACTER, RELATIONSHIP, FREEFORM }

    companion object {
        /**
         * AO3 serves 20 works per page. Verified live 2026-08-06 on `/works/search`,
         * and it is what AO3 itself prints on a tag list ("1 - 20 of …").
         */
        const val WORKS_PER_PAGE = 20
    }
}
