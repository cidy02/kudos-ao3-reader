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
 * - `readerMargin` becomes a multiplier of a 28pt base, clamped to [0.5, 2.0].
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
        return ReaderPreferences(
            theme = resolveTheme(reader, app),
            scroll = scroll,
            columnCount = if (!scroll && reader.readerTwoPage) 2 else 1,
            fontSizePercent = fontSizePercent(reader.readerFontPt),
            lineHeight = reader.readerLineHeight.coerceIn(MIN_LINE_HEIGHT, MAX_LINE_HEIGHT),
            letterSpacingEm = reader.readerLetterSpacing.coerceAtLeast(0.0),
            wordSpacingEm = reader.readerWordSpacing.coerceAtLeast(0.0),
            pageMarginsFactor = marginsFactor(reader.readerMargin),
            justify = reader.readerJustify,
            bold = reader.readerBoldText,
            fontFamily = fontFamily(reader.readerFontId),
            publisherStyles = !reader.readerCustomize,
            fontDeclarations = fontDeclarations
        )
    }

    fun resolveTheme(reader: ReaderSettings, app: AppSettings): ReaderColorTheme {
        return if (reader.matchAppReaderTheme) {
            when (app.appTheme) {
                AppThemeSetting.Dark, AppThemeSetting.Oled -> ReaderColorTheme.Dark
                AppThemeSetting.Sepia -> ReaderColorTheme.Sepia
                AppThemeSetting.Light, AppThemeSetting.System -> ReaderColorTheme.Light
            }
        } else {
            when (reader.readerTheme) {
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

    private fun fontFamily(fontId: String): String? =
        fontId.takeIf {
            it.isNotBlank() && !it.equals("system", true) && !it.equals("default", true)
        }

    private fun buildFontDeclarations(
        selectedFontId: String,
        customFonts: List<CustomFont>,
        fontPathResolver: ((String) -> String?)?
    ): List<CustomFontDeclaration> {
        if (fontPathResolver == null) return emptyList()
        val declarations = mutableListOf<CustomFontDeclaration>()
        val registeredFontIds = mutableSetOf<String>()

        for (font in customFonts) {
            val path = fontPathResolver(font.fileName) ?: continue
            val decl = CustomFontDeclaration(
                fontFamily = font.selectionId,
                fontPath = path,
                alternates = listOf(font.name, font.fileName).filter { it.isNotBlank() && it != font.selectionId }
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
                        alternates = listOf(fileName)
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
        const val MIN_MARGIN_FACTOR = 0.5
        const val MAX_MARGIN_FACTOR = 2.0
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
            }
    }
}
