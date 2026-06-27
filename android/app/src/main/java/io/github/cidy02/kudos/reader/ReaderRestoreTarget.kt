package io.github.cidy02.kudos.reader

/**
 * Where the reader should open. Resolution order (see READER_STATE_CONTRACT.md):
 * a same-platform-compatible locator first, then the cross-platform fallback
 * fields, otherwise the beginning of the work.
 */
sealed interface ReaderRestoreTarget {
    /** Inner Readium locator JSON proven compatible with this platform/engine. */
    data class Locator(val locatorJson: String) : ReaderRestoreTarget

    /** Cross-platform approximate position. */
    data class Fallback(val spineIndex: Int, val scrollFraction: Double) : ReaderRestoreTarget

    data object Beginning : ReaderRestoreTarget
}
