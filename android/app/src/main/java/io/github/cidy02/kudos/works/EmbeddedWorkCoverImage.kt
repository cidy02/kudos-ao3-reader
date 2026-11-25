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
import java.net.URI
import java.net.URLDecoder
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
    private const val MAX_TEXT_ENTRY_BYTES: Int = 4_000_000
    private const val JPEG_QUALITY: Int = 86
    private const val VIRTUAL_ROOT: String = "/KudosGeneratedCoverArt/"

    class Candidate(
        val data: ByteArray,
        val frontMatter: Boolean,
        val pixelArea: Long
    )

    /** Front matter always beats chapter images; ties break by larger pixel area. */
    fun preferred(current: Candidate?, candidate: Candidate): Candidate {
        if (current == null) return candidate
        if (candidate.frontMatter != current.frontMatter) {
            return if (candidate.frontMatter) candidate else current
        }
        return if (candidate.pixelArea > current.pixelArea) candidate else current
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
     * spine XHTML documents `0..firstChapter`, and local candidate images) without unpacking
     * the archive.
     */
    fun data(epubFile: File, isCancelled: () -> Boolean = { false }): ByteArray? {
        if (!epubFile.isFile || isCancelled()) return null
        return runCatching {
            ZipFile(epubFile).use { zip ->
                val containerEntry = zip.getEntry("META-INF/container.xml") ?: return@use null
                val containerBytes = readEntryBounded(zip, containerEntry, MAX_TEXT_ENTRY_BYTES) ?: return@use null
                val opfRawPath = rootfilePath(containerBytes.toString(Charsets.UTF_8)) ?: return@use null

                val rootUri = URI(null, null, VIRTUAL_ROOT, null)
                val opfName = toVirtualUri(opfRawPath)?.let(::entryNameFrom)
                    ?.takeIf { zip.getEntry(it) != null }
                    ?: resolveRelative(rootUri, opfRawPath)?.takeIf { zip.getEntry(it) != null }
                    ?: return@use null
                val opfUri = toVirtualUri(opfName) ?: return@use null
                val opfEntry = zip.getEntry(opfName) ?: return@use null
                val opfBytes = readEntryBounded(zip, opfEntry, MAX_TEXT_ENTRY_BYTES) ?: return@use null
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
                if (pages.isEmpty()) return@use null

                val spineIndexByKey = linkedMapOf<String, Int>()
                pages.forEachIndexed { index, path ->
                    spineIndexByKey.putIfAbsent(fileKey(path), index)
                }

                val tocEntries = parseTocEntries(
                    zip = zip,
                    opfDoc = opfDoc,
                    manifestById = manifestById,
                    spineIndexByKey = spineIndexByKey
                )
                val sections = ReaderSectionBuilder.build(
                    tocEntries = tocEntries,
                    spineHrefs = pages.map { it.substringAfterLast('/') }
                )
                val firstChapter = sections.firstOrNull { it.kind == ReaderSectionKind.CHAPTER }?.spineIndex ?: 0

                var best: Candidate? = null
                for (index in 0..minOf(firstChapter, pages.lastIndex)) {
                    if (isCancelled()) return@use null
                    val pageName = pages[index]
                    val pageUri = toVirtualUri(pageName) ?: continue
                    val pageEntry = zip.getEntry(pageName) ?: continue
                    val pageBytes = readEntryBounded(zip, pageEntry, MAX_TEXT_ENTRY_BYTES) ?: continue
                    val pageDoc = Jsoup.parse(pageBytes.toString(Charsets.UTF_8))
                    val images = pageDoc.select("img[src]")
                    for (image in images) {
                        if (isCancelled()) return@use null
                        val src = image.attr("src").trim()
                        val imageName = resolveRelative(pageUri, src) ?: continue
                        val imageEntry = zip.getEntry(imageName) ?: continue
                        val imageBytes = readEntryBounded(zip, imageEntry, MAX_IMAGE_BYTES) ?: continue
                        val dimensions = decodeBounds(imageBytes) ?: continue
                        val (width, height) = dimensions
                        if (!accepts(width, height)) continue
                        val candidate = Candidate(
                            data = imageBytes,
                            frontMatter = index < firstChapter,
                            pixelArea = width.toLong() * height.toLong()
                        )
                        best = preferred(best, candidate)
                    }
                }
                best?.data
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
        spineIndexByKey: Map<String, Int>
    ): List<ReaderSectionBuilder.RawTOCEntry> {
        val results = mutableListOf<ReaderSectionBuilder.RawTOCEntry>()
        val seen = mutableSetOf<Int>()

        val navPath = manifestById.values.firstOrNull { item ->
            item.properties.split(Regex("\\s+")).any { it.equals("nav", ignoreCase = true) }
        }?.path
        if (navPath != null) {
            val navUri = toVirtualUri(navPath)
            val navEntry = zip.getEntry(navPath)
            val navBytes = navEntry?.let { readEntryBounded(zip, it, MAX_TEXT_ENTRY_BYTES) }
            if (navUri != null && navBytes != null) {
                val doc = Jsoup.parse(navBytes.toString(Charsets.UTF_8))
                val nav = doc.select("nav[epub\\:type=toc], nav[role=doc-toc], nav").firstOrNull()
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
        if (results.isNotEmpty()) return results

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
        val ncxBytes = readEntryBounded(zip, ncxEntry, MAX_TEXT_ENTRY_BYTES) ?: return emptyList()
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

    private fun decodeBounds(bytes: ByteArray): Pair<Int, Int>? {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        return if (opts.outWidth > 0 && opts.outHeight > 0) opts.outWidth to opts.outHeight else null
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

    private fun readEntryBounded(zip: ZipFile, entry: ZipEntry, maxBytes: Int): ByteArray? {
        val declared = entry.size
        if (declared > maxBytes.toLong()) return null
        return runCatching {
            zip.getInputStream(entry).use { input ->
                val initial = if (declared in 1..65_536) declared.toInt() else 8_192
                val out = ByteArrayOutputStream(initial)
                val buffer = ByteArray(8_192)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > maxBytes) return@runCatching null
                    out.write(buffer, 0, count)
                }
                out.toByteArray()
            }
        }.getOrNull()
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
        val decoded = runCatching {
            URLDecoder.decode(base.replace("+", "%2B"), "UTF-8")
        }.getOrDefault(base)
        return decoded.lowercase(Locale.ROOT)
    }

    private fun Element.localTagName(): String =
        tagName().substringAfter(':').lowercase(Locale.ROOT)
}
