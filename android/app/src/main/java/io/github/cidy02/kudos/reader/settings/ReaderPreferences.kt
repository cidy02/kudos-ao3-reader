package io.github.cidy02.kudos.reader.settings

/**
 * Engine-agnostic reader preferences derived from the settings contract. The
 * Readium adapter ([io.github.cidy02.kudos.reader.readium]) translates these to
 * `EpubPreferences`; tests assert on this neutral shape instead of Readium types.
 */
data class ReaderPreferences(
    val theme: ReaderColorTheme,
    /** true = continuous scroll, false = paged. */
    val scroll: Boolean,
    /** 1 or 2 columns (two-page only meaningful in paged mode). */
    val columnCount: Int,
    /** Font size as a percentage of the publisher base (100 = unchanged). */
    val fontSizePercent: Int,
    val lineHeight: Double,
    val letterSpacingEm: Double,
    val wordSpacingEm: Double,
    /** Page-margin multiplier (1.0 = Readium default). */
    val pageMarginsFactor: Double,
    val justify: Boolean,
    val bold: Boolean,
    /** Explicit font family, or null to keep the publisher/default font. */
    val fontFamily: String?,
    /** When true, keep publisher styles and apply only minimal overrides. */
    val publisherStyles: Boolean
)
