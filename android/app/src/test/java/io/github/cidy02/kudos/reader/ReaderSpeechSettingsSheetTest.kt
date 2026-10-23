package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.TTSVoice
import io.github.cidy02.kudos.settings.SettingsListeningContent
import io.github.cidy02.kudos.settings.VoicePackUi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
class ReaderSpeechSettingsSheetTest {
    @get:Rule val compose = createComposeRule()
    private val repository = SettingsRepository(object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    })
    private val audition = TestSpeechService()
    private var sheet by mutableStateOf<ReaderSettingsSheet?>(null)
    private var closedPreferences: ReaderSpeechPreferences? = null
    private var toggles = 0

    private fun show() {
        compose.setContent {
            MaterialTheme {
                ReaderFanMenu(
                    isOpen = true, onOpenChange = {}, pills = emptyList(),
                    roundActions = listOf(readerReadAloudAction(
                        active = false, enabled = true, onSettings = { sheet = it },
                        onToggle = { toggles++ }
                    ))
                )
                when (sheet) {
                    ReaderSettingsSheet.Speech -> ReaderSpeechSettingsSheet(
                        repository, onDismiss = { closedPreferences = it; sheet = null },
                        listeningContent = { frame ->
                            SettingsListeningContent(repository, audition, true, VoicePackUi.fixed(true), frame)
                        }
                    )
                    ReaderSettingsSheet.Display -> ReaderDisplaySheet(
                        ReaderPreferences(), repository, keepScreenAwake = false,
                        onFontSizeChange = {}, onThemeChange = {}
                    )
                    null -> Unit
                }
            }
        }
    }

    private fun longPress() {
        compose.onNodeWithContentDescription("Read aloud").performTouchInput { longClick() }
        compose.waitForIdle()
    }

    @Test fun displayIncludesTheSharedSpeechControlsPackStatusAndSwitchLabels() {
        compose.setContent { io.github.cidy02.kudos.ui.theme.KudosTheme(io.github.cidy02.kudos.ui.theme.KudosThemeMode.Light) {
            ReaderDisplaySheet(ReaderPreferences(scroll = false, columnCount = 2), repository, keepScreenAwake = false,
                onFontSizeChange = {}, onThemeChange = {}, listeningContent = { frame ->
                    SettingsListeningContent(repository, audition, true, VoicePackUi.fixed(true), frame)
                })
        } }
        compose.onNodeWithContentDescription("Two-page spread").performScrollTo().assertExists()
        compose.onNodeWithContentDescription("Keep screen awake").assertExists()
        compose.onNodeWithText("Audition Voice").performScrollTo().assertExists()
        compose.onNodeWithText("Voice Pack Downloaded").performScrollTo().assertExists()
        compose.onNodeWithText(io.github.cidy02.kudos.settings.VOICE_PACK_DISCLOSURE).performScrollTo().assertExists()
        compose.onNodeWithText("Read author's notes").performScrollTo().assertExists()
        compose.onNodeWithText("Reset Read Aloud").performScrollTo().assertExists()
        compose.onNodeWithText("Voice").performScrollTo().performClick()
        compose.onNodeWithText("Test voice B · On device").performClick()
        compose.waitUntil(5_000) { kotlinx.coroutines.runBlocking { repository.speechPreferences.first().voiceIdentifier } == "7" }
    }

    @Test fun longPressOpensReadAloudAndReusesListeningControlsInsteadOfDisplay() {
        show()
        compose.onNodeWithContentDescription("Read aloud").performClick()
        assertEquals(1, toggles)
        assertNull(sheet)
        longPress()
        assertEquals(ReaderSettingsSheet.Speech, sheet)
        assertEquals(1, toggles)
        compose.onAllNodesWithText("Read Aloud").onFirst().assertExists()
        compose.onNodeWithText("Display & Themes").assertDoesNotExist()
        compose.onNodeWithText("Audition Voice").assertExists()
        compose.onNodeWithContentDescription("Done").assertExists()

        compose.onNodeWithText("0.9x").performScrollTo().performClick()
        compose.onNodeWithText("Voice").performScrollTo().performClick()
        compose.onNodeWithText("Test voice B · On device").performClick()
        compose.onNodeWithContentDescription("Done").performClick()
        compose.waitUntil(5_000) { closedPreferences != null }
        assertNull(sheet)
        assertEquals(0.9f, closedPreferences!!.rate, 0f)
        assertEquals("7", closedPreferences!!.voiceIdentifier)
        assertEquals(SpeechStatus.STOPPED, audition.status.value)
    }

    @Test fun dismissGestureAlsoDeliversTheLatestPreferences() {
        show()
        longPress()
        compose.onNodeWithText("1.1x").performScrollTo().performClick()
        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.Dismiss))
            .performSemanticsAction(SemanticsActions.Dismiss) { it() }
        compose.waitUntil(5_000) { closedPreferences != null }
        assertNull(sheet)
        assertEquals(1.1f, closedPreferences!!.rate, 0f)
    }

    private class TestSpeechService : TTSService {
        override val status = MutableStateFlow(SpeechStatus.STOPPED)
        override val spokenText = MutableStateFlow("")
        override val availableVoices = MutableStateFlow(listOf(TTSVoice("0", "Test voice A"), TTSVoice("7", "Test voice B")))
        override suspend fun speak(text: String) { status.value = SpeechStatus.PLAYING; awaitCancellation() }
        override fun pause() {}
        override fun resume() {}
        override fun stop() { status.value = SpeechStatus.STOPPED }
        override fun setVoice(id: String) {}
        override fun setRate(rate: Float) {}
        override fun setPitch(pitch: Float) {}
    }
}
