package io.github.cidy02.kudos.reader.speech

import io.github.cidy02.kudos.reader.ReaderProgressDisplay
import kotlin.math.roundToInt
import org.readium.r2.shared.publication.Locator

/** iOS ReaderSpeechSkip.seekIndex: each hold tick advances one position, stopping at bounds. */
internal object ReaderSpeechSeek {
    fun seekIndex(current: Int, count: Int, delta: Int): Int? {
        if (count <= 0 || delta == 0) return null
        val next = current.toLong() + delta
        return next.takeIf { it >= 0 && it < count }?.toInt()
    }

    fun target(
        positionsByChapter: List<List<Locator>>,
        from: Locator,
        visualPage: Int,
        visualPageCount: Int,
        delta: Int
    ): Locator? {
        val positions = positionsByChapter.firstOrNull { chapter ->
            chapter.firstOrNull()?.href?.removeFragment()?.isEquivalent(from.href.removeFragment()) == true
        } ?: return null
        if (positions.size <= 1) return null
        val firstPosition = positions.first().locations.position
        val globalPosition = from.locations.position
        val index = when {
            globalPosition != null && firstPosition != null -> globalPosition - firstPosition
            from.locations.progression != null ->
                (from.locations.progression!! * positions.lastIndex).roundToInt()
            else -> if (visualPageCount > 1) {
                (ReaderProgressDisplay.sliderValue(visualPage, visualPageCount) * positions.lastIndex).roundToInt()
            } else 0
        }.coerceIn(0, positions.lastIndex)
        return seekIndex(index, positions.size, delta)?.let(positions::get)
    }
}

/** Keep the last accepted target while navigator location updates catch up with hold ticks. */
internal class ReaderSpeechSeekSession(
    private val onStart: () -> Unit,
    private val navigate: (Locator) -> Boolean,
    private val reanchor: (Locator) -> Unit
) {
    private var locator: Locator? = null

    fun begin(from: Locator?) {
        if (from == null) return
        locator = from
        onStart()
    }

    fun step(positions: List<List<Locator>>, visualPage: Int, visualPageCount: Int, delta: Int): Boolean {
        val from = locator ?: return false
        val target = ReaderSpeechSeek.target(positions, from, visualPage, visualPageCount, delta) ?: return false
        if (!navigate(target)) return false
        locator = target
        return true
    }

    fun end() {
        val from = locator ?: return
        locator = null
        reanchor(from)
    }
}
