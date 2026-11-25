package io.github.cidy02.kudos.works

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderSectionKind
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FilterInputStream
import java.io.InputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser

/**
 * Finds author-supplied art already inside a downloaded EPUB. Never requests remote images.
 *
 * Faithful port of iOS `EmbeddedWorkCoverImage` (`UIComponents/EmbeddedWorkCoverImage.swift:7-111`)
 * and alpha/EXIF normalization from `EPUBCoverExport` (`Reading/EPUBCoverExport.swift:170-205`).
 */
object EmbeddedWorkCoverImage {
    const val MAX_IMAGE_BYTES: Int = 20_000_000
    const val MAX_DIMENSION_PX: Int = 20_000
    const val MIN_SHORT_SIDE_PX: Int = 320
    const val MIN_ASPECT_RATIO: Double = 0.40
    const val MAX_ASPECT_RATIO: Double = 1.85
    const val MAX_THUMBNAIL_PX: Int = 600
    const val MAX_IMAGE_CANDIDATES: Int = 64
    private const val MAX_IMAGE_TAGS: Int = 512
    private const val MAX_HEADER_BYTES: Int = 1_048_576
    private const val MAX_TEXT_ENTRY_BYTES: Int = 4_000_000
    private const val JPEG_QUALITY: Int = 86
    private const val VIRTUAL_ROOT: String = "/KudosGeneratedCoverArt/"

    class Candidate(
        val data: ByteArray,
        val frontMatter: Boolean,
        val pixelArea: Long
    )

    private data class SelectedEntry(
        val entryName: String,
        val frontMatter: Boolean,
        val pixelArea: Long,
        val order: Int
    )

    /** Front matter always beats chapter images; ties break by larger pixel area. */
    fun preferred(current: Candidate?, candidate: Candidate): Candidate {
        if (current == null) return candidate
        return if (beats(current.frontMatter, current.pixelArea, candidate.frontMatter, candidate.pixelArea)) {
            candidate
        } else {
            current
        }
    }

    private fun beats(
        currentFrontMatter: Boolean,
        currentPixelArea: Long,
        candidateFrontMatter: Boolean,
        candidatePixelArea: Long
    ): Boolean = if (candidateFrontMatter != currentFrontMatter) {
        candidateFrontMatter
    } else {
        candidatePixelArea > currentPixelArea
    }

    /** Exact iOS `EmbeddedWorkCoverImage.accepts(width:height:)` bounds. */
    fun accepts(width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0 || width > MAX_DIMENSION_PX || height > MAX_DIMENSION_PX) {
            return false
        }
        val aspect = width.toDouble() / height.toDouble()
        return minOf(width, height) >= MIN_SHORT_SIDE_PX && aspect in MIN_ASPECT_RATIO..MAX_ASPECT_RATIO
    }

    /**
     * Reads only the central-directory entries needed (`META-INF/container.xml`, OPF, TOC,
     * spine XHTML documents `0..firstChapter`, and local candidate image headers) without unpacking
     * the archive. Image dimensions are decoded from bounded streams before buffering full bytes,
     * repeated hrefs are deduplicated, candidates are capped at [MAX_IMAGE_CANDIDATES], and only
     * the winning image entry is read into memory.
     */
    fun data(epubFile: File, isCancelled: () -> Boolean = { false }): ByteArray? {
        if (!epubFile.isFile || isCancelled()) return null
        return runCatching {
            ZipFile(epubFile).use { zip ->
                val containerEntry = zip.getEntry("META-INF/container.xml") ?: return@use null
                val containerBytes = readEntryBounded(zip, containerEntry, MAX_TEXT_ENTRY_BYTES, isCancelled)
                    ?: return@use null
                if (isCancelled()) return@use null
                val opfRawPath = rootfilePath(containerBytes.toString(Charsets.UTF_8)) ?: return@use null

                val rootUri = URI(null, null, VIRTUAL_ROOT, null)
                val opfName = toVirtualUri(opfRawPath)?.let(::entryNameFrom)
                    ?.takeIf { zip.getEntry(it) != null }
                    ?: resolveRelative(rootUri, opfRawPath)?.takeIf { zip.getEntry(it) != null }
                    ?: return@use null
                val opfUri = toVirtualUri(opfName) ?: return@use null
                val opfEntry = zip.getEntry(opfName) ?: return@use null
                val opfBytes = readEntryBounded(zip, opfEntry, MAX_TEXT_ENTRY_BYTES, isCancelled)
                    ?: return@use null
                if (isCancelled()) return@use null
                val opfDoc = Jsoup.parse(opfBytes.toString(Charsets.UTF_8), "", Parser.xmlParser())

                val manifestById = linkedMapOf<String, ManifestItem>()
                opfDoc.getAllElements()
                    .filter { it.localTagName() == "item" }
                    .forEach { item ->
                        val id = item.attr("id").trim()
                        val href = item.attr("href").trim()
                        if (id.isNotEmpty() && href.isNotEmpty()) {
                            val resolved = resolveRelative(opfUri, href) ?: return@forEach
                            manifestById[id] = ManifestItem(
                                path = resolved,
                                mediaType = item.attr("media-type").trim(),
                                properties = item.attr("properties").trim()
                            )
                        }
                    }

                val pages = opfDoc.getAllElements()
                    .filter { it.localTagName() == "itemref" }
                    .mapNotNull { itemRef -> manifestById[itemRef.attr("idref").trim()]?.path }
                if (pages.isEmpty() || isCancelled()) return@use null

                val spineIndexByKey = linkedMapOf<String, Int>()
                pages.forEachIndexed { index, path ->
                    spineIndexByKey.putIfAbsent(fileKey(path), index)
                }

                val tocEntries = parseTocEntries(
                    zip = zip,
                    opfDoc = opfDoc,
                    manifestById = manifestById,
                    spineIndexByKey = spineIndexByKey,
                    isCancelled = isCancelled
                )
                if (isCancelled()) return@use null
                val sections = ReaderSectionBuilder.build(
                    tocEntries = tocEntries,
                    spineHrefs = pages.map { it.substringAfterLast('/') }
                )
                val firstChapter = sections.firstOrNull { it.kind == ReaderSectionKind.CHAPTER }?.spineIndex ?: 0

                val seenImageNames = hashSetOf<String>()
                val candidates = mutableListOf<SelectedEntry>()
                var inspectedEntries = 0
                var examinedTags = 0
                var hasFrontMatterCandidate = false
                for (index in 0..minOf(firstChapter, pages.lastIndex)) {
                    if (isCancelled()) return@use null
                    if (inspectedEntries >= MAX_IMAGE_CANDIDATES || examinedTags >= MAX_IMAGE_TAGS) break
                    // Front matter always beats chapter 1; skip reading chapter 1 when front matter already qualified.
                    if (index == firstChapter && hasFrontMatterCandidate) break
                    val pageName = pages[index]
                    val pageUri = toVirtualUri(pageName) ?: continue
                    val pageEntry = zip.getEntry(pageName) ?: continue
                    val pageBytes = readEntryBounded(zip, pageEntry, MAX_TEXT_ENTRY_BYTES, isCancelled)
                        ?: continue
                    if (isCancelled()) return@use null
                    val pageDoc = Jsoup.parse(pageBytes.toString(Charsets.UTF_8))
                    val images = pageDoc.select("img[src]")
                    for (image in images) {
                        if (isCancelled()) return@use null
                        if (inspectedEntries >= MAX_IMAGE_CANDIDATES || examinedTags >= MAX_IMAGE_TAGS) break
                        examinedTags += 1
                        val src = image.attr("src").trim()
                        val imageName = resolveRelative(pageUri, src) ?: continue
                        if (!seenImageNames.add(imageName)) continue
                        val imageEntry = zip.getEntry(imageName) ?: continue
                        inspectedEntries += 1
                        if (imageEntry.size > MAX_IMAGE_BYTES.toLong()) continue
                        val dimensions = decodeBounds(zip, imageEntry, isCancelled) ?: continue
                        val (width, height) = dimensions
                        if (!accepts(width, height)) continue
                        val isFrontMatter = index < firstChapter
                        if (isFrontMatter) hasFrontMatterCandidate = true
                        candidates += SelectedEntry(
                            entryName = imageName,
                            frontMatter = isFrontMatter,
                            pixelArea = width.toLong() * height.toLong(),
                            order = candidates.size
                        )
                    }
                }
                if (candidates.isEmpty() || isCancelled()) return@use null

                candidates.sortWith(
                    compareByDescending<SelectedEntry> { it.frontMatter }
                        .thenByDescending { it.pixelArea }
                        .thenBy { it.order }
                )
                for (selected in candidates) {
                    if (isCancelled()) return@use null
                    val entry = zip.getEntry(selected.entryName) ?: continue
                    val bytes = readEntryBounded(zip, entry, MAX_IMAGE_BYTES, isCancelled)
                    if (bytes != null) return@use bytes
                }
                null
            }
        }.getOrNull()
    }

    /**
     * Downsamples to at most [maxPixelSize] px on the longest side, applies EXIF orientation,
     * flattens alpha onto white, and encodes JPEG (matching iOS `downsampledJPEG` +
     * `EPUBCoverExport.flattenedOntoWhiteIfNeeded`).
     */
    fun downsampledJPEG(raw: ByteArray?, maxPixelSize: Int = MAX_THUMBNAIL_PX): ByteArray? {
        if (raw == null || raw.isEmpty() || maxPixelSize <= 0) return null
        return runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
            val srcW = bounds.outWidth
            val srcH = bounds.outHeight
            if (srcW <= 0 || srcH <= 0) return@runCatching null

            var sampleSize = 1
            val maxSrc = maxOf(srcW, srcH)
            while (maxSrc / (sampleSize * 2) >= maxPixelSize) {
                sampleSize *= 2
            }
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size, decodeOpts) ?: return@runCatching null
            val oriented = applyExifOrientation(decoded, raw)
            if (oriented !== decoded) decoded.recycle()

            val scaled = scaleDownIfNeeded(oriented, maxPixelSize)
            if (scaled !== oriented) oriented.recycle()

            val flattened = flattenOntoWhiteIfNeeded(scaled)
            if (flattened !== scaled) scaled.recycle()

            try {
                val out = ByteArrayOutputStream()
                if (!flattened.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) {
                    return@runCatching null
                }
                out.toByteArray()
            } finally {
                flattened.recycle()
            }
        }.getOrNull()
    }

    private data class ManifestItem(
        val path: String,
        val mediaType: String,
        val properties: String
    )

    private fun rootfilePath(containerXml: String): String? {
        val doc = Jsoup.parse(containerXml, "", Parser.xmlParser())
        return doc.getAllElements()
            .firstOrNull { it.localTagName() == "rootfile" }
            ?.attr("full-path")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun parseTocEntries(
        zip: ZipFile,
        opfDoc: Document,
        manifestById: Map<String, ManifestItem>,
        spineIndexByKey: Map<String, Int>,
        isCancelled: () -> Boolean = { false }
    ): List<ReaderSectionBuilder.RawTOCEntry> {
        val results = mutableListOf<ReaderSectionBuilder.RawTOCEntry>()
        val seen = mutableSetOf<Int>()

        val navPath = manifestById.values.firstOrNull { item ->
            item.properties.split(Regex("\\s+")).any { it.equals("nav", ignoreCase = true) }
        }?.path
        if (navPath != null && !isCancelled()) {
            val navUri = toVirtualUri(navPath)
            val navEntry = zip.getEntry(navPath)
            val navBytes = navEntry?.let { readEntryBounded(zip, it, MAX_TEXT_ENTRY_BYTES, isCancelled) }
            if (navUri != null && navBytes != null) {
                val doc = Jsoup.parse(navBytes.toString(Charsets.UTF_8))
                val navs = doc.select("nav")
                val nav = navs.firstOrNull { navEl ->
                    navEl.attr("epub:type").split(Regex("\\s+")).any { it.equals("toc", ignoreCase = true) } ||
                        navEl.id() == "toc"
                } ?: navs.firstOrNull { navEl ->
                    navEl.attr("role").split(Regex("\\s+")).any { it.equals("doc-toc", ignoreCase = true) }
                } ?: navs.firstOrNull()
                nav?.select("a[href]")?.forEach { anchor ->
                    val rawHref = anchor.attr("href").trim()
                    val resolved = resolveRelative(navUri, rawHref)
                    val spineIndex = resolved?.let { spineIndexByKey[fileKey(it)] }
                        ?: spineIndexByKey[fileKey(rawHref)]
                        ?: return@forEach
                    if (seen.add(spineIndex)) {
                        val label = anchor.text().trim().ifEmpty { "Section ${spineIndex + 1}" }
                        results += ReaderSectionBuilder.RawTOCEntry(label, spineIndex)
                    }
                }
            }
        }
        if (results.isNotEmpty() || isCancelled()) return results

        val ncxId = opfDoc.getAllElements()
            .firstOrNull { it.localTagName() == "spine" }
            ?.attr("toc")
            ?.trim()
            .orEmpty()
        val ncxPath = manifestById[ncxId]?.path
            ?: manifestById.values.firstOrNull {
                it.mediaType.equals("application/x-dtbncx+xml", ignoreCase = true)
            }?.path
            ?: manifestById.values.firstOrNull {
                it.path.lowercase(Locale.ROOT).endsWith(".ncx")
            }?.path
            ?: return emptyList()

        val ncxUri = toVirtualUri(ncxPath) ?: return emptyList()
        val ncxEntry = zip.getEntry(ncxPath) ?: return emptyList()
        val ncxBytes = readEntryBounded(zip, ncxEntry, MAX_TEXT_ENTRY_BYTES, isCancelled) ?: return emptyList()
        val ncxDoc = Jsoup.parse(ncxBytes.toString(Charsets.UTF_8), "", Parser.xmlParser())
        ncxDoc.getAllElements()
            .filter { it.localTagName() == "navpoint" }
            .forEach { navPoint ->
                val src = navPoint.children()
                    .firstOrNull { it.localTagName() == "content" }
                    ?.attr("src")
                    ?.trim()
                    ?: navPoint.selectFirst("content")?.attr("src")?.trim()
                    ?: return@forEach
                val resolved = resolveRelative(ncxUri, src)
                val spineIndex = resolved?.let { spineIndexByKey[fileKey(it)] }
                    ?: spineIndexByKey[fileKey(src)]
                    ?: return@forEach
                if (seen.add(spineIndex)) {
                    val label = navPoint.children()
                        .firstOrNull { it.localTagName() == "navlabel" }
                        ?.text()
                        ?.trim()
                        .orEmpty()
                        .ifEmpty { "Section ${spineIndex + 1}" }
                    results += ReaderSectionBuilder.RawTOCEntry(label, spineIndex)
                }
            }
        return results
    }

    private fun decodeBounds(
        zip: ZipFile,
        entry: ZipEntry,
        isCancelled: () -> Boolean
    ): Pair<Int, Int>? {
        if (entry.size > MAX_IMAGE_BYTES.toLong() || isCancelled()) return null
        return runCatching {
            zip.getInputStream(entry).use { raw ->
                val bounded = BoundedCancellableInputStream(
                    delegate = raw,
                    maxBytes = minOf(MAX_IMAGE_BYTES, MAX_HEADER_BYTES),
                    isCancelled = isCancelled
                )
                val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeStream(bounded, null, opts)
                if (bounded.cancelled) return@runCatching null
                if (opts.outWidth > 0 && opts.outHeight > 0) opts.outWidth to opts.outHeight else null
            }
        }.getOrNull()
    }

    private fun applyExifOrientation(bitmap: Bitmap, rawBytes: ByteArray): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(rawBytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(270f)
            else -> return bitmap
        }
        return runCatching {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }.getOrDefault(bitmap)
    }

    private fun scaleDownIfNeeded(bitmap: Bitmap, maxPixelSize: Int): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= maxPixelSize) return bitmap
        val scale = maxPixelSize.toFloat() / longest.toFloat()
        val targetW = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val targetH = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, targetW, targetH, true)
    }

    private fun flattenOntoWhiteIfNeeded(bitmap: Bitmap): Bitmap {
        if (!bitmap.hasAlpha()) return bitmap
        val flattened = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(flattened)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(bitmap, 0f, 0f, null)
        return flattened
    }

    private fun readEntryBounded(
        zip: ZipFile,
        entry: ZipEntry,
        maxBytes: Int,
        isCancelled: () -> Boolean = { false }
    ): ByteArray? {
        val declared = entry.size
        if (declared > maxBytes.toLong() || isCancelled()) return null
        return runCatching {
            zip.getInputStream(entry).use { input ->
                if (declared in 1L..maxBytes.toLong()) {
                    val expected = declared.toInt()
                    val exact = ByteArray(expected)
                    var offset = 0
                    while (offset < expected) {
                        if (isCancelled()) return@runCatching null
                        val count = input.read(exact, offset, minOf(65_536, expected - offset))
                        if (count < 0) break
                        offset += count
                    }
                    if (offset == expected) {
                        if (isCancelled()) return@runCatching null
                        val extra = input.read()
                        if (extra < 0) return@runCatching exact
                        if (expected + 1 > maxBytes) return@runCatching null
                        val out = ByteArrayOutputStream(minOf(maxBytes, expected + 8_192))
                        out.write(exact, 0, offset)
                        out.write(extra)
                        return@runCatching readRemainingBounded(input, out, offset + 1, maxBytes, isCancelled)
                    }
                    return@runCatching exact.copyOf(offset)
                }
                val out = ByteArrayOutputStream(8_192)
                readRemainingBounded(input, out, 0, maxBytes, isCancelled)
            }
        }.getOrNull()
    }

    private fun readRemainingBounded(
        input: InputStream,
        out: ByteArrayOutputStream,
        initialTotal: Int,
        maxBytes: Int,
        isCancelled: () -> Boolean
    ): ByteArray? {
        val buffer = ByteArray(8_192)
        var total = initialTotal
        while (true) {
            if (isCancelled()) return null
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > maxBytes) return null
            out.write(buffer, 0, count)
        }
        return out.toByteArray()
    }

    /** Caps header-sniffing reads and aborts promptly if the scan's waiters leave composition. */
    private class BoundedCancellableInputStream(
        delegate: InputStream,
        maxBytes: Int,
        private val isCancelled: () -> Boolean
    ) : FilterInputStream(delegate) {
        private var remaining: Int = maxBytes
        var cancelled: Boolean = false
            private set

        override fun markSupported(): Boolean = false

        override fun read(): Int {
            if (isCancelled()) {
                cancelled = true
                return -1
            }
            if (remaining <= 0) return -1
            val value = `in`.read()
            if (value >= 0) remaining -= 1
            return value
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (len == 0) return 0
            if (isCancelled()) {
                cancelled = true
                return -1
            }
            if (remaining <= 0) return -1
            val toRead = minOf(len, remaining)
            val count = `in`.read(b, off, toRead)
            if (count > 0) remaining -= count
            return count
        }

        override fun skip(n: Long): Long {
            if (n <= 0L) return 0L
            if (isCancelled()) {
                cancelled = true
                return 0L
            }
            if (remaining <= 0) return 0L
            val skipped = `in`.skip(minOf(n, remaining.toLong()))
            if (skipped > 0L) remaining -= skipped.toInt()
            return skipped
        }
    }

    private fun toVirtualUri(entryName: String): URI? {
        if (entryName.isEmpty() || '\\' in entryName || '\u0000' in entryName) return null
        return runCatching {
            URI(null, null, "$VIRTUAL_ROOT${entryName.trimStart('/')}", null).normalize()
        }.getOrNull()
    }

    private fun entryNameFrom(uri: URI): String? {
        if (uri.scheme != null || uri.authority != null) return null
        val path = uri.path ?: return null
        if (!path.startsWith(VIRTUAL_ROOT)) return null
        val relative = path.removePrefix(VIRTUAL_ROOT)
        if (relative.isEmpty() || '\\' in relative || '\u0000' in relative) return null
        return relative
    }

    private fun resolveRelative(baseUri: URI, rawRef: String): String? {
        val trimmed = rawRef.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("//") || '\\' in trimmed || '\u0000' in trimmed) {
            return null
        }
        val clean = trimmed.substringBefore('#').substringBefore('?')
        if (clean.isEmpty()) return null
        val resolved = runCatching { baseUri.resolve(clean).normalize() }.getOrNull()
            ?: runCatching { baseUri.resolve(clean.replace(" ", "%20")).normalize() }.getOrNull()
            ?: return null
        return entryNameFrom(resolved)
    }

    private fun fileKey(path: String): String {
        val base = path.substringBefore('#').substringBefore('?').substringAfterLast('/')
        // Swift `removingPercentEncoding`: decodes %xx, leaves '+' alone, returns the input unchanged if malformed.
        return percentDecode(base).lowercase(Locale.ROOT)
    }

    internal fun percentDecode(value: String): String {
        if ('%' !in value) return value
        val out = StringBuilder(value.length)
        val pending = ByteArrayOutputStream()
        val decoder = StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)

        fun flushPending(): Boolean {
            if (pending.size() == 0) return true
            val decoded = runCatching {
                decoder.reset().decode(ByteBuffer.wrap(pending.toByteArray())).toString()
            }.getOrNull() ?: return false
            out.append(decoded)
            pending.reset()
            return true
        }

        var index = 0
        while (index < value.length) {
            val char = value[index]
            if (char == '%') {
                if (index + 2 >= value.length) return value
                val byte = hexByte(value[index + 1], value[index + 2]) ?: return value
                pending.write(byte)
                index += 3
                continue
            }
            if (!flushPending()) return value
            out.append(char)
            index += 1
        }
        return if (flushPending()) out.toString() else value
    }

    private fun hexByte(hi: Char, lo: Char): Int? {
        val high = Character.digit(hi, 16)
        val low = Character.digit(lo, 16)
        if (high < 0 || low < 0) return null
        return (high shl 4) or low
    }

    private fun Element.localTagName(): String =
        tagName().substringAfter(':').lowercase(Locale.ROOT)
}
