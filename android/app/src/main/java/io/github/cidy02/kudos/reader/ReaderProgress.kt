package io.github.cidy02.kudos.reader

/**
 * Engine-agnostic reading position captured at a save point.
 *
 * [locatorJson] is the platform-specific Readium locator, already wrapped in the
 * portable [ReaderLocatorCodec] envelope. [spineIndex] and [scrollFraction] are
 * the cross-platform fallback fields and must always be populated, even when a
 * richer locator is present (see READER_STATE_CONTRACT.md).
 */
data class ReaderProgress(
    val spineIndex: Int,
    val scrollFraction: Double,
    val locatorJson: String? = null
) {
    val isMeaningful: Boolean
        get() = spineIndex > 0 || scrollFraction > 0.0 || !locatorJson.isNullOrBlank()
}
