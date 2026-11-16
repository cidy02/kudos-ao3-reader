package io.github.cidy02.kudos.works.converters

import io.github.cidy02.kudos.files.TextDecoding
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.nodes.Entities
import org.jsoup.safety.Safelist

/**
 * AO3's own "Download → HTML" file, rebuilt as the EPUB AO3 would have served.
 *
 * AO3 makes its EPUB by running calibre over this very HTML, so the two carry the
 * same content; what calibre adds is the split into sections, the OPF metadata and
 * the embedded images, and those are what this reproduces.
 *
 * Ground truth is otwarchive at 452391b648f2 (2026-11-01):
 * `app/views/downloads/{show,_download_preface,_download_chapter,_download_afterword}.html.erb`
 * for the markup, `config/locales/views/en.yml` for the labels, and
 * `DownloadWriter#get_calibre_command` for the split (its `--chapter` XPaths) and
 * the metadata it passes.
 */
object AO3HtmlDownloadConverter {
    private const val MAX_IMAGES = 60
    private const val MAX_TOTAL_IMAGE_BYTES = 40L * 1024 * 1024

    /** AO3's `barebones` layout rules that are about structure rather than typography. */
    private const val STYLESHEET = """
p.message, .meta h1, .meta h2, .meta .byline { text-align: center; }
.meta dl.tags { border: 1px solid; padding: 1em; }
.meta .endnote-link { font-size: 0.8em; }
img { max-width: 100%; height: auto; }
"""

    /**
     * Null when [bytes] is not an AO3 HTML download — AO3 answers a download it
     * cannot serve with an ordinary page, and that must not become a book.
     *
     * [fetchImage] returns an image's bytes or null. AO3's EPUB carries the work's
     * images inside it, so this one does too; an image that cannot be fetched is
     * left out.
     */
    suspend fun toEpub(bytes: ByteArray, fetchImage: suspend (String) -> ByteArray? = { null }): ByteArray? {
        val html = TextDecoding.decode(bytes) ?: return null
        val document = Jsoup.parse(html, AO3Constants.BASE_URL)
        val preface = document.selectFirst("body > div#preface") ?: return null
        val chapters = document.selectFirst("body > div#chapters") ?: return null
        val book = readBook(document, preface)
        // Hidden in AO3's file; they exist only to give calibre its section names.
        document.select(".toc-heading").remove()

        // calibre starts a section at the Preface, at each chapter's heading, and at
        // the Afterword. A single-chapter work has no chapter heading: its one
        // section is named for the work.
        val sections = mutableListOf<Pair<String, MutableList<Element>>>("Preface" to mutableListOf(preface))
        val firstChapter = sections.size
        for (child in chapters.children()) {
            val heading = child.takeIf { it.hasClass("meta") && it.hasClass("group") }?.selectFirst("> h2.heading")
            if (heading != null || sections.size == firstChapter) {
                sections += (heading?.text()?.trim().orEmpty().ifEmpty { book.title }) to mutableListOf()
            }
            sections.last().second.add(child)
        }
        if (sections.size == firstChapter) return null
        document.selectFirst("body > div#afterword")?.let { sections += "Afterword" to mutableListOf(it) }

        relinkAnchors(sections.map { it.second })
        val images = embedImages(sections.flatMap { it.second }, fetchImage)

        val built = sections.map { (title, elements) ->
            EpubBuilder.Chapter(
                title,
                Jsoup.clean(
                    elements.joinToString("\n") { it.outerHtml() },
                    AO3Constants.BASE_URL,
                    SAFELIST,
                    Document.OutputSettings()
                        .syntax(Document.OutputSettings.Syntax.xml)
                        .escapeMode(Entities.EscapeMode.xhtml)
                        .prettyPrint(false)
                )
            )
        }
        return EpubBuilder.buildEpub(book, built, images, STYLESHEET)
    }

    private fun readBook(document: Document, preface: Element): EpubBuilder.Book {
        val meta = preface.selectFirst("div.meta")
        val byline = meta?.selectFirst("> div.byline")
        fun labelled(label: String): Element? = preface.select("dl.tags > dt")
            .firstOrNull { it.text().trim().startsWith(label, ignoreCase = true) }
            ?.nextElementSibling()
        val stats = labelled("Stats")?.text().orEmpty()
        val series = labelled("Series")
        val languageName = labelled("Language")?.text()?.trim().orEmpty()
        return EpubBuilder.Book(
            title = meta?.selectFirst("> h1")?.text()?.trim().orEmpty().ifEmpty { document.title() },
            author = byline?.select("a[rel=author]")?.eachText()?.joinToString(", ").orEmpty()
                .ifEmpty { byline?.text().orEmpty().trim().removePrefix("by ").trim() },
            // The page's own `lang` is the site's locale, not the work's language.
            language = AO3Language.entries.firstOrNull { it.title.equals(languageName, ignoreCase = true) }?.code ?: "en",
            description = meta?.children()
                ?.firstOrNull { it.tagName() == "p" && it.text().trim() == "Summary" }
                ?.nextElementSibling()?.takeIf { it.tagName() == "blockquote" }?.text().orEmpty(),
            source = preface.select("p.message a[href*=/works/]").lastOrNull()?.absUrl("href").orEmpty(),
            // calibre is given the date the work was last revised.
            date = (Regex("(?:Updated|Completed): (\\d{4}-\\d{2}-\\d{2})").find(stats)
                ?: Regex("Published: (\\d{4}-\\d{2}-\\d{2})").find(stats))?.groupValues?.get(1).orEmpty(),
            // Tag links only: the same list also links the work's series and collections.
            subjects = preface.select("dl.tags dd a[href*=/tags/]").eachText().distinct(),
            seriesTitle = series?.selectFirst("a[href*=/series/]")?.text().orEmpty(),
            seriesIndex = Regex("Part (\\d+) of").find(series?.text().orEmpty())?.groupValues?.get(1).orEmpty(),
            dir = listOf(document.selectFirst("html"), document.body())
                .firstNotNullOfOrNull { element ->
                    element?.attr("dir")?.trim()?.lowercase()?.takeIf { it in VALID_DIRS }
                }.orEmpty()
        )
    }

    /**
     * "See the end of the work for notes" is a link to `#endnotes`, which lands in a
     * different file once the work is split, so it has to name that file. Every other
     * link is made absolute, as it would be in a browser.
     */
    private fun relinkAnchors(sections: List<List<Element>>) {
        val sectionOfId = HashMap<String, Int>()
        sections.forEachIndexed { index, elements ->
            elements.forEach { element -> element.select("[id]").forEach { sectionOfId.putIfAbsent(it.id(), index) } }
        }
        for (link in sections.flatten().flatMap { it.select("a[href]") }) {
            val href = link.attr("href")
            if (href.startsWith("#")) {
                sectionOfId[href.drop(1)]?.let { link.attr("href", "section-$it.xhtml$href") }
            } else {
                link.absUrl("href").takeIf(String::isNotEmpty)?.let { link.attr("href", it) }
            }
        }
    }

    private suspend fun embedImages(
        elements: List<Element>,
        fetchImage: suspend (String) -> ByteArray?
    ): Map<String, ByteArray> {
        val images = LinkedHashMap<String, ByteArray>()
        val pathOfUrl = HashMap<String, String?>()
        var total = 0L
        for (image in elements.flatMap { it.select("img") }) {
            val url = image.absUrl("src")
            val path = if (url in pathOfUrl) pathOfUrl[url] else {
                val data = if (url.startsWith("http") && images.size < MAX_IMAGES && total < MAX_TOTAL_IMAGE_BYTES) {
                    fetchImage(url)
                } else {
                    null
                }
                val extension = data?.let(::imageExtension)
                val fits = data != null && extension != null && total + data.size <= MAX_TOTAL_IMAGE_BYTES
                (if (fits) "images/image-${images.size + 1}.$extension" else null).also {
                    pathOfUrl[url] = it
                    if (it != null && data != null) {
                        images[it] = data
                        total += data.size
                    }
                }
            }
            // Never left pointing at its host: the reader must not fetch on a page turn.
            if (path == null) image.remove() else image.attr("src", path)
        }
        return images
    }

    /** By content, never by what the host says it is: only real images go in the book. */
    private fun imageExtension(data: ByteArray): String? {
        fun startsWith(vararg bytes: Int) = data.size > bytes.size && bytes.indices.all { data[it] == bytes[it].toByte() }
        return when {
            startsWith(0xFF, 0xD8, 0xFF) -> "jpg"
            startsWith(0x89, 0x50, 0x4E, 0x47) -> "png"
            startsWith(0x47, 0x49, 0x46, 0x38) -> "gif"
            startsWith(0x52, 0x49, 0x46, 0x46) && data.size > 12 &&
                data.copyOfRange(8, 12).contentEquals("WEBP".toByteArray()) -> "webp"
            else -> null
        }
    }

    /**
     * `class` and `id` stay because AO3's structure is in them (`dl.tags`, `div.meta`,
     * `#endnotes`), and the importers that read an AO3 EPUB's preface read it by
     * those names. Neither can carry script.
     */
    private val VALID_DIRS = setOf("rtl", "ltr", "auto")

    private val SAFELIST: Safelist = Safelist.relaxed()
        .preserveRelativeLinks(true)
        .addTags("bdo", "bdi")
        .addAttributes(":all", "class", "id", "dir", "lang")
}
