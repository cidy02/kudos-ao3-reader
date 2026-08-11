package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.ReaderSection
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderTocBuilder
import io.github.cidy02.kudos.reader.ReaderTocEntry
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url

/**
 * Maps a Readium [Publication] to engine-agnostic [ReaderTocEntry] rows and
 * resolves a row back to a [Link] for navigator jumps. Also builds normalized
 * [ReaderSection]s for the progress pill (spine-index ↔ TOC kind detection).
 */
object ReadiumTocAdapter {

    fun entries(publication: Publication): List<ReaderTocEntry> {
        return ReaderTocBuilder.build(
            toc = publication.tableOfContents.map { it.toSourceLink() },
            readingOrder = publication.readingOrder.map { it.toSourceLink() }
        )
    }

    /**
     * Normalize the publication's TOC + reading order into one [ReaderSection]
     * per spine item (kinds + story-chapter numbering for the progress pill).
     */
    fun sections(publication: Publication): List<ReaderSection> {
        val spineHrefs = publication.readingOrder.map { it.url().toString() }
        val spineKeyToIndex = LinkedHashMap<String, Int>()
        spineHrefs.forEachIndexed { index, href ->
            val key = ReaderSectionBuilder.hrefKey(href)
            // First spine win for reverse lookup; TOC→spine still last-wins via build().
            if (key !in spineKeyToIndex) spineKeyToIndex[key] = index
        }

        val rawEntries = ArrayList<ReaderSectionBuilder.RawTOCEntry>()
        for (link in publication.tableOfContents.flattenLinks()) {
            val href = link.url().toString()
            if (href.isBlank()) continue
            val key = ReaderSectionBuilder.hrefKey(href)
            val spineIndex = spineKeyToIndex[key] ?: continue
            val title = link.title?.trim().orEmpty().ifEmpty { "Section ${spineIndex + 1}" }
            rawEntries += ReaderSectionBuilder.RawTOCEntry(title = title, spineIndex = spineIndex)
        }

        return ReaderSectionBuilder.build(rawEntries, spineHrefs)
    }

    /** Resolve a TOC row to a publication [Link] suitable for [org.readium.r2.navigator.Navigator.go]. */
    fun resolveLink(publication: Publication, entry: ReaderTocEntry): Link? {
        val url = Url(entry.href)
        if (url != null) {
            publication.linkWithHref(url)?.let { return it }
            publication.readingOrder.firstOrNull { it.url() == url }?.let { return it }
            publication.tableOfContents.flattenLinks().firstOrNull { it.url() == url }?.let { return it }
        }
        // String fallback for relative href forms that don't parse cleanly as Url.
        val href = entry.href
        return publication.readingOrder.firstOrNull { link ->
            link.url().toString() == href || link.href.toString() == href
        } ?: publication.tableOfContents.flattenLinks().firstOrNull { link ->
            link.url().toString() == href || link.href.toString() == href
        }
    }

    private fun Link.toSourceLink(): ReaderTocBuilder.SourceLink =
        ReaderTocBuilder.SourceLink(
            title = title,
            href = url().toString(),
            children = children.map { it.toSourceLink() }
        )

    private fun List<Link>.flattenLinks(): List<Link> {
        val out = ArrayList<Link>()
        for (link in this) {
            out += link
            out += link.children.flattenLinks()
        }
        return out
    }
}
