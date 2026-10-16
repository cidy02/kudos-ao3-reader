package io.github.cidy02.kudos.reader

/** iOS's speech estimate; the position card keeps its separate silent-reading pace. */
object ReaderTimeEstimate {
    data class Timing(val duration: Double, val elapsed: Double)

    fun ttsSecondsPerPosition(rate: Double): Double =
        (200.0 * 55.0 / 60.0) / maxOf(0.01, 160.0 * rate) * 60.0

    fun ttsNowPlayingTiming(totalPositions: Int, remainingPositions: Int, rate: Double): Timing? {
        if (totalPositions <= 0) return null
        val perPosition = ttsSecondsPerPosition(rate)
        val duration = totalPositions * perPosition
        val remaining = remainingPositions.coerceIn(0, totalPositions) * perPosition
        return Timing(duration, (duration - remaining).coerceAtLeast(0.0))
    }
}

/** Keep system playback continuous between navigator samples, including pause and rate changes. */
internal class ReaderPlaybackClock {
    private var lastTiming: ReaderTimeEstimate.Timing? = null
    private var lastUpdatedAt = 0L
    private var wasPlaying = false

    fun reset() { lastTiming = null }

    fun update(timing: ReaderTimeEstimate.Timing?, playing: Boolean, nowMillis: Long): ReaderTimeEstimate.Timing? {
        if (timing == null) {
            reset()
            return null
        }
        val previous = lastTiming
        val elapsed = if (previous == null) timing.elapsed else {
            val advance = if (wasPlaying) (nowMillis - lastUpdatedAt).coerceAtLeast(0) / 1000.0 else 0.0
            // Duration already includes the speech rate; the OS clock always advances at 1x.
            (previous.elapsed + advance) / previous.duration * timing.duration
        }
        lastTiming = timing.copy(elapsed = elapsed.coerceIn(0.0, timing.duration))
        lastUpdatedAt = nowMillis
        wasPlaying = playing
        return lastTiming
    }
}
