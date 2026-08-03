package io.github.cidy02.kudos.reader

/**
 * Formats live reading progress for the immersive bottom chrome.
 *
 * Prefer whole-book [ReaderProgress.totalProgression] when present; otherwise
 * estimate from spine index + intra-spine scroll fraction.
 *
 * Chapter labels use normalized [ReaderSection]s so Preface/Summary/Afterword
 * are never shown as fake numbered chapters, and the denominator is the real
 * story-chapter count only.
 */
object ReaderProgressDisplay {

    fun percent(progress: ReaderProgress?, spineCount: Int): Int? {
        if (progress == null) return null
        progress.totalProgression?.let { total ->
            return (total.coerceIn(0.0, 1.0) * 100.0).toInt().coerceIn(0, 100)
        }
        if (spineCount <= 0) return null
        val spine = progress.spineIndex.coerceAtLeast(0).toDouble()
        val fraction = progress.scrollFraction.coerceIn(0.0, 1.0)
        val overall = ((spine + fraction) / spineCount.toDouble()).coerceIn(0.0, 1.0)
        return (overall * 100.0).toInt().coerceIn(0, 100)
    }

    fun label(progress: ReaderProgress?, sections: List<ReaderSection>): String {
        val spineCount = sections.size
        val pct = percent(progress, spineCount)
        val sectionPart = progress?.let { sectionLabel(it, sections) }
        return when {
            pct != null && sectionPart != null -> "$sectionPart · $pct%"
            pct != null -> "$pct%"
            sectionPart != null -> sectionPart
            else -> ""
        }
    }

    /**
     * Rough remaining-time estimate from remaining word count / 200 wpm
     * (iOS `ReaderTimeEstimate` spirit — not exact page-of-page).
     */
    fun minutesRemaining(progress: ReaderProgress?, wordCount: Int): Int? {
        if (wordCount <= 0) return null
        val fraction = progress?.totalProgression
            ?: return null
        val remaining = ((1.0 - fraction.coerceIn(0.0, 1.0)) * wordCount).toInt()
        if (remaining <= 0) return 0
        return (remaining / 200.0).toInt().coerceAtLeast(1)
    }

    private fun sectionLabel(progress: ReaderProgress, sections: List<ReaderSection>): String? {
        if (sections.isEmpty()) return null
        val idx = progress.spineIndex.coerceIn(0, sections.lastIndex)
        val section = sections[idx]
        val storyTotal = sections.storyChapterCount
        return when (section.kind) {
            ReaderSectionKind.PREFACE -> "Preface"
            ReaderSectionKind.SUMMARY -> "Summary"
            ReaderSectionKind.AFTERWORD -> "Afterword"
            ReaderSectionKind.CHAPTER -> {
                val i = section.storyChapterIndex ?: return null
                val total = maxOf(storyTotal, i)
                "Ch. $i/$total"
            }
            ReaderSectionKind.OTHER -> null
        }
    }
}
