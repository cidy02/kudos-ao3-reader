package io.github.cidy02.kudos.ui.components

import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorIdentities
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import java.net.URI
import java.text.BreakIterator
import java.util.Locale
import java.util.UUID
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * The choices that identify a cover. No process-random hashing or UI state enters this value.
 * Exact port of iOS `GeneratedCoverRecipe.swift` (with commit `48aac1f0a` fandom dedupe).
 */
data class GeneratedCoverRecipe(
    val hues: List<Int>,
    val lightness: Double,
    val ground: Ground,
    val motif: String,
    val tier: Int,
    val closedRing: Boolean = true,
    val hasRing: Boolean = true,
    val placement: Int,
    val titleStyle: Int,
    val rotation: Double,
    val scale: Double,
    val lineWidth: Double,
    val opacity: Double,
    val shapeSeed: UInt,
    val title: String,
    val subtitle: String,
    val author: String,
    val fandom: String,
    val part: Int,
    val groundChroma: Double = 0.085
) {
    enum class Ground { GRADIENT, SPLIT, BAND, SOLID, CROSSOVER }

    /** Seeded Mulberry32 PRNG matching iOS `GeneratedCoverRecipe.Random` bit-for-bit. */
    class Random(private var state: UInt) {
        fun next(): Double {
            state += 0x6D2B79F5u
            var value = state
            value = (value xor (value shr 15)) * (value or 1u)
            value = value xor (value + ((value xor (value shr 7)) * (value or 61u)))
            return (value xor (value shr 14)).toDouble() / 4_294_967_296.0
        }

        fun between(low: Double, high: Double): Double = low + next() * (high - low)

        fun integer(low: Int, high: Int): Int = low + (next() * (high - low + 1).toDouble()).toInt()
    }

    companion object {
        private val palette = intArrayOf(20, 55, 85, 125, 150, 180, 205, 230, 260, 290, 320, 350)
        private val parents = mapOf(
            "Persuasion" to "Jane Austen",
            "Pride and Prejudice" to "Jane Austen",
            "Northanger Abbey" to "Jane Austen",
            "Jane Eyre" to "The Brontës"
        )
        private val sourceHues = mapOf(
            "Jane Austen" to 150,
            "The Brontës" to 300,
            "Sherlock Holmes" to 55,
            "Original Work" to 220
        )
        private val kinds = listOf(
            "rings", "orbit", "contours", "sigil", "guilloche", "sprig",
            "waves", "halftone", "truchet", "rosette", "sunburst",
            "constellation", "chevrons", "moire", "squares", "petals"
        )
        private val families = mapOf(
            "soft" to listOf("petals", "sprig", "waves", "rosette"),
            "angular" to listOf("chevrons", "squares", "sunburst", "sigil"),
            "orderly" to listOf("truchet", "contours", "halftone", "moire"),
            "celestial" to listOf("constellation", "orbit", "rings", "guilloche")
        )
        private val tones = mapOf(
            "Fluff" to "soft", "Domestic Fluff" to "soft", "Romance" to "soft",
            "Humor" to "soft", "Slice of Life" to "soft",
            "Angst" to "angular", "Drama" to "angular", "Horror" to "angular", "Thriller" to "angular",
            "Case Fic" to "orderly", "Mystery" to "orderly", "Politics" to "orderly", "Character Study" to "orderly",
            "Fantasy" to "celestial", "Magic" to "celestial", "Science Fiction" to "celestial"
        )
        private val constrainedRotationMotifs = setOf("sprig", "waves", "chevrons", "truchet", "halftone")
        private val leadingNumberRegex = Regex("^\\d+\\.\\s*")
        private val subtitleRegex = Regex("^(.*\\S)\\s+(\\(.*\\)|\\[.*\\])$")

        // Approximate posting dates of well-known works and round-number IDs, supplied
        // by the orchestrator from memory on 2026-11-14 while AO3 was down; not verified
        // against AO3. Fixed and monotone; matches iOS `GeneratedCoverRecipe.idYears`.
        private val idYears: List<Pair<Long, Double>> = listOf(
            0L to 2010.0,
            540_000L to 2012.8,
            1_000_000L to 2013.8,
            5_000_000L to 2015.8,
            8_340_000L to 2016.8,
            10_060_000L to 2017.2,
            14_450_000L to 2018.3,
            20_000_000L to 2019.6,
            26_600_000L to 2020.7,
            34_500_000L to 2021.8,
            40_000_000L to 2022.5,
            50_000_000L to 2023.7,
            60_000_000L to 2024.8,
            72_000_000L to 2026.0
        )

        /** FNV-1a 32-bit over UTF-8 bytes, matching iOS bit-for-bit. Never use Kotlin's `hashCode`. */
        fun hash(text: String): UInt {
            var state = 2_166_136_261u
            for (byte in text.toByteArray(Charsets.UTF_8)) {
                state = (state xor (byte.toInt() and 0xFF).toUInt()) * 16_777_619u
            }
            return state
        }

        private fun clean(fandom: String): String =
            FandomDisplayName.bareTitle(fandom).trim { it.isWhitespace() }

        private fun hue(fandom: String): Int {
            val source = parents[fandom] ?: fandom
            val base = sourceHues[source]
                ?: palette[(hash("source:$source") % palette.size.toUInt()).toInt()]
            return if (source == fandom) base else base + ((hash("fandom:$fandom") % 5u).toInt() - 2) * 9
        }

        fun year(id: Long?): Double {
            if (id == null) return 2018.0
            if (id <= idYears[0].first) return idYears[0].second
            for (index in 1 until idYears.size) {
                val upper = idYears[index]
                if (id < upper.first) {
                    val lower = idYears[index - 1]
                    return lower.second +
                        (id - lower.first).toDouble() / (upper.first - lower.first).toDouble() *
                        (upper.second - lower.second)
                }
            }
            return 2026.0
        }

        fun create(
            id: Long?,
            title: String,
            author: String,
            fandoms: List<String>,
            tags: List<String> = emptyList(),
            words: Int? = null,
            complete: Boolean = true,
            seriesID: Long? = null,
            part: Int = 0,
            salt: Int = 0,
            postedYear: Int? = null,
            firstAuthor: String? = null
        ): GeneratedCoverRecipe {
            // Two tags that name one fandom ("Doctor Who (2005)" and "Doctor Who") are one fandom on
            // a cover: no repeated label, no crossover split between identical colours (commit 48aac1f0a).
            val seen = HashSet<String>()
            val names = fandoms.map(::clean).filter { it.isNotEmpty() && seen.add(it.lowercase(Locale.ROOT)) }
            val mainTitle = title.replaceFirst(leadingNumberRegex, "")
            val (parsedTitle, parsedSubtitle) = splitTitle(mainTitle)
            val fandomLabel = names.joinToString(" × ")
            val fallback = palette[(hash("title:$mainTitle") % palette.size.toUInt()).toInt()]
            val hues = if (names.isEmpty()) {
                listOf(fallback)
            } else {
                names.mapIndexed { index, name ->
                    hue(name) + if (index == 0 && part > 0) (part - 1) * 18 else 0
                }
            }
            val resolvedYear = postedYear?.toDouble() ?: year(id)
            val lightness = round2(0.32 + min(max((resolvedYear - 2010.0) / 16.0, 0.0), 1.0) * 0.14)
            val resolvedFirstAuthor = firstAuthor ?: author.split(", ", limit = 2).firstOrNull() ?: author
            val authorHash = hash("author:$resolvedFirstAuthor")
            val selectedFamilies = tags.mapNotNullTo(LinkedHashSet()) { tones[it] }
            val workKey = (id ?: hash("work:$mainTitle|$author").toLong()).toString()
            val seriesKey = seriesID?.toString()
            val key = seriesKey ?: (workKey + if (salt == 0) "" else ":$salt")
            val motif = when {
                seriesKey != null -> kinds[(hash("series-kind:$seriesKey") % kinds.size.toUInt()).toInt()]
                selectedFamilies.size == 1 -> families.getValue(selectedFamilies.first())[(authorHash % 4u).toInt()]
                else -> kinds[((authorHash + max(0, salt).toUInt()) % kinds.size.toUInt()).toInt()]
            }
            val titleStyle = ((authorHash shr 5) % 3u).toInt()
            val placement = when {
                parsedSubtitle.isNotEmpty() -> 2
                graphemeCount(parsedTitle) <= 16 -> 1
                else -> 0
            }
            val resolvedWords = words ?: 30_000
            val tier = when {
                resolvedWords < 10_000 -> 0
                resolvedWords < 40_000 -> 1
                resolvedWords < 100_000 -> 2
                else -> 3
            }
            val shapeSeed = hash((if (seriesKey == null) "shape:" else "series-shape:") + key)
            val random = Random(seed = hash((if (seriesKey == null) "fine:" else "series-fine:") + key))
            val treatment = Ground.entries[random.integer(0, 3)]
            val ground = if (names.size > 1) Ground.CROSSOVER else treatment
            val rotation = round2(
                if (motif in constrainedRotationMotifs) {
                    random.between(-12.0, 12.0)
                } else {
                    random.between(0.0, 360.0)
                }
            )
            val scale = round2(random.between(0.85, 1.2))
            val lineWidth = round2(random.between(1.0, 1.5))
            val opacity = round2(random.between(0.4, 0.55))
            return GeneratedCoverRecipe(
                hues = hues,
                lightness = lightness,
                ground = ground,
                motif = motif,
                tier = tier,
                closedRing = complete,
                hasRing = true,
                placement = placement,
                titleStyle = titleStyle,
                rotation = rotation,
                scale = scale,
                lineWidth = lineWidth,
                opacity = opacity,
                shapeSeed = shapeSeed,
                title = parsedTitle,
                subtitle = parsedSubtitle,
                author = author,
                fandom = fandomLabel,
                part = part,
                groundChroma = 0.085
            )
        }

        fun forCollection(
            name: String,
            identity: String? = null,
            hue: Int,
            graphite: Boolean = false
        ): GeneratedCoverRecipe {
            val key = identity ?: name
            return create(
                id = hash("collection:$key").toLong(),
                title = name,
                author = "collection:$key",
                fandoms = emptyList(),
                complete = true
            ).copy(
                hues = listOf(hue),
                lightness = 0.4,
                ground = Ground.GRADIENT,
                closedRing = false,
                hasRing = false,
                groundChroma = if (graphite) 0.012 else 0.085,
                placement = 0
            )
        }

        fun collectionHue(hex: String?, fallback: Int): Int =
            collectionSwatch(hex, fallback).first

        fun collectionHue(identity: UUID): Int =
            collectionHueForIdentity(identity.toString().uppercase(Locale.ROOT))

        fun collectionHueForIdentity(identity: String): Int {
            val canonical = runCatching {
                UUID.fromString(identity).toString().uppercase(Locale.ROOT)
            }.getOrDefault(identity)
            return palette[(hash("collection:$canonical") % palette.size.toUInt()).toInt()]
        }

        fun collectionSwatch(hex: String?, fallback: Int): Pair<Int, Double> {
            val value = if (hex != null && hex.length == 7 && hex.startsWith("#")) {
                hex.drop(1).toLongOrNull(16)
            } else {
                null
            }
            if (value == null) {
                val normalized = (fallback % 360 + 360) % 360
                val hue = palette.minByOrNull { candidate ->
                    val diff = abs(candidate - normalized)
                    min(diff, 360 - diff)
                } ?: palette[0]
                return hue to 0.085
            }
            val channels = intArrayOf(16, 8, 0).map { shift ->
                val v = ((value shr shift) and 255L).toDouble() / 255.0
                if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
            }
            val l = cbrt(0.4122214708 * channels[0] + 0.5363325363 * channels[1] + 0.0514459929 * channels[2])
            val m = cbrt(0.2119034982 * channels[0] + 0.6806995451 * channels[1] + 0.1073969566 * channels[2])
            val s = cbrt(0.0883024619 * channels[0] + 0.2817188376 * channels[1] + 0.6299787005 * channels[2])
            val a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            val b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            if (hypot(a, b) < 0.03) return 260 to 0.012
            val hue = (atan2(b, a) * 180.0 / PI + 360.0) % 360.0
            val snapped = palette.minByOrNull { candidate ->
                val diff = abs(candidate.toDouble() - hue)
                min(diff, 360.0 - diff)
            } ?: palette[0]
            return snapped to 0.085
        }

        private fun splitTitle(text: String): Pair<String, String> {
            val orIndex = text.indexOf("; or, ")
            if (orIndex >= 0) {
                return text.substring(0, orIndex) to text.substring(orIndex + 6)
            }
            val match = subtitleRegex.matchEntire(text)
            if (match != null) {
                return match.groupValues[1] to match.groupValues[2]
            }
            return text to ""
        }

        internal fun graphemeCount(text: String): Int {
            if (text.isEmpty()) return 0
            val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
            iterator.setText(text)
            var count = 0
            while (iterator.next() != BreakIterator.DONE) {
                count += 1
            }
            return count
        }

        internal fun roundAwayFromZero(value: Double): Double =
            if (value >= 0.0) floor(value + 0.5) else ceil(value - 0.5)

        private fun round2(value: Double): Double = roundAwayFromZero(value * 100.0) / 100.0

        internal fun parseAo3SeriesId(urlString: String): Long? {
            if (urlString.isBlank()) return null
            val parts = runCatching { URI(urlString).path }
                .getOrNull()
                ?.split('/')
                ?.filter { it.isNotEmpty() }
                ?: return null
            val index = parts.indexOf("series")
            if (index < 0 || index + 1 >= parts.size) return null
            return parts[index + 1].toLongOrNull()
        }
    }
}

/** Pure color and layout math shared by the Compose cover renderer and JVM tests. */
object GeneratedCoverMath {
    const val FANDOM_OPACITY: Double = 0.88
    const val BYLINE_OPACITY: Double = 0.86

    data class Rgb(val r: Double, val g: Double, val b: Double)

    fun lighterGroundLightness(lightness: Double): Double = min(lightness + 0.07, 0.50)

    fun strokeFloor(width: Double): Double = 0.9 * 112.0 / max(width, 1.0)

    /** Invert the area of `x + y <= cut` so 135° bands cover exact fractions of the card. */
    fun crossoverCut(fraction: Double, height: Double): Double {
        val w = 112.0
        if (height <= 0.0) return w * fraction
        if (fraction <= 0.0) return 0.0
        if (fraction >= 1.0) return w + height
        var low = 0.0
        var high = w + height
        fun square(value: Double): Double = max(value, 0.0) * max(value, 0.0)
        repeat(32) {
            val middle = (low + high) / 2.0
            val area = (square(middle) - square(middle - w) -
                square(middle - height) + square(middle - w - height)) / 2.0
            if (area / (w * height) < fraction) low = middle else high = middle
        }
        return (low + high) / 2.0
    }

    /** OKLCH to clipped sRGB; canvas and contrast tests use the same conversion. */
    fun oklchToRgb(lightness: Double, chroma: Double, hue: Double): Rgb {
        val angle = hue * PI / 180.0
        val a = chroma * cos(angle)
        val b = chroma * sin(angle)
        val l = (lightness + 0.3963377774 * a + 0.2158037573 * b).pow(3)
        val m = (lightness - 0.1055613458 * a - 0.0638541728 * b).pow(3)
        val s = (lightness - 0.0894841775 * a - 1.2914855480 * b).pow(3)
        fun encode(value: Double): Double {
            val x = min(max(value, 0.0), 1.0)
            return if (x <= 0.0031308) 12.92 * x else 1.055 * x.pow(1.0 / 2.4) - 0.055
        }
        return Rgb(
            r = encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            g = encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            b = encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }
}

fun SavedWork.generatedCoverRecipe(): GeneratedCoverRecipe =
    GeneratedCoverRecipe.create(
        id = ao3WorkID?.toLong(),
        title = title,
        author = author,
        fandoms = workFandoms,
        tags = if (workTagsFetched) workFreeforms else workTags,
        words = wordCount,
        complete = isComplete,
        seriesID = ao3SeriesID?.toLong() ?: GeneratedCoverRecipe.parseAo3SeriesId(seriesUrl),
        part = seriesPosition,
        firstAuthor = AO3AuthorIdentities.firstDisplayName(authorIdentitiesJSON)
    )

fun AO3WorkSummary.generatedCoverRecipe(): GeneratedCoverRecipe =
    GeneratedCoverRecipe.create(
        id = id,
        title = title,
        author = authorText,
        fandoms = fandoms,
        tags = freeforms,
        words = wordCount,
        complete = isComplete ?: true,
        seriesID = seriesUrl?.let(GeneratedCoverRecipe::parseAo3SeriesId),
        part = seriesPosition ?: 0,
        firstAuthor = authors.firstOrNull()
    )
