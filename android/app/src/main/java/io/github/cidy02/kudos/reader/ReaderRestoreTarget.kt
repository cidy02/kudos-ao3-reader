package io.github.cidy02.kudos.reader

/**
 * Where the reader should open. Same order as iOS Readium: a same-platform
 * locator, otherwise the start of [Fallback.spineIndex] when that index is
 * past the first spine item, otherwise the beginning. `legacyReaderProgress`
 * is not a resume position.
 */
sealed interface ReaderRestoreTarget {
    /** Inner Readium locator JSON proven compatible with this platform/engine. */
    data class Locator(val locatorJson: String) : ReaderRestoreTarget

    /** Cross-platform approximate position. */
    data class Fallback(val spineIndex: Int, val scrollFraction: Double) : ReaderRestoreTarget

    data object Beginning : ReaderRestoreTarget
}
