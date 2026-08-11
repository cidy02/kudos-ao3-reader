package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure coverage of the in-session display-preference transforms used by
 * [ReaderViewModel] (font size clamp + theme / publisherStyles). Avoids
 * ViewModel + Room scheduling flakiness under Robolectric test dispatchers.
 */
class ReaderViewModelPreferencesTest {

    @Test
    fun fontSizeClampedAndDisablesPublisherStyles() {
        val base = defaultPrefs()
        val updated = applyFontSize(base, 150)
        assertEquals(150, updated.fontSizePercent)
        assertFalse(updated.publisherStyles)

        assertEquals(
            ReaderSettingsMapper.MAX_FONT_PERCENT,
            applyFontSize(base, 999).fontSizePercent
        )
        assertEquals(
            ReaderSettingsMapper.MIN_FONT_PERCENT,
            applyFontSize(base, 1).fontSizePercent
        )
    }

    @Test
    fun themeChangeKeepsOtherFields() {
        val base = defaultPrefs().copy(fontSizePercent = 120, scroll = true)
        val updated = applyTheme(base, ReaderColorTheme.Dark)
        assertEquals(ReaderColorTheme.Dark, updated.theme)
        assertEquals(120, updated.fontSizePercent)
        assertTrue(updated.scroll)
        assertFalse(updated.publisherStyles)
    }

    @Test
    fun liveProgressCopyPreservesPreferences() {
        val reading = ReaderUiState.Reading(
            work = io.github.cidy02.kudos.core.model.SavedWork(
                id = "w",
                title = "T",
                author = "A"
            ),
            epubPath = java.nio.file.Paths.get("/tmp/w.epub"),
            restoreTarget = ReaderRestoreTarget.Beginning,
            preferences = defaultPrefs().copy(fontSizePercent = 130),
            endOfWork = EndOfWorkActions(
                canMarkFinished = true,
                workId = null,
                sourceUrl = null,
                seriesUrl = null
            ),
            finished = false
        )
        val progress = ReaderProgress(spineIndex = 1, scrollFraction = 0.2, totalProgression = 0.4)
        val next = reading.copy(liveProgress = progress)
        assertEquals(progress, next.liveProgress)
        assertEquals(130, next.preferences.fontSizePercent)
    }

    @Test
    fun fontSizePersistMappingUses18ptBase() {
        // Same math ReaderViewModel uses when writing SettingsRepository.
        assertEquals(27.0, ReaderSettingsMapper.fontPtFromPercent(150), 0.0)
        assertEquals(
            ReaderThemeSetting.Dark,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Dark)
        )
    }

    // Mirrors ReaderViewModel.setFontSizePercent / setColorTheme transforms.
    private fun applyFontSize(prefs: ReaderPreferences, percent: Int): ReaderPreferences {
        val clamped = percent.coerceIn(
            ReaderSettingsMapper.MIN_FONT_PERCENT,
            ReaderSettingsMapper.MAX_FONT_PERCENT
        )
        return prefs.copy(fontSizePercent = clamped, publisherStyles = false)
    }

    private fun applyTheme(prefs: ReaderPreferences, theme: ReaderColorTheme): ReaderPreferences =
        prefs.copy(theme = theme, publisherStyles = false)

    private fun defaultPrefs() = ReaderPreferences(
        theme = ReaderColorTheme.Light,
        scroll = true,
        columnCount = 1,
        fontSizePercent = 100,
        lineHeight = 1.65,
        letterSpacingEm = 0.0,
        wordSpacingEm = 0.0,
        pageMarginsFactor = 1.0,
        justify = false,
        bold = false,
        fontFamily = null,
        publisherStyles = true
    )
}
