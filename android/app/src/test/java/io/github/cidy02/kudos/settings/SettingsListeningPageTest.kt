package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.work.WorkInfo
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.settings.ReaderTTSEngineKind
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.TTSVoice
import io.github.cidy02.kudos.reader.speech.VoicePackState
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
    fun kokoroSectionUsesTheIOSSectionAndActionTitles() {
        compose.setContent { SettingsListeningPage(repository, engine, packInstalled = false) }
        compose.onNodeWithText("Kokoro Neural Engine").performScrollTo().assertExists()
        compose.onNodeWithText("Download Kokoro (Neural Engine)").performScrollTo().assertExists()
        compose.onNodeWithText("Kokoro Pack").assertDoesNotExist()
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
    fun resetReadAloudClearsExplicitVoiceRatePitchAndEngineWithoutChangingBackupSettings() {
        runBlocking {
            repository.updateSpeechVoiceIdentifier("7")
            repository.updateSpeechRate(1.3f)
            repository.updateSpeechPitch(1.15f)
            repository.updateSpeechEngine(ReaderTTSEngineKind.SYSTEM.rawValue)
        }
        engine.applySpeechPreferences(
            ReaderPreferences(
                speechVoiceIdentifier = "7",
                speechRate = 1.3f,
                speechPitch = 1.15f,
                speechEngine = ReaderTTSEngineKind.SYSTEM.rawValue
            )
        )
        showPage()
        compose.onNodeWithText("Reset Read Aloud").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { repository.speechPreferences.first() == ReaderSpeechPreferences() } }
        val speech = runBlocking { repository.speechPreferences.first() }
        engine.applySpeechPreferences(speech.applyTo(ReaderPreferences()))
        assertNull(speech.voiceIdentifier)
        assertEquals(ReaderSpeechPreferences.DEFAULT_PITCH, speech.pitch, 0f)
        assertEquals(ReaderSpeechPreferences.AUTOMATIC_ENGINE, speech.engine)
        assertEquals("0", engine.appliedVoice)
        assertEquals(1f, engine.appliedRate, 0f)
        assertEquals(1f, engine.appliedPitch, 0f)
        assertEquals("", engine.appliedEngine)
        assertEquals(KudosSettings.Defaults, runBlocking { repository.snapshot() })
    }

    @Test
    fun engineChangedOnListeningPersistsReachesServiceAndWarnsWhenKokoroPackIsMissing() {
        compose.setContent { SettingsListeningPage(repository, engine, packInstalled = false) }
        compose.onNodeWithText("Engine").performScrollTo().performClick()
        compose.onNodeWithText("Kokoro").performClick()
        compose.waitUntil(5_000) {
            runBlocking { repository.speechPreferences.first().engine == ReaderTTSEngineKind.KOKORO.rawValue } &&
                engine.appliedEngine == ReaderTTSEngineKind.KOKORO.rawValue
        }
        compose.onNodeWithText(
            "Download the Kokoro Voice Pack to use Kokoro. Until then, you hear your device's own voice."
        ).assertExists()

        compose.onNodeWithText("Engine").performScrollTo().performClick()
        compose.onNodeWithText("Device voice").performClick()
        compose.waitUntil(5_000) {
            runBlocking { repository.speechPreferences.first().engine == ReaderTTSEngineKind.SYSTEM.rawValue } &&
                engine.appliedEngine == ReaderTTSEngineKind.SYSTEM.rawValue
        }
        compose.onNodeWithText(
            "Download the Kokoro Voice Pack to use Kokoro. Until then, you hear your device's own voice."
        ).assertDoesNotExist()
    }

    @Test
    fun voicePackSectionShowsConfirmationProgressCancelRetryAndInstalledStates() {
        assertEquals(
            VoicePackState.NotDownloaded,
            VoicePackState.from(state = null, phase = null, progress = -1f, error = null, installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Downloading(0f),
            VoicePackState.from(WorkInfo.State.ENQUEUED, phase = null, progress = -1f, error = null, installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Downloading(0.42f),
            VoicePackState.from(WorkInfo.State.RUNNING, phase = "downloading", progress = 0.42f, error = null, installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Extracting,
            VoicePackState.from(WorkInfo.State.RUNNING, phase = "extracting", progress = 1f, error = null, installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Cancelling,
            VoicePackState.from(WorkInfo.State.RUNNING, phase = "downloading", progress = 0.5f, error = null, installed = false, cancelling = true)
        )
        assertEquals(
            VoicePackState.Failed("Disk full."),
            VoicePackState.from(WorkInfo.State.FAILED, phase = null, progress = -1f, error = "Disk full.", installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Failed(VoicePackState.DEFAULT_FAILURE),
            VoicePackState.from(WorkInfo.State.FAILED, phase = null, progress = -1f, error = "", installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.NotDownloaded,
            VoicePackState.from(WorkInfo.State.CANCELLED, phase = null, progress = -1f, error = null, installed = false, cancelling = false)
        )
        assertEquals(
            VoicePackState.Downloaded,
            VoicePackState.from(WorkInfo.State.SUCCEEDED, phase = null, progress = 1f, error = null, installed = true, cancelling = false)
        )

        var downloads = 0
        var cancels = 0
        var packState by mutableStateOf<VoicePackState>(VoicePackState.NotDownloaded)
        compose.setContent {
            SettingsListeningPage(
                repository = repository,
                service = engine,
                packInstalled = packState == VoicePackState.Downloaded,
                voicePack = VoicePackUi(
                    state = packState,
                    installed = packState == VoicePackState.Downloaded,
                    onDownload = { downloads++ },
                    onCancel = { cancels++ }
                )
            )
        }

        compose.onNodeWithText(VOICE_PACK_DISCLOSURE).assertExists()
        compose.onNodeWithText("Download Kokoro (Neural Engine)").performScrollTo().performClick()
        compose.onNodeWithText(VOICE_PACK_CONFIRM_TITLE).assertExists()
        compose.onNodeWithText(VOICE_PACK_CONFIRM_MESSAGE).assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(0, downloads)

        compose.onNodeWithText("Download Kokoro (Neural Engine)").performScrollTo().performClick()
        compose.onNodeWithText("Download $VOICE_PACK_SIZE_LABEL").performClick()
        assertEquals(1, downloads)

        compose.runOnIdle { packState = VoicePackState.Downloading(0.42f) }
        compose.onNodeWithText("Downloading... 42%").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(1, cancels)

        compose.runOnIdle { packState = VoicePackState.Extracting }
        compose.onNodeWithText("Extracting...").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals(2, cancels)

        compose.runOnIdle { packState = VoicePackState.Cancelling }
        compose.onNodeWithText("Cancelling…").assertExists()

        compose.runOnIdle { packState = VoicePackState.Failed("Network lost.") }
        compose.onNodeWithText("Network lost.").assertExists()
        compose.onNodeWithText("Retry Download").performScrollTo().performClick()
        compose.onNodeWithText("Download $VOICE_PACK_SIZE_LABEL").performClick()
        assertEquals(2, downloads)

        compose.runOnIdle { packState = VoicePackState.Downloaded }
        compose.onNodeWithText("Voice Pack Downloaded").assertExists()
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
        @Volatile var appliedPitch = 1f
        @Volatile var appliedEngine = ""
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
        override fun setPitch(pitch: Float) { appliedPitch = pitch }
        override fun setEngine(engine: String) { appliedEngine = engine }
    }
}
