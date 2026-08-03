package io.github.cidy02.kudos.reader.settings

/**
 * Engine-agnostic declaration of an imported custom font file on disk.
 */
data class CustomFontDeclaration(
    /** Selection ID or family name, matching [ReaderPreferences.fontFamily] (e.g. "custom:uuid.ttf"). */
    val fontFamily: String,
    /** Absolute path to the font file on disk. */
    val fontPath: String,
    /** Optional alternate font family identifiers (e.g. display name or raw filename). */
    val alternates: List<String> = emptyList()
)

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
    val publisherStyles: Boolean,
    /** Registered custom font declarations from disk. */
    val fontDeclarations: List<CustomFontDeclaration> = emptyList()
)
