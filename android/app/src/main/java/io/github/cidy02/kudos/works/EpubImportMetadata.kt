package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.TextDecoding
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser

internal data class EpubImportMetadata(
    val title: String = "",
    val author: String = "",
    val summary: String = "",
    val sourceUrl: String = "",
    val rating: String = "",
    val language: String = "",
    val publishedDate: String = "",
    val updatedDate: String = "",
    val seriesTitle: String = "",
    val seriesIndex: Int? = null,
    val wordCount: Int? = null,
    val localChapterCount: Int? = null,
    val isComplete: Boolean? = null,
    val chapters: String = "",
    val kudos: Int? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val subjects: List<String> = emptyList(),
    val fandoms: List<String> = emptyList(),
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
    val categories: List<String> = emptyList()
) {
    fun applyTo(work: SavedWork, fillOnly: Boolean): SavedWork {
        var result = work.copy(
            title = assigned(title, work.title, fillOnly),
            author = assigned(author, work.author, fillOnly),
            summary = assigned(summary, work.summary, fillOnly),
            sourceUrl = assigned(sourceUrl, work.sourceUrl, fillOnly),
            rating = assigned(rating, work.rating, fillOnly),
            language = assigned(language, work.language, fillOnly),
            datePublished = assigned(publishedDate, work.datePublished, fillOnly),
            dateUpdated = assigned(updatedDate, work.dateUpdated, fillOnly),
            seriesTitle = assigned(seriesTitle, work.seriesTitle, fillOnly),
            seriesPosition = seriesIndex?.takeIf { !fillOnly || work.seriesPosition == 0 }
                ?: work.seriesPosition,
            isComplete = isComplete?.takeIf { !fillOnly || !work.isComplete }
                ?: work.isComplete,
            wordCount = wordCount?.takeIf { it > 0 && (!fillOnly || work.wordCount == 0) }
                ?: work.wordCount,
            chapters = when {
                chapters.isNotBlank() -> assigned(chapters, work.chapters, fillOnly)
                localChapterCount != null && localChapterCount > 0 && work.chapters.isBlank() ->
                    "$localChapterCount/$localChapterCount"
                else -> work.chapters
            },
            kudos = kudos?.takeIf { it > 0 && (!fillOnly || work.kudos == 0) } ?: work.kudos,
            comments = comments?.takeIf { it > 0 && (!fillOnly || (work.comments ?: 0) == 0) }
                ?: work.comments,
            hits = hits?.takeIf { it > 0 && (!fillOnly || (work.hits ?: 0) == 0) }
                ?: work.hits
        )

        val flatSubjects = subjects
            .map(String::trim)
            .filter { it.isNotEmpty() && it != result.rating }
            .distinct()
        val warningSubjects = flatSubjects.filter { normalized(it) in ARCHIVE_WARNINGS }
        val categorySubjects = flatSubjects.filter { normalized(it) in CATEGORIES }

        val mergedFandoms = replaceOrMerge(result.workFandoms, fandoms, fillOnly)
        val mergedRelationships = replaceOrMerge(result.workRelationships, relationships, fillOnly)
        val mergedCharacters = replaceOrMerge(result.workCharacters, characters, fillOnly)
        var mergedFreeforms = replaceOrMerge(result.workFreeforms, freeforms, fillOnly)
        val mergedWarnings = replaceOrMerge(result.workWarnings, warnings + warningSubjects, fillOnly)
        val mergedCategories = replaceOrMerge(result.workCategories, categories + categorySubjects, fillOnly)
        val categorized = mergedFandoms + mergedRelationships + mergedCharacters + mergedFreeforms
        val known = (categorized + mergedWarnings + mergedCategories + result.rating)
            .mapTo(mutableSetOf(), ::normalized)
        val uncategorized = flatSubjects.filter { normalized(it) !in known }
        val hasCategorizedPrefaceTags = fandoms.isNotEmpty() || relationships.isNotEmpty() ||
            characters.isNotEmpty() || freeforms.isNotEmpty()
        if (hasCategorizedPrefaceTags) {
            mergedFreeforms = (mergedFreeforms + uncategorized).dedupeFirstSeen()
        }
        val fallbackFlat = if (hasCategorizedPrefaceTags) categorized + uncategorized else flatSubjects

        result = result.copy(
            workFandoms = mergedFandoms,
            workRelationships = mergedRelationships,
            workCharacters = mergedCharacters,
            workFreeforms = mergedFreeforms,
            workWarnings = mergedWarnings,
            workCategories = mergedCategories,
            workTags = replaceOrMerge(result.workTags, fallbackFlat, fillOnly),
            workTagsFetched = result.workTagsFetched || hasCategorizedPrefaceTags
        )
        return result
    }

    private fun assigned(incoming: String, existing: String, fillOnly: Boolean): String {
        val value = incoming.trim()
        return if (value.isNotEmpty() && (!fillOnly || existing.isBlank())) value else existing
    }

    private fun replaceOrMerge(existing: List<String>, incoming: List<String>, fillOnly: Boolean): List<String> {
        if (incoming.isEmpty()) return existing
        return ((if (fillOnly) existing else emptyList()) + incoming).dedupeFirstSeen()
    }

    companion object {
        fun inspect(bytes: ByteArray): EpubImportMetadata = EpubMetadataReader.inspect(bytes)

        /**
         * iOS `EPUBDocument.inspectPackage`: a whole ZIP whose package document lists at least
         * one readable spine item. What a restore checks before bytes may replace a local EPUB.
         */
        fun isReadablePackage(bytes: ByteArray): Boolean = EpubMetadataReader.isReadablePackage(bytes)

        private fun normalized(value: String): String = value.trim().lowercase()

        private val ARCHIVE_WARNINGS = setOf(
            "creator chose not to use archive warnings",
            "graphic depictions of violence",
            "major character death",
            "no archive warnings apply",
            "rape/non-con",
            "underage"
        )
        private val CATEGORIES = setOf("f/f", "f/m", "gen", "m/m", "multi", "other")
    }
}

private object EpubMetadataReader {
    fun inspect(bytes: ByteArray): EpubImportMetadata = runCatching {
        val opfText = readOpf(bytes)
        val candidates = linkedMapOf<String, String>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            var remainingBytes = MAX_TOTAL_METADATA_BYTES
            repeat(MAX_ENTRIES) {
                val entry = zip.nextEntry ?: return@use
                if (entry.isDirectory || entry.name.endsWith(".opf", ignoreCase = true) ||
                    !isMetadataCandidate(entry.name)
                ) {
                    return@repeat
                }
                val limit = minOf(MAX_ENTRY_BYTES, remainingBytes)
                if (limit <= 0) return@use
                val entryBytes = zip.readBounded(limit) ?: return@use
                remainingBytes -= entryBytes.size
                TextDecoding.decode(entryBytes)?.let { candidates[entry.name] = it }
            }
        }

        val opf = opfText?.let(::parseOpf) ?: OpfMetadata()
        val extracted = candidates.values.fold(ExtractedMetadata()) { result, text ->
            result.merge(scanPreface(text))
        }.deduplicated()

        EpubImportMetadata(
            title = opf.title.ifBlank { extracted.title },
            author = opf.author.ifBlank { extracted.author },
            summary = opf.summary.ifBlank { extracted.summary },
            sourceUrl = extracted.sourceUrl.ifBlank { opf.sourceUrl },
            rating = extracted.rating.ifBlank { opf.rating },
            language = displayLanguage(opf.language).ifBlank { extracted.language },
            publishedDate = extracted.publishedDate.ifBlank { opf.publishedDate },
            updatedDate = extracted.updatedDate.ifBlank { opf.updatedDate },
            seriesTitle = opf.seriesTitle,
            seriesIndex = opf.seriesIndex,
            wordCount = extracted.wordCount ?: opf.wordCount,
            localChapterCount = opf.localChapterCount,
            isComplete = extracted.isComplete,
            chapters = extracted.chapters,
            kudos = extracted.kudos,
            comments = extracted.comments,
            hits = extracted.hits,
            subjects = opf.subjects,
            fandoms = extracted.fandoms,
            relationships = extracted.relationships,
            characters = extracted.characters,
            freeforms = extracted.freeforms,
            warnings = extracted.warnings,
            categories = extracted.categories
        )
    }.getOrDefault(EpubImportMetadata())

    fun isReadablePackage(bytes: ByteArray): Boolean = hasZipEnd(bytes) &&
        runCatching { readOpf(bytes)?.let(::parseOpf)?.localChapterCount != null }.getOrDefault(false)

    /** A complete ZIP ends with its end-of-central-directory record; a cut-off copy has none. */
    private fun hasZipEnd(bytes: ByteArray): Boolean {
        val last = bytes.size - ZIP_END_BYTES
        return (last downTo maxOf(0, last - MAX_ZIP_COMMENT_BYTES)).any { i ->
            bytes[i] == 0x50.toByte() && bytes[i + 1] == 0x4B.toByte() &&
                bytes[i + 2] == 0x05.toByte() && bytes[i + 3] == 0x06.toByte()
        }
    }

    private fun readOpf(bytes: ByteArray): String? = runCatching {
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            repeat(MAX_ENTRIES) {
                val entry = zip.nextEntry ?: return@use null
                if (!entry.isDirectory && entry.name.endsWith(".opf", ignoreCase = true)) {
                    return@use zip.readBounded(MAX_ENTRY_BYTES)?.let(TextDecoding::decode)
                }
            }
            null
        }
    }.getOrNull()

    private fun parseOpf(text: String): OpfMetadata {
        val document = Jsoup.parse(text, "", Parser.xmlParser())
        val metadataElements = document.getAllElements()
        fun elements(name: String) = metadataElements.filter { it.localName() == name }
        fun first(name: String) = elements(name).firstOrNull()?.text().orEmpty().trim()

        val subjects = elements("subject").map(Element::text).map(String::trim).filter(String::isNotEmpty)
        val sources = elements("source").map(Element::text).map(String::trim).filter(String::isNotEmpty)
        val dates = elements("date").map(Element::text).map(String::trim).filter(String::isNotEmpty)
        val meta = elements("meta")
        fun metaValue(name: String): String = meta.firstOrNull {
            it.attr("name").equals(name, ignoreCase = true)
        }?.let { it.attr("content").ifBlank(it::text) }.orEmpty().trim()

        var published = dates.firstOrNull().orEmpty()
        var updated = ""
        meta.forEach { element ->
            val name = element.attr("name").ifBlank { element.attr("property") }.lowercase()
            val value = element.text().ifBlank { element.attr("content") }.trim()
            if (updated.isEmpty() && "modified" in name) updated = value
            if (published.isEmpty() && ("published" in name || "issued" in name)) published = value
        }
        val manifestIds = elements("item").mapNotNullTo(mutableSetOf()) {
            it.attr("id").takeIf(String::isNotBlank)
        }
        val chapterCount = elements("itemref").count { it.attr("idref") in manifestIds }
        val rating = subjects.firstOrNull { it in RATINGS }.orEmpty()
        val sourceUrl = canonicalWorkUrl(text)
            ?: sources.firstOrNull { it.startsWith("http", ignoreCase = true) }.orEmpty()

        return OpfMetadata(
            title = first("title"),
            author = first("creator"),
            summary = first("description"),
            sourceUrl = sourceUrl,
            rating = rating,
            language = first("language"),
            publishedDate = published,
            updatedDate = updated,
            seriesTitle = metaValue("calibre:series"),
            seriesIndex = metaValue("calibre:series_index").toDoubleOrNull()?.toInt(),
            wordCount = metaValue("calibre:word_count").digitsToInt(),
            localChapterCount = chapterCount.takeIf { it > 0 },
            subjects = subjects
        )
    }

    private fun scanPreface(text: String): ExtractedMetadata {
        val document = Jsoup.parse(text)
        var result = ExtractedMetadata(
            title = firstText(document, "h2.title", "h1.title", "h1", "h2"),
            author = firstText(
                document,
                "h3.byline a[rel=author]",
                "h3.byline a",
                ".byline a[rel=author]",
                ".byline"
            ),
            summary = firstText(
                document,
                ".summary blockquote",
                "blockquote.userstuff",
                "div.summary",
                "section.summary"
            ),
            sourceUrl = canonicalWorkUrl(text).orEmpty(),
            rating = firstText(document, "dd.rating.tags", "dd.rating"),
            language = firstText(document, "dd.language"),
            fandoms = tags(document, "fandom"),
            relationships = tags(document, "relationship"),
            characters = tags(document, "character"),
            freeforms = tags(document, "freeform"),
            warnings = tags(document, "warning"),
            categories = tags(document, "category"),
            wordCount = statInt(document, "words"),
            chapters = stat(document, "chapters"),
            kudos = statInt(document, "kudos"),
            comments = statInt(document, "comments"),
            hits = statInt(document, "hits")
        )

        document.select("dt").forEach { label ->
            val labelText = label.text().trim(' ', ':', '\n', '\t').lowercase()
            val value = label.nextElementSibling() ?: return@forEach
            val values = tagValues(value)
            val plain = value.text().trim()
            result = when {
                "stats" in labelText -> result.merge(parseStats(plain))
                "fandom" in labelText -> result.copy(fandoms = (result.fandoms + values).dedupeFirstSeen())
                "relationship" in labelText -> result.copy(
                    relationships = (result.relationships + values).dedupeFirstSeen()
                )
                "character" in labelText -> result.copy(characters = (result.characters + values).dedupeFirstSeen())
                "additional" in labelText || "freeform" in labelText -> result.copy(
                    freeforms = (result.freeforms + values).dedupeFirstSeen()
                )
                "archive warning" in labelText || labelText == "warnings" -> result.copy(
                    warnings = (result.warnings + values).dedupeFirstSeen()
                )
                labelText == "category" || labelText == "categories" -> result.copy(
                    categories = (result.categories + values).dedupeFirstSeen()
                )
                labelText == "rating" && result.rating.isBlank() -> result.copy(rating = values.firstOrNull() ?: plain)
                labelText == "language" && result.language.isBlank() -> result.copy(language = plain)
                labelText == "words" && result.wordCount == null -> result.copy(wordCount = plain.digitsToInt())
                labelText == "chapters" && result.chapters.isBlank() -> result.copy(chapters = plain)
                "published" in labelText && result.publishedDate.isBlank() -> result.copy(publishedDate = plain)
                "updated" in labelText && result.updatedDate.isBlank() -> result.copy(updatedDate = plain)
                labelText == "status" && result.isComplete == null -> result.copy(
                    isComplete = plain.contains("complete", ignoreCase = true) &&
                        !plain.contains("incomplete", ignoreCase = true)
                )
                else -> result
            }
        }
        return result
    }

    private fun parseStats(text: String) = ExtractedMetadata(
        publishedDate = statValue(text, "Published").orEmpty(),
        updatedDate = statValue(text, "Updated").orEmpty(),
        wordCount = statValue(text, "Words")?.digitsToInt(),
        chapters = statValue(text, "Chapters").orEmpty(),
        kudos = statValue(text, "Kudos")?.digitsToInt(),
        comments = statValue(text, "Comments")?.digitsToInt(),
        hits = statValue(text, "Hits")?.digitsToInt()
    )

    private fun statValue(text: String, label: String): String? {
        val nextLabel = "Published|Updated|Words|Chapters|Kudos|Comments|Bookmarks|Hits"
        return Regex("(?is)\\b$label:\\s*(.+?)(?=\\s+(?:$nextLabel):|$)")
            .find(text)
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            ?.takeIf(String::isNotEmpty)
    }

    private fun tags(document: Document, kind: String): List<String> =
        document.select("dd.$kind.tags a.tag").map(Element::text).dedupeFirstSeen()

    private fun stat(document: Document, kind: String): String =
        document.selectFirst("dl.stats dd.$kind, dd.$kind")?.text().orEmpty().trim()

    private fun statInt(document: Document, kind: String): Int? = stat(document, kind).digitsToInt()

    private fun tagValues(element: Element): List<String> {
        val links = element.select("a.tag, a").map(Element::text).dedupeFirstSeen()
        if (links.isNotEmpty()) return links
        return element.text().split(',', '\n').dedupeFirstSeen()
    }

    private fun firstText(document: Document, vararg selectors: String): String = selectors.firstNotNullOfOrNull {
        document.selectFirst(it)?.text()?.trim()?.takeIf(String::isNotEmpty)
    }.orEmpty()

    private fun displayLanguage(code: String): String {
        val normalized = code.replace("-", "").lowercase()
        return AO3Language.entries.firstOrNull { it.code?.lowercase() == normalized }?.title
            ?: code
    }

    private fun canonicalWorkUrl(text: String): String? {
        val id = AO3_URL.find(text)?.groupValues?.getOrNull(1) ?: return null
        return "https://archiveofourown.org/works/$id"
    }

    private fun isMetadataCandidate(name: String): Boolean =
        name.substringAfterLast('.', "").lowercase() in METADATA_EXTENSIONS

    private fun ZipInputStream.readBounded(limit: Int): ByteArray? {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            if (total > limit) return null
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun String.digitsToInt(): Int? = filter(Char::isDigit).takeIf(String::isNotEmpty)?.toIntOrNull()
    private fun Element.localName(): String = tagName().substringAfter(':').lowercase()

    // ponytail: bounded header walk; raise only if a legitimate 4,000+ member EPUB appears.
    private const val MAX_ENTRIES = 4_096
    private const val ZIP_END_BYTES = 22
    private const val MAX_ZIP_COMMENT_BYTES = 0xFFFF
    private const val MAX_ENTRY_BYTES = 2 * 1024 * 1024
    private const val MAX_TOTAL_METADATA_BYTES = 8 * 1024 * 1024
    private val METADATA_EXTENSIONS = setOf("opf", "xhtml", "html", "htm", "xml")
    private val RATINGS = setOf(
        "General Audiences",
        "Teen And Up Audiences",
        "Mature",
        "Explicit",
        "Not Rated"
    )
    private val AO3_URL = Regex(
        "(?i)(?:https?://)?(?:www\\.)?archiveofourown\\.org/(?:works|downloads)/(\\d+)"
    )
}

private data class OpfMetadata(
    val title: String = "",
    val author: String = "",
    val summary: String = "",
    val sourceUrl: String = "",
    val rating: String = "",
    val language: String = "",
    val publishedDate: String = "",
    val updatedDate: String = "",
    val seriesTitle: String = "",
    val seriesIndex: Int? = null,
    val wordCount: Int? = null,
    val localChapterCount: Int? = null,
    val subjects: List<String> = emptyList()
)

private data class ExtractedMetadata(
    val title: String = "",
    val author: String = "",
    val summary: String = "",
    val sourceUrl: String = "",
    val rating: String = "",
    val language: String = "",
    val publishedDate: String = "",
    val updatedDate: String = "",
    val isComplete: Boolean? = null,
    val wordCount: Int? = null,
    val chapters: String = "",
    val kudos: Int? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val fandoms: List<String> = emptyList(),
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
    val categories: List<String> = emptyList()
) {
    fun merge(incoming: ExtractedMetadata) = copy(
        title = title.ifBlank { incoming.title },
        author = author.ifBlank { incoming.author },
        summary = summary.ifBlank { incoming.summary },
        sourceUrl = sourceUrl.ifBlank { incoming.sourceUrl },
        rating = rating.ifBlank { incoming.rating },
        language = language.ifBlank { incoming.language },
        publishedDate = publishedDate.ifBlank { incoming.publishedDate },
        updatedDate = updatedDate.ifBlank { incoming.updatedDate },
        isComplete = isComplete ?: incoming.isComplete,
        wordCount = wordCount ?: incoming.wordCount,
        chapters = chapters.ifBlank { incoming.chapters },
        kudos = kudos ?: incoming.kudos,
        comments = comments ?: incoming.comments,
        hits = hits ?: incoming.hits,
        fandoms = (fandoms + incoming.fandoms).dedupeFirstSeen(),
        relationships = (relationships + incoming.relationships).dedupeFirstSeen(),
        characters = (characters + incoming.characters).dedupeFirstSeen(),
        freeforms = (freeforms + incoming.freeforms).dedupeFirstSeen(),
        warnings = (warnings + incoming.warnings).dedupeFirstSeen(),
        categories = (categories + incoming.categories).dedupeFirstSeen()
    )

    fun deduplicated(): ExtractedMetadata {
        val categorized = fandoms + relationships + characters + warnings + categories + rating
        val keys = categorized.mapTo(mutableSetOf()) { it.trim().lowercase() }
        return copy(
            fandoms = fandoms.dedupeFirstSeen(),
            relationships = relationships.dedupeFirstSeen(),
            characters = characters.dedupeFirstSeen(),
            freeforms = freeforms.filter { it.trim().lowercase() !in keys }.dedupeFirstSeen(),
            warnings = warnings.dedupeFirstSeen(),
            categories = categories.dedupeFirstSeen()
        )
    }
}
