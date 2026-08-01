package io.github.cidy02.kudos.reader

/**
 * Builds a flat TOC list for the chapters sheet.
 *
 * Prefers an explicit TOC (flattened in document order, preserving depth).
 * When the TOC is empty, falls back to the reading-order/spine titles.
 */
object ReaderTocBuilder {

    data class SourceLink(
        val title: String?,
        val href: String,
        val children: List<SourceLink> = emptyList()
    )

    fun build(
        toc: List<SourceLink>,
        readingOrder: List<SourceLink>
    ): List<ReaderTocEntry> {
        val fromToc = flatten(toc, depth = 0)
        if (fromToc.isNotEmpty()) return fromToc
        return readingOrder.mapIndexed { index, link ->
            ReaderTocEntry(
                title = displayTitle(link.title, index),
                href = link.href,
                depth = 0
            )
        }
    }

    private fun flatten(links: List<SourceLink>, depth: Int): List<ReaderTocEntry> {
        if (links.isEmpty()) return emptyList()
        val out = ArrayList<ReaderTocEntry>()
        links.forEachIndexed { index, link ->
            if (link.href.isNotBlank()) {
                out += ReaderTocEntry(
                    title = displayTitle(link.title, index),
                    href = link.href,
                    depth = depth
                )
            }
            out += flatten(link.children, depth + 1)
        }
        return out
    }

    private fun displayTitle(title: String?, index: Int): String {
        val trimmed = title?.trim().orEmpty()
        return trimmed.ifEmpty { "Section ${index + 1}" }
    }
}
