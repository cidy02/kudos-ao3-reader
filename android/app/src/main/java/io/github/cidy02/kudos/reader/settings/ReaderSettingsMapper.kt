package io.github.cidy02.kudos.reader.settings

import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import kotlin.math.roundToInt

/**
 * Maps the settings-contract reader fields onto engine-agnostic
 * [ReaderPreferences]. Documented fallbacks:
 * - `appTheme = System` resolves to Light (Readium has no "follow system" EPUB theme here).
 * - `readerFontPt` becomes a percentage of an 18pt base.
 * - `readerMargin` becomes a multiplier of a 28pt base, covering the iOS 8–64pt range.
 * - Custom font ids other than system/default are passed through by name and registered
 *   with disk font paths via [CustomFontDeclaration]s for Readium font loading.
 */
class ReaderSettingsMapper(private val baseFontPt: Double = DEFAULT_BASE_FONT_PT) {

    fun map(
        reader: ReaderSettings,
        app: AppSettings,
        customFonts: List<CustomFont> = emptyList(),
        fontPathResolver: ((String) -> String?)? = null
    ): ReaderPreferences {
        val scroll = reader.readerMode == ReaderMode.Scroll
        val fontDeclarations = buildFontDeclarations(reader.readerFontId, customFonts, fontPathResolver)
        val layout = if (reader.readerCustomize) reader else ReaderSettings()
        return ReaderPreferences(
            theme = resolveTheme(reader, app),
            scroll = scroll,
            columnCount = if (!scroll && reader.readerTwoPage) 2 else 1,
            fontSizePercent = fontSizePercent(reader.readerFontPt),
            lineHeight = layout.readerLineHeight.coerceIn(MIN_LINE_HEIGHT, MAX_LINE_HEIGHT),
            letterSpacingEm = layout.readerLetterSpacing.coerceAtLeast(0.0),
            wordSpacingEm = layout.readerWordSpacing.coerceAtLeast(0.0),
            pageMarginsFactor = marginsFactor(layout.readerMargin),
            justify = layout.readerJustify,
            bold = reader.readerBoldText,
            fontFamily = fontFamily(reader.readerFontId, fontDeclarations),
            // iOS always applies font, bold, text size and its comfortable layout defaults.
            publisherStyles = false,
            fontDeclarations = fontDeclarations
        )
    }

    fun resolveTheme(reader: ReaderSettings, app: AppSettings): ReaderColorTheme {
        return if (reader.matchAppReaderTheme) {
            when (app.appTheme) {
                AppThemeSetting.Oled -> ReaderColorTheme.Oled
                AppThemeSetting.Dark -> ReaderColorTheme.Dark
                AppThemeSetting.Sepia -> ReaderColorTheme.Sepia
                AppThemeSetting.Light, AppThemeSetting.System -> ReaderColorTheme.Light
            }
        } else {
            when (reader.readerTheme) {
                ReaderThemeSetting.Oled -> ReaderColorTheme.Oled
                ReaderThemeSetting.Dark -> ReaderColorTheme.Dark
                ReaderThemeSetting.Sepia -> ReaderColorTheme.Sepia
                ReaderThemeSetting.Light -> ReaderColorTheme.Light
            }
        }
    }

    private fun fontSizePercent(pt: Double): Int =
        ((pt / baseFontPt) * 100).roundToInt().coerceIn(MIN_FONT_PERCENT, MAX_FONT_PERCENT)

    private fun marginsFactor(marginPt: Double): Double =
        (marginPt / DEFAULT_MARGIN_PT).coerceIn(MIN_MARGIN_FACTOR, MAX_MARGIN_FACTOR)

    /**
     * A custom font id is only requested from Readium if [fontDeclarations] actually
     * registered an @font-face for it - otherwise Readium would be asked for a family
     * with no matching face and silently fall back to the default font anyway, which
     * is harder to debug than just not requesting a family at all.
     */
    private fun fontFamily(fontId: String, fontDeclarations: List<CustomFontDeclaration>): String? {
        if (fontId.isBlank() || fontId.equals("system", true) || fontId.equals("default", true)) {
            return null
        }
        if (fontId.startsWith("custom:")) {
            return fontId.takeIf { id -> fontDeclarations.any { it.fontFamily == id } }
        }
        return fontId
    }

    private fun buildFontDeclarations(
        selectedFontId: String,
        customFonts: List<CustomFont>,
        fontPathResolver: ((String) -> String?)?
    ): List<CustomFontDeclaration> {
        // Stable declarations keep a font pick from rebuilding the navigator at the old restore locator.
        val declarations = io.github.cidy02.kudos.core.model.ReaderFontCatalog.builtIns.mapNotNull { option ->
            when (option.id) {
                "nyserif" -> CustomFontDeclaration("nyserif", alternates = listOf("New York", "ui-serif", "Georgia", "serif"))
                "georgia" -> CustomFontDeclaration("georgia", alternates = listOf("Georgia", "serif"))
                "palatino" -> CustomFontDeclaration("palatino", alternates = listOf("Palatino", "serif"))
                "times" -> CustomFontDeclaration("times", alternates = listOf("Times New Roman", "serif"))
                "helvetica" -> CustomFontDeclaration("helvetica", alternates = listOf("Helvetica Neue", "sans-serif"))
                "avenir" -> CustomFontDeclaration("avenir", alternates = listOf("Avenir", "sans-serif"))
                "menlo" -> CustomFontDeclaration("menlo", alternates = listOf("Menlo", "monospace"))
                else -> null
            }
        }.toMutableList()
        if (fontPathResolver == null) return declarations
        val registeredFontIds = mutableSetOf<String>()

        for (font in customFonts) {
            val path = fontPathResolver(font.fileName) ?: continue
            val decl = CustomFontDeclaration(
                fontFamily = font.selectionId,
                fontPath = path,
                alternates = listOf("serif")
            )
            declarations.add(decl)
            registeredFontIds.add(font.selectionId)
        }

        if (selectedFontId.startsWith("custom:") && selectedFontId !in registeredFontIds) {
            val fileName = selectedFontId.removePrefix("custom:")
            val path = fontPathResolver(fileName)
            if (path != null) {
                declarations.add(
                    CustomFontDeclaration(
                        fontFamily = selectedFontId,
                        fontPath = path,
                        alternates = listOf("serif")
                    )
                )
            }
        }

        return declarations
    }

    companion object {
        const val DEFAULT_BASE_FONT_PT = 18.0
        const val DEFAULT_MARGIN_PT = 28.0
        const val MIN_FONT_PERCENT = 50
        const val MAX_FONT_PERCENT = 250
        const val MIN_MARGIN_FACTOR = 8.0 / DEFAULT_MARGIN_PT
        const val MAX_MARGIN_FACTOR = 64.0 / DEFAULT_MARGIN_PT
        const val MIN_LINE_HEIGHT = 1.0
        const val MAX_LINE_HEIGHT = 3.0

        /**
         * Inverse of [fontSizePercent]: percent of [DEFAULT_BASE_FONT_PT] → points.
         * Used when persisting display-sheet font size into DataStore.
         */
        fun fontPtFromPercent(
            percent: Int,
            baseFontPt: Double = DEFAULT_BASE_FONT_PT
        ): Double {
            val clamped = percent.coerceIn(MIN_FONT_PERCENT, MAX_FONT_PERCENT)
            return (clamped / 100.0) * baseFontPt
        }

        fun toReaderThemeSetting(theme: ReaderColorTheme): ReaderThemeSetting =
            when (theme) {
                ReaderColorTheme.Light -> ReaderThemeSetting.Light
                ReaderColorTheme.Sepia -> ReaderThemeSetting.Sepia
                ReaderColorTheme.Dark -> ReaderThemeSetting.Dark
                ReaderColorTheme.Oled -> ReaderThemeSetting.Oled
            }
    }
}
