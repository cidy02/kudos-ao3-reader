package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.settings.SettingsAppearancePage
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
class CustomizeThemeSheetTest {
    @get:Rule val compose = createComposeRule()
    private val dataStore = object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    }
    private val repository = SettingsRepository(dataStore)

    @Test fun appearanceEntryOpensReadingTextControlsWithoutAnAccentPicker() {
        compose.setContent {
            val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
            CompositionLocalProvider(LocalKudosTokens provides KudosTokens.of(ReaderTheme.Light, Color.Red)) {
                SettingsAppearancePage(repository, settings)
            }
        }
        compose.onAllNodesWithText("Accent Color").assertCountEquals(0)
        openAndCheckSharedSheet()
    }

    @Test fun readerEntryOpensTheSameControlsAndResetPreservesTextSize() {
        runBlocking {
            repository.updateReaderFontPt(27.0)
            repository.updateReaderCustomize(true)
            repository.updateReaderBoldText(true)
        }
        compose.setContent {
            CompositionLocalProvider(LocalKudosTokens provides KudosTokens.of(ReaderTheme.Light, Color.Red)) {
                ReaderDisplaySheet(preferences = ReaderPreferences(), settingsRepository = repository,
                    listeningContent = { frame -> frame {} },
                    keepScreenAwake = false, onFontSizeChange = {}, onThemeChange = {})
            }
        }
        openAndCheckSharedSheet()
        compose.onNodeWithText("Reset Theme").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking {
            val reader = repository.snapshot().reader
            reader == ReaderSettings(readerFontPt = 27.0)
        } }
    }

    @Test fun customizeOffDisablesLayoutButBoldStillWritesWithoutEnablingCustomize() {
        compose.setContent {
            CompositionLocalProvider(LocalKudosTokens provides KudosTokens.of(ReaderTheme.Light, Color.Red)) {
                CustomizeThemeSheet(repository, onDismiss = {})
            }
        }
        compose.onNodeWithContentDescription("Line Spacing").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithContentDescription("Bold Text").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking {
            val reader = repository.snapshot().reader
            reader.readerBoldText && !reader.readerCustomize
        } }
    }

    private fun openAndCheckSharedSheet() {
        compose.onNodeWithText("Customize Theme…").performScrollTo().performClick()
        compose.onNodeWithText("Customize Theme").assertExists()
        compose.onNodeWithText("Bold Text").assertExists()
        compose.onNodeWithText("Customize").performScrollTo().assertExists()
        compose.onNodeWithText("Character Spacing").performScrollTo().assertExists()
        compose.onNodeWithText("Margins").performScrollTo().assertExists()
        compose.onNodeWithText("Justify Text").performScrollTo().assertExists()
        compose.onNodeWithText("Reset Theme").performScrollTo().assertExists()
    }

    @Test fun sampleResolvesCustomizeAndIncludesEveryParagraphFromIos() {
        val saved = KudosSettings.Defaults.copy(reader = ReaderSettings(readerBoldText = true,
            readerLineHeight = 2.4, readerLetterSpacing = 0.12, readerWordSpacing = 0.6,
            readerMargin = 64.0, readerJustify = true))
        val off = readerThemePreviewHTML(saved)
        assertTrue(off.contains("A Study in Starlight"))
        assertTrue(off.contains("quietly made room for one more"))
        assertTrue(off.contains("line-height: 1.65"))
        assertTrue(off.contains("letter-spacing: 0.0em"))
        val on = readerThemePreviewHTML(saved.copy(reader = saved.reader.copy(readerCustomize = true)))
        assertTrue(on.contains("line-height: 2.4"))
        assertTrue(on.contains("letter-spacing: 0.12em"))
        assertTrue(on.contains("word-spacing: 0.6em"))
        assertTrue(on.contains("0.5em 64.0px"))
        assertTrue(on.contains("text-align: justify"))
    }
}
