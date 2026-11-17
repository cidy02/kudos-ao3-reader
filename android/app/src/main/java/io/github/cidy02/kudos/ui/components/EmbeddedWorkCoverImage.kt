package io.github.cidy02.kudos.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderSectionKind
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.jsoup.Jsoup
import org.jsoup.parser.Parser

/** Codec seam so pure JVM tests can supply an ImageIO implementation without Android BitmapFactory. */
interface EmbeddedImageCodec {
    fun dimensions(bytes: ByteArray): Pair<Int, Int>?
    fun downsampledJpeg(bytes: ByteArray, maxPixelSize: Int = 600): ByteArray?
}

object AndroidEmbeddedImageCodec : EmbeddedImageCodec {
    @Volatile
    internal var compressBitmap: (Bitmap, Bitmap.CompressFormat, Int, ByteArrayOutputStream) -> Boolean =
        { bitmap, format, quality, out -> bitmap.compress(format, quality, out) }

    override fun dimensions(bytes: ByteArray): Pair<Int, Int>? {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null
        return opts.outWidth to opts.outHeight
    }

    override fun downsampledJpeg(bytes: ByteArray, maxPixelSize: Int): ByteArray? {
        val dims = dimensions(bytes) ?: return null
        val (srcW, srcH) = dims
        var sampleSize = 1
        while (max(srcW / sampleSize, srcH / sampleSize) > maxPixelSize * 2) {
            sampleSize *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return null
        val oriented = applyExifOrientation(decoded, bytes)
        val longSide = max(oriented.width, oriented.height)
        val scaled = if (longSide > maxPixelSize) {
            val factor = maxPixelSize.toDouble() / longSide.toDouble()
            val targetW = max(1, (oriented.width * factor).roundToInt())
            val targetH = max(1, (oriented.height * factor).roundToInt())
            Bitmap.createScaledBitmap(oriented, targetW, targetH, true).also {
                if (it !== oriented) oriented.recycle()
            }
        } else {
            oriented
        }
        return try {
            val out = ByteArrayOutputStream()
            if (compressBitmap(scaled, Bitmap.CompressFormat.JPEG, EmbeddedWorkCoverImage.JPEG_QUALITY, out)) {
                out.toByteArray()
            } else {
                null
            }
        } finally {
            scaled.recycle()
        }
    }

    private fun applyExifOrientation(bitmap: Bitmap, bytes: ByteArray): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also {
            if (it !== bitmap) bitmap.recycle()
        }
    }
}

/**
 * Finds author-supplied art already inside a downloaded EPUB. Never requests remote images.
 * Port of iOS `EmbeddedWorkCoverImage.swift`.
 */
object EmbeddedWorkCoverImage {
    private const val VIRTUAL_ROOT = "/KudosGeneratedCoverArt/"
    private const val MAX_IMAGE_BYTES = 20_000_000
    private const val MAX_XML_BYTES = 8_000_000

    /** iOS ImageIO writes the downsampled cover at its highest JPEG quality. */
    internal const val JPEG_QUALITY = 100

    /** iOS skips an image whose uncompressed size is missing. `ZipEntry.size` is -1 then. */
    internal fun imageEntrySkipped(size: Long): Boolean = size < 0L || size > MAX_IMAGE_BYTES

    data class Candidate(
        val data: ByteArray,
        val frontMatter: Boolean,
        val pixelArea: Int
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Candidate) return false
            return frontMatter == other.frontMatter &&
                pixelArea == other.pixelArea &&
                data.contentEquals(other.data)
        }

        override fun hashCode(): Int {
            var result = data.contentHashCode()
            result = 31 * result + frontMatter.hashCode()
            result = 31 * result + pixelArea
            return result
        }
    }

    fun preferred(current: Candidate?, candidate: Candidate): Candidate {
        if (current == null) return candidate
        if (candidate.frontMatter != current.frontMatter) {
            return if (candidate.frontMatter) candidate else current
        }
        return if (candidate.pixelArea > current.pixelArea) candidate else current
    }

    fun accepts(width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0 || width > 20_000 || height > 20_000) return false
        val ratio = width.toDouble() / height.toDouble()
        return min(width, height) >= 320 && ratio in 0.40..1.85
    }

    fun data(
        epubFile: File,
        imageCodec: EmbeddedImageCodec = AndroidEmbeddedImageCodec
    ): ByteArray? = data(epubFile = epubFile, imageCodec = imageCodec, entrySize = { it.size })

    internal fun data(
        epubFile: File,
        imageCodec: EmbeddedImageCodec = AndroidEmbeddedImageCodec,
        entrySize: (ZipEntry) -> Long
    ): ByteArray? {
        if (!epubFile.isFile) return null
        return runCatching {
            ZipFile(epubFile).use { zip ->
                val containerBytes = readEntry(zip, "META-INF/container.xml", MAX_XML_BYTES) ?: return@use null
                val opfPath = rootfilePath(containerBytes) ?: return@use null
                val rootUri = URI("file://$VIRTUAL_ROOT")
                val opfUri = resolveRelative(rootUri, opfPath) ?: return@use null
                val opfName = entryName(opfUri) ?: return@use null
                val opfBytes = readEntry(zip, opfName, MAX_XML_BYTES) ?: return@use null
                val parsed = parseOpf(opfBytes) ?: return@use null
                val opfDir = opfDirUri(opfUri)
                val pages = parsed.spine.mapNotNull { id ->
                    val href = parsed.manifest[id] ?: return@mapNotNull null
                    val url = resolveRelative(opfDir, href) ?: return@mapNotNull null
                    if (entryName(url) != null) url else null
                }
                if (pages.isEmpty()) return@use null

                val tocEntries = tableOfContents(
                    parsed = parsed,
                    opfDir = opfDir,
                    spineCount = pages.size,
                    readData = { uri -> entryName(uri)?.let { readEntry(zip, it, MAX_XML_BYTES) } }
                )
                val sections = ReaderSectionBuilder.build(
                    tocEntries = tocEntries,
                    spineHrefs = pages.map { lastPathSegment(it) }
                )
                val firstChapter = sections.firstOrNull { it.kind == ReaderSectionKind.CHAPTER }?.spineIndex ?: 0

                var best: Candidate? = null
                for (index in 0..firstChapter) {
                    if (index !in pages.indices) break
                    val pageUri = pages[index]
                    val pageName = entryName(pageUri) ?: continue
                    val pageBytes = readEntry(zip, pageName, MAX_XML_BYTES) ?: continue
                    val xhtml = pageBytes.toString(StandardCharsets.UTF_8)
                    val doc = runCatching { Jsoup.parse(xhtml) }.getOrNull() ?: continue
                    for (img in doc.select("img[src]")) {
                        val src = img.attr("src")
                        if (src.isEmpty() || src.startsWith("//")) continue
                        val imgUri = resolveRelative(pageUri, src) ?: continue
                        val name = entryName(imgUri) ?: continue
                        val entry = zip.getEntry(name) ?: continue
                        if (imageEntrySkipped(entrySize(entry))) continue
                        val data = readEntry(zip, name, MAX_IMAGE_BYTES) ?: continue
                        val (width, height) = imageCodec.dimensions(data) ?: continue
                        if (!accepts(width, height)) continue
                        val candidate = Candidate(
                            data = data,
                            frontMatter = index < firstChapter,
                            pixelArea = width * height
                        )
                        best = preferred(best, candidate)
                    }
                }
                best?.data
            }
        }.getOrNull()
    }

    fun downsampledJPEG(
        data: ByteArray?,
        imageCodec: EmbeddedImageCodec = AndroidEmbeddedImageCodec
    ): ByteArray? = data?.let { imageCodec.downsampledJpeg(it, maxPixelSize = 600) }

    private data class OpfData(
        val manifest: Map<String, String>,
        val manifestMedia: Map<String, String>,
        val manifestProps: Map<String, String>,
        val spine: List<String>,
        val tocId: String?
    )

    private fun rootfilePath(containerBytes: ByteArray): String? {
        val doc = runCatching {
            Jsoup.parse(containerBytes.toString(StandardCharsets.UTF_8), "", Parser.xmlParser())
        }.getOrNull() ?: return null
        return doc.getElementsByTag("rootfile")
            .firstOrNull { it.hasAttr("full-path") }
            ?.attr("full-path")
            ?.takeIf { it.isNotBlank() }
    }

    private fun parseOpf(opfBytes: ByteArray): OpfData? {
        val doc = runCatching {
            Jsoup.parse(opfBytes.toString(StandardCharsets.UTF_8), "", Parser.xmlParser())
        }.getOrNull() ?: return null
        val manifest = LinkedHashMap<String, String>()
        val manifestMedia = LinkedHashMap<String, String>()
        val manifestProps = LinkedHashMap<String, String>()
        for (item in doc.getElementsByTag("item")) {
            val id = item.attr("id")
            val href = item.attr("href")
            if (id.isNotBlank() && href.isNotBlank()) {
                manifest[id] = href
                item.attr("media-type").takeIf { it.isNotBlank() }?.let { manifestMedia[id] = it }
                item.attr("properties").takeIf { it.isNotBlank() }?.let { manifestProps[id] = it }
            }
        }
        val spineEl = doc.getElementsByTag("spine").firstOrNull()
        val tocId = spineEl?.attr("toc")?.takeIf { it.isNotBlank() }
        val spine = doc.getElementsByTag("itemref").mapNotNull { el ->
            el.attr("idref").takeIf { it.isNotBlank() && manifest.containsKey(it) }
        }
        if (spine.isEmpty()) return null
        return OpfData(manifest, manifestMedia, manifestProps, spine, tocId)
    }

    private fun tableOfContents(
        parsed: OpfData,
        opfDir: URI,
        spineCount: Int,
        readData: (URI) -> ByteArray?
    ): List<ReaderSectionBuilder.RawTOCEntry> {
        val keyToIndex = HashMap<String, Int>()
        parsed.spine.forEachIndexed { index, idref ->
            val href = parsed.manifest[idref].orEmpty()
            val key = fileKey(href)
            if (!keyToIndex.containsKey(key)) keyToIndex[key] = index
        }

        var tocHref: String? = null
        var isNav = false
        val navId = parsed.manifestProps.entries.firstOrNull { (_, props) ->
            props.split(' ', '\t', '\n', '\r').any { it == "nav" }
        }?.key
        if (navId != null) {
            tocHref = parsed.manifest[navId]
            isNav = true
        } else {
            val ncxId = parsed.tocId
                ?: parsed.manifestMedia.entries.firstOrNull { it.value == "application/x-dtbncx+xml" }?.key
            if (ncxId != null) tocHref = parsed.manifest[ncxId]
        }

        var pairs: List<Pair<String, String>> = emptyList()
        if (tocHref != null) {
            val tocUri = resolveRelative(opfDir, tocHref)
            val data = tocUri?.let(readData)
            if (data != null) {
                pairs = if (isNav) parseNav(data) else parseNcx(data)
            }
        }
        if (isNav && pairs.isEmpty()) {
            val ncxId = parsed.tocId
                ?: parsed.manifestMedia.entries.firstOrNull { it.value == "application/x-dtbncx+xml" }?.key
            val ncxHref = ncxId?.let { parsed.manifest[it] }
            val data = ncxHref?.let { resolveRelative(opfDir, it) }?.let(readData)
            if (data != null) {
                pairs = parseNcx(data)
            }
        }

        val entries = ArrayList<ReaderSectionBuilder.RawTOCEntry>()
        val seen = HashSet<Int>()
        for ((rawTitle, src) in pairs) {
            val index = keyToIndex[fileKey(src)] ?: continue
            if (!seen.add(index)) continue
            val title = rawTitle.trim().ifEmpty { "Section ${index + 1}" }
            entries += ReaderSectionBuilder.RawTOCEntry(title = title, spineIndex = index)
        }
        if (entries.isEmpty()) {
            for (i in 0 until spineCount) {
                entries += ReaderSectionBuilder.RawTOCEntry(title = "Section ${i + 1}", spineIndex = i)
            }
        }
        return entries
    }

    private fun parseNav(data: ByteArray): List<Pair<String, String>> {
        val doc = runCatching {
            Jsoup.parse(data.toString(StandardCharsets.UTF_8))
        }.getOrNull() ?: return emptyList()
        val nav = doc.select("nav").firstOrNull { el ->
            val typedToc = el.attributes().any { attr ->
                attr.key.endsWith("type") && attr.value.contains("toc")
            }
            typedToc || el.id() == "toc"
        } ?: doc.selectFirst("nav") ?: return emptyList()
        return nav.select("a[href]").mapNotNull { link ->
            val href = link.attr("href")
            if (href.isBlank()) null else link.text().trim() to href
        }
    }

    private fun parseNcx(data: ByteArray): List<Pair<String, String>> {
        val doc = runCatching {
            Jsoup.parse(data.toString(StandardCharsets.UTF_8), "", Parser.xmlParser())
        }.getOrNull() ?: return emptyList()
        return doc.getElementsByTag("navPoint").mapNotNull { point ->
            val title = point.getElementsByTag("navLabel").firstOrNull()
                ?.getElementsByTag("text")?.firstOrNull()?.text() ?: ""
            val src = point.getElementsByTag("content").firstOrNull()?.attr("src").orEmpty()
            if (src.isBlank()) null else Parser.unescapeEntities(title, false).trim() to src
        }
    }

    private fun fileKey(href: String): String {
        val noFragment = href.substringBefore('#')
        val last = noFragment.substringAfterLast('/')
        // Swift `removingPercentEncoding` decodes %xx and leaves '+' alone.
        // URLDecoder would turn "ch+1.xhtml" into "ch 1.xhtml".
        return percentDecode(last).lowercase(Locale.ROOT)
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

    private fun resolveRelative(base: URI, rawRef: String): URI? {
        val ref = rawRef.trim().replace(" ", "%20")
        return runCatching {
            val resolved = base.resolve(ref).normalize()
            if (resolved.scheme == "file") resolved else null
        }.getOrNull()
    }

    private fun opfDirUri(opfUri: URI): URI {
        val raw = opfUri.toString()
        val dir = raw.substringBeforeLast('/', raw) + "/"
        return URI(dir)
    }

    private fun entryName(uri: URI): String? {
        if (uri.scheme != "file") return null
        val path = uri.path ?: return null
        if (!path.startsWith(VIRTUAL_ROOT)) return null
        return path.removePrefix(VIRTUAL_ROOT).takeIf { it.isNotEmpty() }
    }

    private fun lastPathSegment(uri: URI): String =
        (uri.path ?: "").substringAfterLast('/')

    private fun readEntry(zip: ZipFile, name: String, maxBytes: Int): ByteArray? {
        val entry = zip.getEntry(name) ?: return null
        if (entry.isDirectory) return null
        if (entry.size > maxBytes) return null
        return zip.getInputStream(entry).use { it.readBounded(maxBytes) }
    }

    private fun InputStream.readBounded(maxBytes: Int): ByteArray? {
        val buffer = ByteArray(8192)
        val out = ByteArrayOutputStream()
        var total = 0
        while (true) {
            val read = read(buffer)
            if (read < 0) break
            total += read
            if (total > maxBytes) return null
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }
}
