package io.github.cidy02.kudos.reader.speech

import android.app.Application
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import androidx.test.core.app.ApplicationProvider
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowTextToSpeech

/** Brief 3dm: Read Aloud reads with the device's own voice until the Kokoro pack is installed. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SystemTTSServiceTest {
    private fun voice(name: String, locale: Locale, network: Boolean = false, installed: Boolean = true) =
        Voice(name, locale, Voice.QUALITY_NORMAL, Voice.LATENCY_NORMAL, network,
            if (installed) emptySet() else setOf(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))

    @After fun tearDown() = ShadowTextToSpeech.reset()

    @Test fun aVoiceThatNeedsTheNetworkIsNeverChosen() {
        val us = Locale.US
        val network = voice("cloud", us, network = true)
        val missing = voice("missing", us, installed = false)
        val british = voice("gb", Locale.UK)
        val local = voice("local", us)
        assertSame(local, SystemTTSService.onDeviceVoice(network, listOf(network, missing, british, local), us))
        assertSame(british, SystemTTSService.onDeviceVoice(null, listOf(network, british), us))
        assertNull(SystemTTSService.onDeviceVoice(network, listOf(network, missing), us))
        assertSame(local, SystemTTSService.onDeviceVoice(local, emptyList(), Locale.FRANCE))
    }

    @Test fun itReadsEachStretchInTurnAndAPauseReadsTheCutOffOneAgain() = runBlocking {
        ShadowTextToSpeech.addVoice(voice("local", Locale.getDefault()))
        val service = SystemTTSService(ApplicationProvider.getApplicationContext())
        val shadow = shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance())
        shadow.onInitListener.onInit(TextToSpeech.SUCCESS)
        assertEquals(SpeechStatus.STOPPED, service.status.value)

        val reading = async(Dispatchers.Default) { service.speak("First stretch.\n\nSecond stretch.") }
        suspend fun waitFor(text: String) = withTimeout(5_000) {
            while (shadow.lastSpokenText != text) kotlinx.coroutines.delay(10)
        }
        waitFor("First stretch.")
        shadow.utteranceProgressListener.onDone("kudos-1")
        waitFor("Second stretch.")
        service.pause()
        assertEquals(SpeechStatus.PAUSED, service.status.value)
        shadow.clearLastSpokenText()
        service.resume()
        waitFor("Second stretch.")
        shadow.utteranceProgressListener.onDone("kudos-3")
        withTimeout(5_000) { reading.await() }
        assertEquals(SpeechStatus.STOPPED, service.status.value)
        assertEquals(listOf("First stretch.", "Second stretch.", "Second stretch."), shadow.spokenTextList)
    }

    @Test fun aPackThatWillNotOpenReadsWithTheDeviceVoice() = runBlocking {
        // A49 F4: the pack's files are here (says packInstalled) but Kokoro cannot open them.
        ShadowTextToSpeech.addVoice(voice("local", Locale.getDefault()))
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val service = AutomaticTTSService(context, packInstalled = { true })
        val shadow = shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance())
        shadow.onInitListener.onInit(TextToSpeech.SUCCESS)
        val reading = async(Dispatchers.Default) { service.speak("Read by the device.") }
        withTimeout(5_000) { while (shadow.lastSpokenText != "Read by the device.") kotlinx.coroutines.delay(10) }
        assertEquals(SpeechStatus.PLAYING, withTimeout(5_000) {
            while (service.status.value != SpeechStatus.PLAYING) kotlinx.coroutines.delay(10); service.status.value
        })
        service.stop()
        withTimeout(5_000) { reading.await() }
    }

    @Test fun withNoVoiceOnTheDeviceItIsUnavailable() {
        ShadowTextToSpeech.addVoice(voice("cloud", Locale.getDefault(), network = true))
        val service = SystemTTSService(ApplicationProvider.getApplicationContext())
        shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance()).onInitListener.onInit(TextToSpeech.SUCCESS)
        assertEquals(SpeechStatus.UNAVAILABLE, service.status.value)
    }
    @Test fun automaticChecksPackAvailabilityAgainBeforeEveryUtterance() = runBlocking {
        ShadowTextToSpeech.addVoice(voice("local", Locale.getDefault()))
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val installed = java.util.concurrent.atomic.AtomicBoolean(false)
        val checks = java.util.concurrent.atomic.AtomicInteger()
        val service = AutomaticTTSService(context, packInstalled = { checks.incrementAndGet(); installed.get() })
        val shadow = shadowOf(ShadowTextToSpeech.getLastTextToSpeechInstance())
        shadow.onInitListener.onInit(TextToSpeech.SUCCESS)
        try {
            var id = 0
            suspend fun utterance(text: String) {
                val before = checks.get()
                val reading = async(Dispatchers.Default) { service.speak(text) }
                withTimeout(5_000) { while (shadow.lastSpokenText != text) kotlinx.coroutines.delay(10) }
                org.junit.Assert.assertTrue("availability must be checked for each utterance", checks.get() > before)
                shadow.utteranceProgressListener.onDone("kudos-${++id}")
                withTimeout(5_000) { reading.await() }
            }
            utterance("Before installation.")
            // Same Automatic service, changed files. An unusable pack falls back as before.
            installed.set(true)
            utterance("After installation.")
            installed.set(false)
            utterance("After removal.")
            assertEquals(listOf("Before installation.", "After installation.", "After removal."), shadow.spokenTextList)
        } finally {
            service.shutdown()
        }
    }

    @Test fun automaticHonoursEngineChoiceFallsBackWhenKokoroPackMissingAndForwardsPitch() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val kokoro = FakeSubTTSService(listOf(TTSVoice("0", "Kokoro A")))
        val device = FakeSubTTSService(emptyList())
        var installed = true
        val service = AutomaticTTSService(
            context = context,
            kokoro = kokoro,
            device = device,
            packInstalled = { installed }
        )
        try {
            // Default Automatic with pack installed uses Kokoro and exposes its voices.
            assertEquals(listOf(TTSVoice("0", "Kokoro A")), service.availableVoices.value)
            service.speak("Automatic utterance.")
            assertEquals(listOf("Automatic utterance."), kokoro.spoken)
            assertEquals(emptyList<String>(), device.spoken)

            // Forced Device voice ("system") uses device even when Kokoro pack is installed, and hides Kokoro voices.
            service.applySpeechPreferences(
                io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences(
                    pitch = 1.15f,
                    engine = "system"
                ).applyTo(io.github.cidy02.kudos.reader.settings.ReaderPreferences())
            )
            assertEquals(1.15f, device.pitchSet, 0f)
            assertEquals(1.15f, kokoro.pitchSet, 0f)
            withTimeout(5_000) {
                while (service.availableVoices.value.isNotEmpty()) kotlinx.coroutines.delay(10)
            }
            service.speak("Device utterance.")
            assertEquals(listOf("Device utterance."), device.spoken)
            assertEquals(listOf("Automatic utterance."), kokoro.spoken)

            // Forced Kokoro with pack installed uses Kokoro.
            service.setEngine("kokoro")
            withTimeout(5_000) {
                while (service.availableVoices.value.isEmpty()) kotlinx.coroutines.delay(10)
            }
            service.speak("Kokoro utterance.")
            assertEquals(listOf("Automatic utterance.", "Kokoro utterance."), kokoro.spoken)

            // Forced Kokoro without pack installed falls back to Device voice, as on iOS.
            installed = false
            service.speak("Fallback utterance.")
            assertEquals(listOf("Device utterance.", "Fallback utterance."), device.spoken)
        } finally {
            service.shutdown()
        }
    }

    private class FakeSubTTSService(voices: List<TTSVoice>) : TTSService {
        override val status = kotlinx.coroutines.flow.MutableStateFlow(SpeechStatus.STOPPED)
        override val spokenText = kotlinx.coroutines.flow.MutableStateFlow("")
        override val availableVoices = kotlinx.coroutines.flow.MutableStateFlow(voices)
        val spoken = mutableListOf<String>()
        var pitchSet = 1.0f
        var rateSet = 1.0f
        var voiceSet = "0"
        override suspend fun speak(text: String) {
            spoken += text
            spokenText.value = text
        }
        override fun pause() { status.value = SpeechStatus.PAUSED }
        override fun resume() { status.value = SpeechStatus.PLAYING }
        override fun stop() { status.value = SpeechStatus.STOPPED }
        override fun setVoice(id: String) { voiceSet = id }
        override fun setRate(rate: Float) { rateSet = rate }
        override fun setPitch(pitch: Float) { pitchSet = pitch }
    }

}
