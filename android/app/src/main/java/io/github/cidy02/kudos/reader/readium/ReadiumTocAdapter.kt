package io.github.cidy02.kudos.reader.readium

import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import io.github.cidy02.kudos.reader.ReaderSection
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderTocBuilder
import io.github.cidy02.kudos.reader.ReaderTocEntry
import kotlin.math.roundToInt
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.positions
import org.readium.r2.shared.util.Url

/**
 * Maps a Readium [Publication] to engine-agnostic [ReaderTocEntry] rows and
 * resolves a row back to a [Link] for navigator jumps. Also builds normalized
 * [ReaderSection]s for the progress pill (spine-index ↔ TOC kind detection).
 */
object ReadiumTocAdapter {

    /** Match by href, never by an index into position groups (empty resources can be absent). */
    fun chapterStartLocator(
        positions: List<List<Locator>>, href: String
    ): Locator? = positions.asSequence().flatten().firstOrNull {
        ReaderSectionBuilder.hrefKey(it.href.toString()) == ReaderSectionBuilder.hrefKey(href)
    }

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
    fun sections(publication: Publication): List<ReaderSection> =
        sections(publication.tableOfContents, publication.readingOrder)

    internal fun sections(toc: List<Link>, readingOrder: List<Link>): List<ReaderSection> {
        val spineHrefs = readingOrder.map { it.url().toString() }
        val spineKeyToIndex = LinkedHashMap<String, Int>()
        spineHrefs.forEachIndexed { index, href ->
            val key = ReaderSectionBuilder.hrefKey(href)
            // First spine wins for reverse lookup.
            if (key !in spineKeyToIndex) spineKeyToIndex[key] = index
        }

        val rawEntries = ArrayList<ReaderSectionBuilder.RawTOCEntry>()
        val seen = mutableSetOf<Int>()
        for (link in toc.flattenLinks()) {
            val href = link.url().toString()
            if (href.isBlank()) continue
            val key = ReaderSectionBuilder.hrefKey(href)
            val spineIndex = spineKeyToIndex[key] ?: continue
            // Preorder traversal: the outer title owns a shared file, as on iOS.
            if (!seen.add(spineIndex)) continue
            val title = link.title?.trim().orEmpty().ifEmpty { "Section ${spineIndex + 1}" }
            rawEntries += ReaderSectionBuilder.RawTOCEntry(title = title, spineIndex = spineIndex)
        }

        return ReaderSectionBuilder.build(rawEntries, spineHrefs)
    }

    /**
     * Where in the work each file starts, as a whole percent, from its first position (iOS
     * `chapterStartPercent`). Keyed by [ReaderSectionBuilder.hrefKey], so a contents row that
     * carries a fragment finds its file. Empty when the publication has no positions.
     */
    suspend fun startPercents(publication: Publication): Map<String, Int> = withContext(Dispatchers.Default) {
        // Off the main thread: a long work has thousands of positions (A49 F11).
        startPercents(
            runCatching { publication.positions() }.getOrDefault(emptyList())
                .map { it.href.toString() to it.locations.totalProgression }
        )
    }

    /** Each file's first position only. */
    internal fun startPercents(positions: List<Pair<String, Double?>>): Map<String, Int> {
        val starts = LinkedHashMap<String, Int>()
        for ((href, progression) in positions) {
            val file = ReaderSectionBuilder.hrefKey(href)
            if (file !in starts && progression != null) starts[file] = (progression * 100).roundToInt()
        }
        return starts
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
