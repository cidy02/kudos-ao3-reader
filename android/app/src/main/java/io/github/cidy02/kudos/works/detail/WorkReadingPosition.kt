package io.github.cidy02.kudos.works.detail

import android.content.Context
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderSectionKind
import java.io.File
import java.net.URI
import java.util.Locale
import java.util.zip.ZipFile
import kotlin.math.ceil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import org.jsoup.Jsoup
import org.jsoup.parser.Parser

/**
 * Pure Readium locator helpers matching iOS `WorkReadingPosition`.
 */
object WorkReadingPosition {
    private val json = Json { ignoreUnknownKeys = true }

    /** `locations.progression` (in-chapter 0..1) from raw locator JSON or an Android envelope. */
    fun chapterProgress(locatorJson: String?): Double? {
        if (locatorJson.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(locatorJson) }.getOrNull() as? JsonObject
            ?: return null
        val inner = root["locator"] as? JsonObject
        val raw = progressionOf(inner) ?: progressionOf(root) ?: return null
        return raw.coerceIn(0.0, 1.0)
    }

    fun title(locatorJson: String?): String? = HomeFacts.locatorTitle(locatorJson)

    private fun progressionOf(obj: JsonObject?): Double? {
        val locations = obj?.get("locations") as? JsonObject ?: return null
        val value = locations["progression"] as? JsonPrimitive ?: return null
        if (value.isString) return null
        return value.contentOrNull?.toDoubleOrNull()
    }

    /** Readium position weight for one ZIP entry: `max(1, ceil(bytes / 1024))`. */
    fun positionsForEntryLength(bytes: Int): Int =
        maxOf(1, ceil(maxOf(0, bytes) / 1024.0).toInt())
}

data class ChapterLengths(
    val positions: List<Int>,
    val words: List<Int>
)

/**
 * Per-chapter lengths for [io.github.cidy02.kudos.ui.components.ChapterBars], kept in app caches
 * (excluded from Android backups). Mirrors iOS `ChapterLengthCache`.
 */
object ChapterLengthCache {
    @Serializable
    data class Record(
        val byteCount: Long,
        val modifiedAtMillis: Long,
        val weights: List<Int>,
        val words: List<Int>? = null
    )

    @Serializable
    private data class Store(
        val works: Map<String, Record> = emptyMap()
    )

    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }
    private val headRegex = Regex("(?is)<head\\b.*?</head>")
    private val tagRegex = Regex("<[^>]+>")
    private val whitespaceRegex = Regex("\\s+")

    fun keptWeights(record: Record?, byteCount: Long, modifiedAtMillis: Long): List<Int>? {
        if (record == null || record.byteCount != byteCount || record.modifiedAtMillis != modifiedAtMillis) {
            return null
        }
        return record.weights
    }

    fun taskKey(work: SavedWork?, epubFile: File?): String {
        if (work == null || !work.hasEpub || epubFile == null || !epubFile.exists()) return "none"
        return "${work.id}-${epubFile.length()}-${epubFile.lastModified()}"
    }

    suspend fun lengths(context: Context, work: SavedWork): ChapterLengths? {
        if (!work.hasEpub) return null
        val epubFile = File(File(context.filesDir, "works"), "${work.id}.epub")
        if (!epubFile.exists()) return null
        val cacheDir = context.cacheDir
        return withContext(Dispatchers.IO) {
            lengths(workId = work.id, epubFile = epubFile, cacheDir = cacheDir)
        }
    }

    fun lengths(workId: String, epubFile: File, cacheDir: File): ChapterLengths? {
        val stamp = stampOf(epubFile) ?: return null
        val record = synchronized(lock) { load(cacheDir).works[workId] }
        val kept = keptWeights(record, stamp.first, stamp.second)
        if (kept != null && record?.words != null) {
            return ChapterLengths(positions = kept, words = record.words)
        }

        val measured = measureEpub(epubFile) ?: return null

        synchronized(lock) {
            val current = stampOf(epubFile) ?: return null
            val fresh = load(cacheDir).works.toMutableMap()
            fresh[workId] = Record(
                byteCount = current.first,
                modifiedAtMillis = current.second,
                weights = measured.positions,
                words = measured.words
            )
            save(Store(fresh), cacheDir)
            if (current.first != stamp.first || current.second != stamp.second) return null
            return measured
        }
    }

    fun store(
        workId: String,
        epubFile: File,
        weights: List<Int>,
        words: List<Int>? = null,
        cacheDir: File
    ) {
        val stamp = stampOf(epubFile) ?: return
        synchronized(lock) {
            val fresh = load(cacheDir).works.toMutableMap()
            fresh[workId] = Record(
                byteCount = stamp.first,
                modifiedAtMillis = stamp.second,
                weights = weights,
                words = words
            )
            save(Store(fresh), cacheDir)
        }
    }

    internal fun wordCountOfXhtml(xhtml: String): Int {
        val body = headRegex.replace(xhtml, " ")
        val stripped = tagRegex.replace(body, " ").trim()
        if (stripped.isEmpty()) return 0
        return stripped.split(whitespaceRegex).count { it.isNotEmpty() }
    }

    private fun measureEpub(epubFile: File): ChapterLengths? = runCatching {
        ZipFile(epubFile).use { zip ->
            val containerEntry = zip.getEntry("META-INF/container.xml") ?: return null
            val containerXml = zip.getInputStream(containerEntry).bufferedReader().use { it.readText() }
            val containerDoc = Jsoup.parse(containerXml, "", Parser.xmlParser())
            val opfPath = containerDoc.select("rootfile").firstOrNull()?.attr("full-path")?.trim()
                ?.takeIf { it.isNotEmpty() } ?: return null
            val opfEntry = zip.getEntry(opfPath) ?: return null
            val opfXml = zip.getInputStream(opfEntry).bufferedReader().use { it.readText() }
            val opfDoc = Jsoup.parse(opfXml, "", Parser.xmlParser())

            val opfDir = opfPath.substringBeforeLast('/', "")
            fun resolveOpfRelative(href: String): String {
                val cleaned = href.substringBefore('#').trim()
                if (cleaned.isEmpty()) return ""
                val combined = if (opfDir.isEmpty()) cleaned else "$opfDir/$cleaned"
                return runCatching { URI("/$combined").normalize().path.removePrefix("/") }
                    .getOrDefault(combined)
            }

            val manifestById = HashMap<String, Pair<String, String>>()
            opfDoc.getAllElements().filter { it.localName() == "item" }.forEach { item ->
                val id = item.attr("id")
                val href = item.attr("href")
                val props = item.attr("properties")
                if (id.isNotBlank() && href.isNotBlank()) {
                    manifestById[id] = resolveOpfRelative(href) to props
                }
            }

            val spinePaths = opfDoc.getAllElements()
                .filter { it.localName() == "itemref" }
                .mapNotNull { manifestById[it.attr("idref")]?.first }
            if (spinePaths.isEmpty()) return null

            val spineIndexByKey = LinkedHashMap<String, Int>()
            spinePaths.forEachIndexed { idx, path ->
                val key = ReaderSectionBuilder.hrefKey(path)
                if (key !in spineIndexByKey) spineIndexByKey[key] = idx
            }

            val rawToc = parseTocEntries(zip, opfDoc, manifestById, ::resolveOpfRelative, spineIndexByKey)
            val sections = ReaderSectionBuilder.build(
                tocEntries = rawToc,
                spineHrefs = spinePaths.map { it.substringAfterLast('/') }
            )

            val positions = mutableListOf<Int>()
            val words = mutableListOf<Int>()
            for (section in sections) {
                if (section.kind != ReaderSectionKind.CHAPTER) continue
                val entryPath = spinePaths.getOrNull(section.spineIndex) ?: continue
                val zipEntry = zip.getEntry(entryPath)
                val entryBytes = zipEntry?.size?.takeIf { it >= 0 }?.toInt()
                    ?: zipEntry?.let { entry ->
                        zip.getInputStream(entry).use { it.readBytes().size }
                    } ?: 0
                positions += WorkReadingPosition.positionsForEntryLength(entryBytes)
                val xhtml = zipEntry?.let { entry ->
                    zip.getInputStream(entry).bufferedReader().use { it.readText() }
                }.orEmpty()
                words += wordCountOfXhtml(xhtml)
            }
            if (positions.isEmpty()) null else ChapterLengths(positions = positions, words = words)
        }
    }.getOrNull()

    private fun parseTocEntries(
        zip: ZipFile,
        opfDoc: org.jsoup.nodes.Document,
        manifestById: Map<String, Pair<String, String>>,
        resolveOpfRelative: (String) -> String,
        spineIndexByKey: Map<String, Int>
    ): List<ReaderSectionBuilder.RawTOCEntry> {
        val results = mutableListOf<ReaderSectionBuilder.RawTOCEntry>()
        val seen = mutableSetOf<Int>()

        // Prefer EPUB 3 nav document if declared, else NCX.
        val navItem = manifestById.values.firstOrNull { (_, props) ->
            props.split(' ').any { it.equals("nav", ignoreCase = true) }
        }?.first
        if (navItem != null) {
            zip.getEntry(navItem)?.let { entry ->
                val navDir = navItem.substringBeforeLast('/', "")
                val html = zip.getInputStream(entry).bufferedReader().use { it.readText() }
                val doc = Jsoup.parse(html)
                val nav = doc.select("nav[epub\\:type=toc], nav[role=doc-toc], nav").firstOrNull()
                nav?.select("a[href]")?.forEach { a ->
                    val rawHref = a.attr("href").substringBefore('#').trim()
                    val full = if (navDir.isEmpty()) rawHref else "$navDir/$rawHref"
                    val normalized = runCatching { URI("/$full").normalize().path.removePrefix("/") }
                        .getOrDefault(full)
                    val spineIndex = spineIndexByKey[ReaderSectionBuilder.hrefKey(normalized)]
                        ?: return@forEach
                    if (seen.add(spineIndex)) {
                        val label = a.text().trim().ifEmpty { "Section ${spineIndex + 1}" }
                        results += ReaderSectionBuilder.RawTOCEntry(label, spineIndex)
                    }
                }
            }
        }
        if (results.isNotEmpty()) return results

        val ncxId = opfDoc.getAllElements().firstOrNull { it.localName() == "spine" }?.attr("toc").orEmpty()
        val ncxPath = manifestById[ncxId]?.first ?: manifestById.values.firstOrNull { (path, _) ->
            path.lowercase(Locale.ROOT).endsWith(".ncx")
        }?.first ?: return emptyList()

        val ncxEntry = zip.getEntry(ncxPath) ?: return emptyList()
        val ncxDir = ncxPath.substringBeforeLast('/', "")
        val ncxXml = zip.getInputStream(ncxEntry).bufferedReader().use { it.readText() }
        val ncxDoc = Jsoup.parse(ncxXml, "", Parser.xmlParser())
        ncxDoc.select("navPoint").forEach { np ->
            val src = np.selectFirst("content")?.attr("src")?.substringBefore('#')?.trim().orEmpty()
            val full = if (ncxDir.isEmpty()) src else "$ncxDir/$src"
            val normalized = runCatching { URI("/$full").normalize().path.removePrefix("/") }
                .getOrDefault(full)
            val spineIndex = spineIndexByKey[ReaderSectionBuilder.hrefKey(normalized)]
                ?: spineIndexByKey[ReaderSectionBuilder.hrefKey(resolveOpfRelative(src))]
                ?: return@forEach
            if (seen.add(spineIndex)) {
                val label = np.selectFirst("navLabel > text")?.text()?.trim().orEmpty()
                    .ifEmpty { "Section ${spineIndex + 1}" }
                results += ReaderSectionBuilder.RawTOCEntry(label, spineIndex)
            }
        }
        return results
    }

    private fun stampOf(file: File): Pair<Long, Long>? {
        if (!file.exists()) return null
        return file.length() to file.lastModified()
    }

    private fun storeFile(cacheDir: File): File =
        File(File(cacheDir, "ChapterLengths"), "lengths.json")

    private fun load(cacheDir: File): Store = runCatching {
        val file = storeFile(cacheDir)
        if (!file.exists()) return Store()
        json.decodeFromString<Store>(file.readText())
    }.getOrDefault(Store())

    private fun save(store: Store, cacheDir: File) {
        runCatching {
            val file = storeFile(cacheDir)
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, "lengths.json.tmp")
            temp.writeText(json.encodeToString(store))
            if (!temp.renameTo(file)) {
                file.writeText(json.encodeToString(store))
                temp.delete()
            }
        }
    }

    private fun org.jsoup.nodes.Element.localName(): String =
        tagName().substringAfter(':').lowercase(Locale.ROOT)
}
