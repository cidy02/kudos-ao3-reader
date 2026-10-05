package io.github.cidy02.kudos.reader

/** Pure port of iOS ReaderSearchGrouping: current section first, then ascending spine order. */
object ReaderSearchGrouping {
    data class Group<Result>(
        val spineIndex: Int,
        val title: String,
        val results: List<Result>
    )

    fun <Result> grouped(
        results: List<Result>,
        hrefKey: (Result) -> String,
        sections: List<ReaderSection>,
        currentSpineIndex: Int?
    ): List<Group<Result>> {
        if (results.isEmpty()) return emptyList()
        val sectionByKey = sections.associateBy { ReaderSectionBuilder.hrefKey(it.href) }
        val buckets = results.groupBy { sectionByKey[hrefKey(it)]?.spineIndex ?: -1 }
        return buckets.keys.sortedWith(
            compareBy<Int> { if (it == currentSpineIndex) 0 else 1 }.thenBy { it }
        ).map { index ->
            val section = sectionByKey[hrefKey(buckets.getValue(index).first())]
            val title = if (index == currentSpineIndex) {
                "This Chapter" + (section?.let(::placeSuffix) ?: "")
            } else {
                section?.title ?: "This Work"
            }
            Group(index, title, buckets.getValue(index))
        }
    }

    private fun placeSuffix(section: ReaderSection): String = when (section.kind) {
        ReaderSectionKind.CHAPTER -> section.storyChapterIndex?.let { " (Ch. $it)" } ?: ""
        ReaderSectionKind.PREFACE -> " (Preface)"
        ReaderSectionKind.SUMMARY -> " (Summary)"
        ReaderSectionKind.AFTERWORD -> " (Afterword)"
        ReaderSectionKind.OTHER -> ""
    }
}
