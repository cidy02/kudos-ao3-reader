package io.github.cidy02.kudos.reader.settings

import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
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
 * - Custom font ids other than system/default are passed through by name; actual
 *   custom-font *import* is deferred (see HANDOFF.md), so unknown fonts fall back
 *   to the publisher/default font at the adapter layer.
 */
class ReaderSettingsMapper(private val baseFontPt: Double = DEFAULT_BASE_FONT_PT) {

    fun map(reader: ReaderSettings, app: AppSettings): ReaderPreferences {
        val scroll = reader.readerMode == ReaderMode.Scroll
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
            publisherStyles = !reader.readerCustomize
        )
    }

    fun resolveTheme(reader: ReaderSettings, app: AppSettings): ReaderColorTheme {
        return if (reader.matchAppReaderTheme) {
            when (app.appTheme) {
                AppThemeSetting.Dark -> ReaderColorTheme.Dark
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

    companion object {
        const val DEFAULT_BASE_FONT_PT = 18.0
        const val DEFAULT_MARGIN_PT = 28.0
        const val MIN_FONT_PERCENT = 50
        const val MAX_FONT_PERCENT = 250
        const val MIN_MARGIN_FACTOR = 0.5
        const val MAX_MARGIN_FACTOR = 2.0
        const val MIN_LINE_HEIGHT = 1.0
        const val MAX_LINE_HEIGHT = 3.0
    }
}
