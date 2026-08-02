package io.github.cidy02.kudos.reader

/**
 * Classification of a single EPUB reading-order (spine) item. AO3's own export
 * (and Calibre's re-splitting of it into per-file EPUBs) puts a Preface and
 * optional Afterword around the real story chapters; neither the reader index
 * nor the progress pill should count those as numbered chapters.
 *
 * Faithful port of iOS `ReaderSectionKind` / `ReaderSection` / `ReaderSectionBuilder`
 * from `kudos-ao3-reader/Reading/ReaderSection.swift`.
 */
enum class ReaderSectionKind {
    PREFACE,
    SUMMARY,
    CHAPTER,
    AFTERWORD,
    /** Spine item with no TOC entry that isn't the Preface→Chapter-1 Summary gap. */
    OTHER
}

/**
 * One normalized reading-order item, aligned 1:1 with the EPUB's spine —
 * [ReaderSectionBuilder.build] always returns exactly `spineHrefs.size` entries,
 * in spine order, so `sections[spineIndex]` is always valid.
 *
 * [storyChapterIndex] is the 1-based position among [ReaderSectionKind.CHAPTER]
 * entries only; null for every other kind.
 */
data class ReaderSection(
    val href: String,
    val title: String,
    val kind: ReaderSectionKind,
    val spineIndex: Int,
    val storyChapterIndex: Int?
)

/** Count of real story chapters only (excludes preface/summary/afterword/other). */
val List<ReaderSection>.storyChapterCount: Int
    get() = count { it.kind == ReaderSectionKind.CHAPTER }

/**
 * Reconciles an EPUB's own (possibly incomplete) table of contents against its
 * full spine into normalized [ReaderSection]s. Pure and engine-agnostic: callers
 * resolve their own TOC representation down to spine-index + title pairs before
 * calling [build].
 */
object ReaderSectionBuilder {

    /** One TOC entry already resolved to the spine index it targets. */
    data class RawTOCEntry(
        val title: String,
        val spineIndex: Int
    )

    /**
     * @param tocEntries the EPUB's own navigation entries, each resolved to a
     *   spine index. Order doesn't matter; duplicates for the same spine index
     *   keep the last one.
     * @param spineHrefs every reading-order item's href, in spine order — the
     *   source of truth for how many sections exist and what order they're in.
     */
    fun build(tocEntries: List<RawTOCEntry>, spineHrefs: List<String>): List<ReaderSection> {
        if (spineHrefs.isEmpty()) return emptyList()

        val titleBySpineIndex = LinkedHashMap<Int, String>()
        for (entry in tocEntries) {
            if (entry.spineIndex in spineHrefs.indices) {
                titleBySpineIndex[entry.spineIndex] = entry.title
            }
        }

        val sections = ArrayList<ReaderSection>(spineHrefs.size)
        var storyChapterCounter = 0
        // Only an EPUB that has an actual "Preface"-titled TOC entry can trigger
        // Summary synthesis below — the one AO3-specific signal, so a non-AO3 EPUB
        // (no Preface entry at all) falls through to "every spine item with a TOC
        // match is a .chapter, numbered by story order".
        var sawPreface = false
        // Once true, an untitled gap no longer reads as "the Summary gap".
        var summaryGapClosed = false

        for (index in spineHrefs.indices) {
            val href = spineHrefs[index]
            val tocTitle = titleBySpineIndex[index]
            if (tocTitle != null) {
                val kind = classify(tocTitle)
                if (kind == ReaderSectionKind.PREFACE) sawPreface = true
                if (kind != ReaderSectionKind.PREFACE) summaryGapClosed = true
                val storyIndex: Int? = if (kind == ReaderSectionKind.CHAPTER) {
                    storyChapterCounter += 1
                    storyChapterCounter
                } else {
                    null
                }
                sections += ReaderSection(
                    href = href,
                    title = tocTitle,
                    kind = kind,
                    spineIndex = index,
                    storyChapterIndex = storyIndex
                )
            } else if (sawPreface && !summaryGapClosed) {
                // AO3's Summary: invisible to the TOC by construction, but it
                // always sits right after Preface and before Chapter 1.
                summaryGapClosed = true
                sections += ReaderSection(
                    href = href,
                    title = "Summary",
                    kind = ReaderSectionKind.SUMMARY,
                    spineIndex = index,
                    storyChapterIndex = null
                )
            } else {
                sections += ReaderSection(
                    href = href,
                    title = "Section ${index + 1}",
                    kind = ReaderSectionKind.OTHER,
                    spineIndex = index,
                    storyChapterIndex = null
                )
            }
        }
        return sections
    }

    /**
     * AO3/Calibre labels are exact ("Preface", "Summary", "Afterword");
     * everything else — "Chapter 1", "Epilogue", "Epilogue: Chapter 1" — is real
     * story content.
     */
    internal fun classify(title: String): ReaderSectionKind {
        return when (title.trim().lowercase()) {
            "preface" -> ReaderSectionKind.PREFACE
            "summary" -> ReaderSectionKind.SUMMARY
            "afterword" -> ReaderSectionKind.AFTERWORD
            else -> ReaderSectionKind.CHAPTER
        }
    }

    /**
     * Fragment- and path-insensitive comparison key for matching a TOC href
     * (which may carry a `#fragment` or a differently-prefixed relative path)
     * against a spine item's own href.
     */
    fun hrefKey(href: String): String {
        val noFragment = href.substringBefore('#')
        val lastSegment = noFragment.substringAfterLast('/')
        return lastSegment.lowercase()
    }
}
