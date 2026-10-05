package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.TTSVoice
import io.github.cidy02.kudos.reader.speech.applySpeechPreferences
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
// A tall window: the page is a lazy list, and a section below the fold is not there to be found.
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
class SettingsListeningPageTest {
    @get:Rule val compose = createComposeRule()
    private val tempDir = Files.createTempDirectory("kudos-listening-test").toFile()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dataStore = PreferenceDataStoreFactory.create(
        scope = scope, produceFile = { File(tempDir, "settings.preferences_pb") }
    )
    private val repository = SettingsRepository(dataStore)
    private val engine = RecordingSpeechService()

    @After
    fun tearDown() {
        scope.cancel()
        tempDir.deleteRecursively()
    }

    @Test
    fun speedChangedOnListeningIsPersistedAndReadBySpeech() {
        showPage()
        compose.onNodeWithText("0.9x").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { repository.speechPreferences.first().rate == 0.9f } }

        // ReaderViewModel uses applyTo; ReaderSpeechController uses applySpeechPreferences.
        val readerPreferences = runBlocking {
            SettingsRepository(dataStore).speechPreferences.first().applyTo(ReaderPreferences())
        }
        engine.applySpeechPreferences(readerPreferences)
        assertEquals(0.9f, readerPreferences.speechRate, 0f)
        assertEquals(0.9f, engine.appliedRate, 0f)
    }

    @Test
    fun voiceChangedOnListeningIsPersistedAndReadBySpeech() {
        showPage()
        compose.onNodeWithText("Voice").performScrollTo().performClick()
        compose.onNodeWithText("Reported B · On device").performClick()
        compose.waitUntil(5_000) { runBlocking { repository.speechPreferences.first().voiceIdentifier == "7" } }

        val readerPreferences = runBlocking {
            SettingsRepository(dataStore).speechPreferences.first().applyTo(ReaderPreferences())
        }
        engine.applySpeechPreferences(readerPreferences)
        assertEquals("7", readerPreferences.speechVoiceIdentifier)
        assertEquals("7", engine.appliedVoice)
    }

    @Test
    fun voiceMenuListsExactlyEngineReportedVoicesAndTracksCatalogChanges() {
        showPage()
        compose.onNodeWithText("Voice").performScrollTo().performClick()
        compose.onAllNodesWithText("On device", substring = true).assertCountEquals(engine.availableVoices.value.size)
        engine.availableVoices.value.forEach {
            compose.onNodeWithText("${it.name} · On device").assertExists()
        }
        compose.onNodeWithText("Reported A · On device").performClick()
        compose.runOnIdle { engine.availableVoices.value = listOf(TTSVoice("42", "Reported C")) }
        compose.onNodeWithText("Voice").performClick()
        compose.onAllNodesWithText("On device", substring = true).assertCountEquals(1)
        compose.onNodeWithText("Reported C · On device").assertExists()
        compose.onNodeWithText("Reported A · On device").assertDoesNotExist()
        compose.onNodeWithText("Reported B · On device").assertDoesNotExist()
    }

    @Test
    fun auditionSpeaksIosSampleAndRestartsAtTheSharedRate() {
        showPage()
        compose.onNodeWithText("Play Sample").performScrollTo().performClick()
        compose.waitForIdle()
        compose.waitUntil(5_000) { engine.spokenText.value == ListeningSample.PlainNarration.text }
        compose.onNodeWithText("Playing Sample").assertExists()
        compose.onNodeWithText("0.9x").performScrollTo().performClick()
        compose.waitUntil(5_000) { engine.appliedRate == 0.9f && engine.speakCount >= 2 }
        compose.onNodeWithText("Stop").performScrollTo().performClick()
        compose.waitUntil(5_000) { engine.status.value == SpeechStatus.STOPPED }
    }

    @Test
    fun resetReadAloudClearsExplicitVoiceAndRateWithoutChangingBackupSettings() {
        runBlocking {
            repository.updateSpeechVoiceIdentifier("7")
            repository.updateSpeechRate(1.3f)
        }
        engine.applySpeechPreferences(ReaderPreferences(speechVoiceIdentifier = "7", speechRate = 1.3f))
        showPage()
        compose.onNodeWithText("Reset Read Aloud").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { repository.speechPreferences.first() == ReaderSpeechPreferences() } }
        val speech = runBlocking { repository.speechPreferences.first() }
        engine.applySpeechPreferences(speech.applyTo(ReaderPreferences()))
        assertNull(speech.voiceIdentifier)
        assertEquals("0", engine.appliedVoice)
        assertEquals(1f, engine.appliedRate, 0f)
        assertEquals(KudosSettings.Defaults, runBlocking { repository.snapshot() })
    }

    private fun showPage() {
        compose.setContent { SettingsListeningPage(repository, engine, packInstalled = true) }
    }

    private class RecordingSpeechService : TTSService {
        override val status = MutableStateFlow(SpeechStatus.STOPPED)
        override val spokenText = MutableStateFlow("")
        override val availableVoices = MutableStateFlow(listOf(
            TTSVoice("0", "Reported A"), TTSVoice("7", "Reported B")
        ))
        @Volatile var appliedRate = 1f
        var appliedVoice = "0"
        @Volatile var speakCount = 0
        override suspend fun speak(text: String) {
            speakCount++
            spokenText.value = text
            status.value = SpeechStatus.PLAYING
            awaitCancellation()
        }
        override fun pause() {}
        override fun resume() {}
        override fun stop() { status.value = SpeechStatus.STOPPED }
        override fun setVoice(id: String) { appliedVoice = id }
        override fun setRate(rate: Float) { appliedRate = rate }
        override fun setPitch(pitch: Float) {}
    }
}
