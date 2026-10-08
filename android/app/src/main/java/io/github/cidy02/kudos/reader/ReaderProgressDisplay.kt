package io.github.cidy02.kudos.reader

import kotlin.math.roundToInt

/**
 * Formats live reading progress for the immersive bottom chrome.
 *
 * Whole-work percent is the navigator's rounded total progression, as on iOS.
 *
 * Chapter labels use normalized [ReaderSection]s so Preface/Summary/Afterword
 * are never shown as fake numbered chapters, and the denominator is the real
 * story-chapter count only.
 */
object ReaderProgressDisplay {

    fun percent(progress: ReaderProgress?): Int? {
        if (progress == null) return null
        return ((progress.totalProgression ?: 0.0).coerceIn(0.0, 1.0) * 100.0).roundToInt()
    }

    fun label(progress: ReaderProgress?, sections: List<ReaderSection>, chapters: String = ""): String {
        val pct = percent(progress)
        val sectionPart = progress?.let { sectionLabel(it, sections, chapters) }
        return when {
            pct != null && sectionPart != null -> "$sectionPart · $pct% of work"
            pct != null -> "$pct% of work"
            sectionPart != null -> sectionPart
            else -> ""
        }
    }

    fun minutesForPositions(count: Int): Int = (count.coerceAtLeast(0) * 55.0 / 60).roundToInt()

    fun durationLabel(minutes: Int): String {
        val value = minutes.coerceAtLeast(0)
        if (value < 60) return "$value min"
        val hours = value / 60
        val remainder = value % 60
        return if (remainder == 0) "$hours hr" else "$hours hr $remainder min"
    }

    fun sliderValue(page: Int, pageCount: Int): Float =
        if (pageCount > 1) (page.coerceIn(1, pageCount) - 1).toFloat() / (pageCount - 1) else 1f

    fun scrubPage(value: Float, pageCount: Int): Int =
        if (pageCount > 1) (value.coerceIn(0f, 1f) * (pageCount - 1)).roundToInt() + 1 else 1

    fun chapterRemainingPositions(page: Int, pageCount: Int, positionCount: Int): Int =
        if (pageCount <= 0 || positionCount <= 0) 0 else
            ((pageCount - page.coerceIn(1, pageCount)).toDouble() / pageCount * positionCount).roundToInt()

    fun pageLabel(page: Int, pageCount: Int): String =
        if (page < 1 || pageCount < 1) "Measuring pages" else "Page $page of $pageCount"

    private fun sectionLabel(progress: ReaderProgress, sections: List<ReaderSection>, chapters: String): String? {
        if (sections.isEmpty()) return null
        val idx = progress.spineIndex.coerceIn(0, sections.lastIndex)
        val section = sections[idx]
        val parts = chapters.split('/')
        val storyTotal = if (parts.size == 2) parts[1].trim().toIntOrNull() ?: sections.storyChapterCount
            else sections.storyChapterCount
        return when (section.kind) {
            ReaderSectionKind.PREFACE -> "Preface"
            ReaderSectionKind.SUMMARY -> "Summary"
            ReaderSectionKind.AFTERWORD -> "Afterword"
            ReaderSectionKind.CHAPTER -> {
                val i = section.storyChapterIndex ?: return null
                val total = maxOf(storyTotal, i)
                "Chapter $i of $total"
            }
            ReaderSectionKind.OTHER -> null
        }
    }
}
