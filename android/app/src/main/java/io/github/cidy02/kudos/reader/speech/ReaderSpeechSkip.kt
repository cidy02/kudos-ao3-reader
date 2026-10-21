package io.github.cidy02.kudos.reader.speech

import org.readium.r2.shared.publication.Locator

/** iOS ReaderSpeechSkip: chapter means a spine resource, including front/back matter. */
internal object ReaderSpeechSkip {
    fun target(positions: List<List<Locator>>, spineIndex: Int, page: Int, forward: Boolean): Locator? {
        if (spineIndex !in positions.indices) return null
        val target = if (forward) {
            spineIndex + 1
        } else if (page.coerceAtLeast(1) > 2) {
            spineIndex
        } else if (spineIndex > 0) {
            spineIndex - 1
        } else if (page > 1) {
            spineIndex
        } else return null
        return positions.getOrNull(target)?.firstOrNull()
    }
}
