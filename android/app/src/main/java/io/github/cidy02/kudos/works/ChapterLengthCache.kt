package io.github.cidy02.kudos.works

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderSectionKind
import io.github.cidy02.kudos.ui.components.ChapterBarGeometry
import io.github.cidy02.kudos.ui.components.ChapterBarLayout
import io.github.cidy02.kudos.ui.components.ChapterBarModel
import io.github.cidy02.kudos.ui.components.ChapterBarScale
import java.io.File
import java.net.URI
import java.util.Locale
import java.util.zip.ZipFile
import kotlin.math.ceil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser

/**
 * One downloaded work's chapter lengths, story chapters only, in reading order.
 * [positions] are Readium position weights (reading progress is measured in them);
 * [words] are word counts (chapter bars' heights).
 */
data class ChapterLengths(
    val positions: List<Int>,
    val words: List<Int>
)

/**
 * Publication labels and per-chapter progress stored in a Readium locator,
 * handling both Android's envelope and raw Readium locator JSON.
 */
object WorkReadingPosition {
    private val json = Json { ignoreUnknownKeys = true }

    fun title(locatorJson: String?): String? {
        if (locatorJson.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(locatorJson) }.getOrNull() as? JsonObject
            ?: return null
        val target = (root["locator"] as? JsonObject) ?: root
        val title = (target["title"] as? JsonPrimitive)?.contentOrNull?.trim()
        return title?.takeIf { it.isNotEmpty() }
    }

    fun chapterProgress(locatorJson: String?): Double? {
        if (locatorJson.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(locatorJson) }.getOrNull() as? JsonObject
            ?: return null
        val target = (root["locator"] as? JsonObject) ?: root
        val locations = target["locations"] as? JsonObject ?: return null
        val value = locations["progression"] as? JsonPrimitive ?: return null
        if (value.isString) return null
        val progression = value.doubleOrNull ?: return null
        return progression.coerceIn(0.0, 1.0)
    }

    /** Readium's position weight for one ZIP entry: `max(1, ceil(bytes / 1024))`. */
    fun positionsForEntryLength(bytes: Int): Int =
        maxOf(1, ceil(maxOf(0, bytes) / 1024.0).toInt())
}

/**
 * Per-chapter lengths for downloaded works, cached under `cacheDir/ChapterLengths/lengths.json`.
 * Not-downloaded works receive `null`, keeping every bar the same height.
 */
object ChapterLengthCache {
    @Serializable
    data class Record(
        val byteCount: Long,
        val modifiedAt: Long,
        val weights: List<Int>,
        val words: List<Int>? = null
    )

    @Serializable
    private data class Store(
        val works: MutableMap<String, Record> = linkedMapOf()
    )

    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }
    private val headRegex = Regex("""(?is)<head\b.*?</head>""")
    private val tagRegex = Regex("""<[^>]+>""")
    private val whitespaceRegex = Regex("""\s+""")

    fun keptWeights(record: Record?, byteCount: Long, modifiedAt: Long): List<Int>? {
        if (record == null || record.byteCount != byteCount || record.modifiedAt != modifiedAt) return null
        return record.weights
    }

    fun weights(workId: String, epubFile: File, cacheDir: File): List<Int>? {
        val stamp = stampOf(epubFile) ?: return null
        val record = synchronized(lock) { load(cacheDir).works[workId] }
        keptWeights(record, stamp.first, stamp.second)?.let { return it }
        return lengths(workId, epubFile, cacheDir)?.positions
    }

    fun lengths(workId: String, epubFile: File, cacheDir: File): ChapterLengths? {
        val stamp = stampOf(epubFile) ?: return null
        val record = synchronized(lock) { load(cacheDir).works[workId] }
        val keptPositions = keptWeights(record, stamp.first, stamp.second)
        val keptWords = record?.words
        if (keptPositions != null && keptWords != null) {
            return ChapterLengths(positions = keptPositions, words = keptWords)
        }

        val measured = storyChapterLengths(epubFile) ?: return null

        synchronized(lock) {
            val current = stampOf(epubFile) ?: return null
            val fresh = load(cacheDir)
            fresh.works[workId] = Record(
                byteCount = current.first,
                modifiedAt = current.second,
                weights = measured.positions,
                words = measured.words
            )
            save(fresh, cacheDir)
            if (current != stamp) return null
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
            val store = load(cacheDir)
            store.works[workId] = Record(
                byteCount = stamp.first,
                modifiedAt = stamp.second,
                weights = weights,
                words = words
            )
            save(store, cacheDir)
        }
    }

    fun wordCountOfXhtml(xhtml: String): Int {
        val body = headRegex.replace(xhtml, " ")
        val text = tagRegex.replace(body, " ").trim()
        if (text.isEmpty()) return 0
        return text.split(whitespaceRegex).count { it.isNotEmpty() }
    }

    fun storyChapterLengths(epubFile: File): ChapterLengths? = runCatching {
        if (!epubFile.isFile) return null
        ZipFile(epubFile).use { zip ->
            val containerEntry = zip.getEntry("META-INF/container.xml") ?: return null
            val containerXml = zip.getInputStream(containerEntry).bufferedReader().use { it.readText() }
            val containerDoc = Jsoup.parse(containerXml, "", Parser.xmlParser())
            val opfPath = containerDoc.getAllElements()
                .firstOrNull { it.localTagName() == "rootfile" }
                ?.attr("full-path")
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: return null
            val opfEntry = zip.getEntry(opfPath) ?: return null
            val opfXml = zip.getInputStream(opfEntry).bufferedReader().use { it.readText() }
            val opfDoc = Jsoup.parse(opfXml, "", Parser.xmlParser())
            val opfDir = opfPath.substringBeforeLast('/', "")

            fun resolveOpfRelative(href: String): String {
                val clean = href.substringBefore('#').trim()
                val joined = if (opfDir.isEmpty()) clean else "$opfDir/$clean"
                return runCatching { URI("/$joined").normalize().path.removePrefix("/") }
                    .getOrDefault(joined)
            }

            val manifestById = linkedMapOf<String, Pair<String, String>>()
            opfDoc.getAllElements()
                .filter { it.localTagName() == "item" }
                .forEach { item ->
                    val id = item.attr("id").trim()
                    val href = item.attr("href").trim()
                    val props = item.attr("properties").trim()
                    if (id.isNotEmpty() && href.isNotEmpty()) {
                        manifestById[id] = resolveOpfRelative(href) to props
                    }
                }

            val spinePaths = opfDoc.getAllElements()
                .filter { it.localTagName() == "itemref" }
                .mapNotNull { itemRef -> manifestById[itemRef.attr("idref").trim()]?.first }
            if (spinePaths.isEmpty()) return null

            val spineIndexByKey = linkedMapOf<String, Int>()
            spinePaths.forEachIndexed { index, path ->
                spineIndexByKey.putIfAbsent(ReaderSectionBuilder.hrefKey(path), index)
            }

            val tocEntries = parseTocEntries(
                zip = zip,
                opfDoc = opfDoc,
                manifestById = manifestById,
                resolveOpfRelative = ::resolveOpfRelative,
                spineIndexByKey = spineIndexByKey
            )
            val sections = ReaderSectionBuilder.build(
                tocEntries = tocEntries,
                spineHrefs = spinePaths.map { it.substringAfterLast('/') }
            )

            val positions = mutableListOf<Int>()
            val words = mutableListOf<Int>()
            for (section in sections) {
                if (section.kind != ReaderSectionKind.CHAPTER) continue
                val path = spinePaths.getOrNull(section.spineIndex) ?: continue
                val zipEntry = zip.getEntry(path)
                val entryBytes = zipEntry?.let { entry ->
                    val declared = entry.size
                    if (declared >= 0L) declared.toInt()
                    else zip.getInputStream(entry).use { it.readBytes().size }
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

        val ncxId = opfDoc.getAllElements().firstOrNull { it.localTagName() == "spine" }?.attr("toc").orEmpty()
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

    private fun Element.localTagName(): String =
        tagName().substringAfter(':').lowercase(Locale.ROOT)

    private fun stampOf(file: File): Pair<Long, Long>? {
        if (!file.isFile) return null
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
}

/**
 * Measures chapter lengths off the main thread for downloaded works.
 * Returns `null` immediately when [work] is null or not downloaded, keeping every bar the same height.
 */
@Composable
fun rememberChapterLengths(work: SavedWork?): ChapterLengths? {
    val context = LocalContext.current
    val epubId = work?.takeIf { it.hasEpub }?.id
    val lengths by produceState<ChapterLengths?>(initialValue = null, epubId) {
        if (epubId == null) {
            value = null
            return@produceState
        }
        value = withContext(Dispatchers.IO) {
            val file = runCatching {
                WorkFileStore(context.filesDir.toPath()).workEpubPath(epubId).toFile()
            }.getOrNull() ?: return@withContext null
            ChapterLengthCache.lengths(workId = epubId, epubFile = file, cacheDir = context.cacheDir)
        }
    }
    return lengths
}

/**
 * Shared chapter-bar layout and `"Ch N · P%"` progress label for any row displaying [work].
 */
@Composable
fun rememberWorkChapterBarState(
    work: SavedWork,
    scale: ChapterBarScale = ChapterBarScale.Row,
    newChapterCount: Int = if (work.hasUpdate) {
        maxOf(0, work.postedChapterCount - (work.knownChapterCount ?: work.postedChapterCount))
    } else 0
): Pair<ChapterBarLayout, String?> {
    val chapterLengths = rememberChapterLengths(work)
    val progress = work.readingProgress
    val layout = remember(work.chapters, progress, work.isFinished, chapterLengths, newChapterCount, scale) {
        ChapterBarModel.layout(
            chapters = work.chapters,
            progress = progress,
            isFinished = work.isFinished,
            weights = chapterLengths?.positions,
            heights = chapterLengths?.words,
            newChapterCount = newChapterCount,
            scale = scale
        )
    }
    val label = remember(work.chapters, progress, work.isFinished, chapterLengths) {
        ChapterBarGeometry.progressLabel(
            chapters = work.chapters,
            progress = progress,
            isFinished = work.isFinished,
            weights = chapterLengths?.positions
        )
    }
    return layout to label
}
