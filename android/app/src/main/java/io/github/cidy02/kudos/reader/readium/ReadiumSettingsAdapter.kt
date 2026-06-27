package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.preferences.Theme

/**
 * Maps engine-agnostic [ReaderPreferences] to Readium [EpubPreferences].
 *
 * Documented fallbacks:
 * - Bold text (`readerBoldText`) and explicit custom fonts (`readerFontID`) are
 *   NOT applied here yet: Readium's `fontWeight`/`fontFamily` are value-class
 *   preferences and custom-font *import/registration* is deferred (see HANDOFF).
 *   The neutral [ReaderPreferences] still carries them for a later pass.
 * - `publisherStyles = true` keeps the EPUB's own CSS; user overrides apply when
 *   the reader "Customize" toggle is on.
 */
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
            wordSpacing = prefs.wordSpacingEm.takeIf { it > 0.0 }
        )
    }
}
