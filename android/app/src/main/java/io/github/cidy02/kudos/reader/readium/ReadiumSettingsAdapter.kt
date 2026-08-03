package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.settings.CustomFontDeclaration
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.ExperimentalReadiumApi

/**
 * Maps engine-agnostic [ReaderPreferences] to Readium [EpubPreferences] and
 * configures font family declarations on Readium's [EpubNavigatorFragment.Configuration].
 *
 * Documented fallbacks:
 * - Bold text (`readerBoldText`) is NOT applied here yet: Readium's `fontWeight`
 *   is a value-class preference.
 * - Explicit font families are passed into `EpubPreferences` via [FontFamily], and
 *   imported font files on disk are declared on [EpubNavigatorFragment.Configuration]
 *   via [configureFontDeclarations].
 * - `publisherStyles = true` keeps the EPUB's own CSS; user overrides apply when
 *   the reader "Customize" toggle is on.
 */
@OptIn(ExperimentalReadiumApi::class)
object ReadiumSettingsAdapter {
    fun toEpubPreferences(prefs: ReaderPreferences): EpubPreferences {
        return EpubPreferences(
            theme = when (prefs.theme) {
                ReaderColorTheme.Light -> Theme.LIGHT
                ReaderColorTheme.Sepia -> Theme.SEPIA
                ReaderColorTheme.Dark -> Theme.DARK
            },
            scroll = prefs.scroll,
            columnCount = if (!prefs.scroll && prefs.columnCount >= 2) ColumnCount.TWO else ColumnCount.AUTO,
            fontSize = prefs.fontSizePercent / 100.0,
            lineHeight = prefs.lineHeight,
            pageMargins = prefs.pageMarginsFactor,
            textAlign = if (prefs.justify) TextAlign.JUSTIFY else TextAlign.START,
            publisherStyles = prefs.publisherStyles,
            letterSpacing = prefs.letterSpacingEm.takeIf { it > 0.0 },
            wordSpacing = prefs.wordSpacingEm.takeIf { it > 0.0 },
            fontFamily = prefs.fontFamily?.let { FontFamily(it) }
        )
    }

    /**
     * Registers custom font declarations with Readium's navigator [EpubNavigatorFragment.Configuration].
     */
    fun configureFontDeclarations(
        config: EpubNavigatorFragment.Configuration,
        declarations: List<CustomFontDeclaration>
    ) {
        for (decl in declarations) {
            val family = FontFamily(decl.fontFamily)
            val alternates = decl.alternates.map { FontFamily(it) }
            config.addFontFamilyDeclaration(fontFamily = family, alternates = alternates) {
                addFontFace {
                    addSource(decl.fontPath)
                }
            }
        }
    }
}
