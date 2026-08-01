package io.github.cidy02.kudos.reader

/**
 * Formats live reading progress for the immersive bottom chrome.
 *
 * Prefer whole-book [ReaderProgress.totalProgression] when present; otherwise
 * estimate from spine index + intra-spine scroll fraction.
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

    fun label(progress: ReaderProgress?, spineCount: Int): String {
        val pct = percent(progress, spineCount)
        val chapter = progress?.let { p ->
            if (spineCount > 0) {
                val idx = (p.spineIndex + 1).coerceIn(1, spineCount)
                "Ch. $idx/$spineCount"
            } else {
                null
            }
        }
        return when {
            pct != null && chapter != null -> "$chapter · $pct%"
            pct != null -> "$pct%"
            chapter != null -> chapter
            else -> ""
        }
    }
}
