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
    val theme: ReaderColorTheme = ReaderColorTheme.Light,
    /** true = continuous scroll, false = paged. */
    val scroll: Boolean = true,
    /** 1 or 2 columns (two-page only meaningful in paged mode). */
    val columnCount: Int = 1,
    /** Font size as a percentage of the publisher base (100 = unchanged). */
    val fontSizePercent: Int = 100,
    val lineHeight: Double = 1.2,
    val letterSpacingEm: Double = 0.0,
    val wordSpacingEm: Double = 0.0,
    /** Page-margin multiplier (1.0 = Readium default). */
    val pageMarginsFactor: Double = 1.0,
    val justify: Boolean = false,
    val bold: Boolean = false,
    /** Explicit font family, or null to keep the publisher/default font. */
    val fontFamily: String? = null,
    /** When true, keep publisher styles and apply only minimal overrides. */
    val publisherStyles: Boolean = false,
    /** TTS speech rate (1.0 = normal). */
    val speechRate: Float = 1.0f,
    /** TTS speech pitch (1.0 = normal). */
    val speechPitch: Float = 1.0f,
    val speechVoiceIdentifier: String? = null,
    /** Registered custom font declarations from disk. */
    val fontDeclarations: List<CustomFontDeclaration> = emptyList()
)
