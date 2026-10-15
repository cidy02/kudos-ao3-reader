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
}
