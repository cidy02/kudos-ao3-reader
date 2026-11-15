package io.github.cidy02.kudos.works.detail

import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.ui.components.ChapterBarGeometry
import io.github.cidy02.kudos.ui.components.ChapterBarItem
import io.github.cidy02.kudos.ui.components.ChapterBarModel
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Pure resume-card state matching iOS `ResumeCardModel` (`HomeResumeHero.swift`)
 * for Work Detail's short reading card.
 */
data class ResumeCardModel(
    val title: String,
    val fandoms: List<String>,
    val chapters: String,
    val rawProgress: Double?,
    val rawChapterProgress: Double?,
    val chapterName: String?,
    val newChapterCount: Int,
    val lastReadLabel: String? = null,
    val chapterPositions: List<Int>? = null
) {
    val progress: Double? = rawProgress?.coerceIn(0.0, 1.0)
    val chapterProgress: Double? = rawChapterProgress?.coerceIn(0.0, 1.0)
    val clampedNewChapterCount: Int = maxOf(0, newChapterCount)

    val workPercent: Int get() = ((progress ?: 0.0) * 100.0).roundToInt()
    val chapterPercent: Int get() = ((chapterProgress ?: 0.0) * 100.0).roundToInt()

    /** Nil when nothing has been read; omits the chapter half when progression is absent. */
    val detailProgressLine: String?
        get() {
            if (progress == null) return null
            val work = "$workPercent% of the work"
            return if (chapterProgress == null) work else "$chapterPercent% of the chapter · $work"
        }

    fun detailPrimaryTitle(fallback: String): String =
        if (progress == null) fallback else "Resume Chapter $chapterNumber"

    val postedChapters: Int get() = ChapterBarModel.postedChapterCount(chapters)
    val plannedChapters: Int get() = maxOf(ChapterBarModel.totalChapterCount(chapters) ?: postedChapters, postedChapters)
    val postedShortLabel: String get() = if (plannedChapters > 0) "$postedChapters of $plannedChapters" else chapters

    val chapterNumber: Int
        get() {
            chapterName?.let { name ->
                CHAPTER_NUMBER_REGEX.find(name)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { return it }
            }
            return ChapterBarGeometry.readingChapter(
                posted = postedChapters,
                progress = progress ?: 0.0,
                weights = chapterPositions?.map(Int::toDouble)
            )
        }

    val displayedChapterName: String
        get() {
            if (chapterName != null) return chapterName
            if (progress == null || progress == 0.0) {
                return if (lastReadLabel == null) "Not started" else "Last opened"
            }
            return "Chapter $chapterNumber"
        }

    /** Version E's compact reading-card title: `Ch 7, The Salt Road`. */
    val detailChapterName: String
        get() {
            if (progress == null) return displayedChapterName
            val raw = chapterName ?: return "Ch $chapterNumber"
            if (raw.lowercase(Locale.US) in SPECIAL_CHAPTER_TITLES) return raw
            val name = CHAPTER_PREFIX_REGEX.replaceFirst(raw, "")
            return if (name.isEmpty()) "Ch $chapterNumber" else "Ch $chapterNumber, $name"
        }

    val updateChapterValue: String
        get() = if (clampedNewChapterCount == 1) "1 new chapter" else "$clampedNewChapterCount new chapters"

    fun chapterItems(lengths: ChapterLengths?): List<ChapterBarItem> = ChapterBarModel.items(
        chapters = chapters,
        progress = progress,
        isFinished = progress == 1.0,
        weights = lengths?.positions,
        heights = lengths?.words,
        newChapterCount = 0
    )

    companion object {
        private val CHAPTER_NUMBER_REGEX = Regex("""(?i)\bch(?:apter)?\s*(\d+)""")
        private val CHAPTER_PREFIX_REGEX = Regex("""(?i)^ch(?:apter)?\s*\d+\s*[:.,\-]?\s*""")
        private val SPECIAL_CHAPTER_TITLES = setOf("preface", "summary", "afterword")
    }
}

/**
 * Generated cover gradient colors matching iOS `CoverArt.workGradient(fandoms:title:)`
 * (`CarouselCardStyle.swift`), always rich enough for white text and controls.
 */
internal fun workArtGradientColors(fandoms: List<String>, title: String): Pair<Color, Color> {
    val fandom = fandoms.firstOrNull { it.isNotBlank() }
    val familyHue = hueDegrees(fandom ?: title)
    val seed = coverSeed(title)
    val shade = (seed % 25u).toInt() - 12
    val hue = (familyHue + shade + 360) % 360
    return hslColor(hue.toDouble(), 0.46, 0.27) to hslColor(((hue + 22) % 360).toDouble(), 0.50, 0.41)
}

private fun hueDegrees(text: String): Int {
    var hash = 5381UL
    var index = 0
    while (index < text.length) {
        val cp = text.codePointAt(index)
        hash = hash * 33u + cp.toULong()
        index += Character.charCount(cp)
    }
    return (hash % 360u).toInt()
}

private fun coverSeed(text: String): UInt {
    var seed = 7u
    for (ch in text) {
        seed = seed * 31u + ch.code.toUInt()
    }
    return seed
}

private fun hslColor(hue: Double, saturation: Double, lightness: Double): Color {
    val chroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation
    val normalizedHue = ((hue % 360.0) + 360.0) % 360.0
    val sector = normalizedHue / 60.0
    val second = chroma * (1.0 - abs(sector % 2.0 - 1.0))
    val (r, g, b) = when {
        sector < 1.0 -> Triple(chroma, second, 0.0)
        sector < 2.0 -> Triple(second, chroma, 0.0)
        sector < 3.0 -> Triple(0.0, chroma, second)
        sector < 4.0 -> Triple(0.0, second, chroma)
        sector < 5.0 -> Triple(second, 0.0, chroma)
        else -> Triple(chroma, 0.0, second)
    }
    val match = lightness - chroma / 2.0
    return Color(
        red = (r + match).toFloat().coerceIn(0f, 1f),
        green = (g + match).toFloat().coerceIn(0f, 1f),
        blue = (b + match).toFloat().coerceIn(0f, 1f)
    )
}
