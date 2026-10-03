package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.totalProgressionIn
import kotlin.math.abs

/**
 * Decides which navigator reports are a real read.
 *
 * iOS seeds `ReadiumProgressPersistence` from the stored locator so the first
 * identical `locationDidChange` does not write, and `ReadiumSessionStamp`
 * leaves `legacyReaderProgress` in place until a locator actually moves
 * (`SavedWork.applyDebouncedReadiumLocator`). The first report after open is
 * that landing — Readium re-reporting where it opened, often as a new string —
 * and is not a read. Saving it is what rewrote a 42% macOS percent to 0%.
 */
class ReaderProgressGate {
    var workId: String? = null
        private set
    var hasMoved: Boolean = false
        private set
    var hasSessionPosition: Boolean = false
        private set

    private var landed = false
    private var sawProgression = false
    private var baselineProgression: Double? = null
    private var baselineSpine: Int = 0
    private var baselineScroll: Double = 0.0

    fun seed(workId: String, work: SavedWork) {
        this.workId = workId
        // The landing is whatever the navigator first reports, not the stored
        // percent. Comparing against the stored value would save a restore that
        // opened at 0% and wipe the percent the reader had not moved.
        baselineProgression = null
        sawProgression = false
        baselineSpine = work.lastSpineIndex
        baselineScroll = work.lastScrollFraction
        hasSessionPosition = !work.readiumLocator.isNullOrBlank()
        landed = false
        hasMoved = false
    }

    /**
     * Returns [progress] when it should be persisted. The open landing — the
     * first report, and the first one that carries a whole-book progression —
     * is never persisted. Later reports persist once progression, spine, or
     * scroll leaves that landing by [MIN_DELTA]. The baseline stays on the
     * landing (not the last noisy sample) so a slow read still commits.
     */
    fun consider(workId: String, progress: ReaderProgress): ReaderProgress? {
        if (this.workId != workId) return null
        val progression = progress.totalProgression ?: totalProgressionIn(progress.locatorJson)
        val locator = progress.locatorJson?.takeIf { it.isNotBlank() }
        val hasSignal = locator != null || progression != null ||
            progress.spineIndex > 0 || progress.scrollFraction > 0.0
        if (!hasSignal) return null
        hasSessionPosition = true
        if (!landed) {
            landed = true
            rememberLanding(progress, progression)
            return null
        }
        // Readium may report the open page once without totalProgression and
        // again with it. That second sample is still the landing.
        if (!sawProgression && progression != null) {
            rememberLanding(progress, progression)
            return null
        }
        val moved = when {
            progression != null && baselineProgression != null ->
                abs(progression - baselineProgression!!) >= MIN_DELTA
            progress.spineIndex != baselineSpine -> true
            else -> abs(progress.scrollFraction - baselineScroll) >= MIN_DELTA
        }
        if (!moved) return null
        hasMoved = true
        rememberLanding(progress, progression)
        return progress
    }

    private fun rememberLanding(progress: ReaderProgress, progression: Double?) {
        if (progression != null) {
            baselineProgression = progression
            sawProgression = true
        }
        baselineSpine = progress.spineIndex
        baselineScroll = progress.scrollFraction
    }

    fun sessionMatches(workId: String): Boolean = this.workId == workId

    companion object {
        /** iOS `ReadiumProgressPersistence.minProgressionDelta`. */
        const val MIN_DELTA = 0.001
    }
}
