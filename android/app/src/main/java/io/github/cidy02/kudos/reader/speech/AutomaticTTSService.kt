package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn

/**
 * iOS's Automatic engine: it "starts with an Apple voice, then uses Kokoro … after you install
 * its optional voice pack". Kokoro once its pack is on the device, the device's own voice until
 * then. Android read nothing aloud without the 45 MB pack; it reads at once now. The reader and
 * Settings' sample both speak through this.
 */
class AutomaticTTSService(
    context: Context,
    private val kokoro: KokoroTTSController = KokoroTTSController(context.applicationContext),
    private val device: SystemTTSService = SystemTTSService(context),
    private val packInstalled: () -> Boolean = { TTSDownloadWorker.isModelDownloaded(context.applicationContext) }
) : TTSService {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private fun active(): TTSService = if (packInstalled()) kokoro else device

    override val status: StateFlow<SpeechStatus> =
        combine(kokoro.status, device.status) { k, d -> if (packInstalled()) k else d }
            .stateIn(scope, SharingStarted.Eagerly, active().status.value)
    override val spokenText: StateFlow<String> =
        combine(kokoro.spokenText, device.spokenText) { k, d -> if (packInstalled()) k else d }
            .stateIn(scope, SharingStarted.Eagerly, "")
    /** Kokoro's voices; the device's own is the one its Settings chose (Automatic). */
    override val availableVoices: StateFlow<List<TTSVoice>> = kokoro.availableVoices

    override suspend fun speak(text: String) = active().speak(text)
    override fun pause() = active().pause()
    override fun resume() = active().resume()
    override fun stop() {
        kokoro.stop()
        device.stop()
    }
    override fun setVoice(id: String) = kokoro.setVoice(id)
    override fun setRate(rate: Float) {
        kokoro.setRate(rate)
        device.setRate(rate)
    }
    override fun setPitch(pitch: Float) {
        kokoro.setPitch(pitch)
        device.setPitch(pitch)
    }

    fun shutdown() {
        kokoro.shutdown()
        device.shutdown()
        scope.cancel()
    }
}

/**
 * The device's own text-to-speech, with an on-device voice only: a voice that needs the network
 * would send the work's words to the engine's server, and Kudos says it sends none. Unavailable
 * when the device has no such voice; the reader then offers the Kokoro pack, as before.
 * Android's engine cannot pause: pausing stops the stretch being read and resuming reads it again.
 */
class SystemTTSService(context: Context) : TTSService {
    private val _status = MutableStateFlow(SpeechStatus.UNAVAILABLE)
    override val status: StateFlow<SpeechStatus> = _status.asStateFlow()
    private val _spokenText = MutableStateFlow("")
    override val spokenText: StateFlow<String> = _spokenText.asStateFlow()
    override val availableVoices: StateFlow<List<TTSVoice>> = MutableStateFlow(emptyList<TTSVoice>()).asStateFlow()

    /** The stretch being read: its id, and whether it ended (true) or was cut off (false). */
    @Volatile private var utterance: Pair<String, CompletableDeferred<Boolean>>? = null
    private val utterances = AtomicInteger()
    private val readings = AtomicInteger()
    /** A reading's start and a cancelled one's end, one at a time: skipping ahead runs both at once. */
    private val handover = Any()
    private lateinit var engine: TextToSpeech

    init {
        engine = TextToSpeech(context.applicationContext) { result ->
            val voice = if (result != TextToSpeech.SUCCESS) null else onDeviceVoice(
                runCatching { engine.voice ?: engine.defaultVoice }.getOrNull(),
                runCatching { engine.voices }.getOrNull().orEmpty(),
                Locale.getDefault()
            )
            if (voice != null && runCatching { engine.setVoice(voice) }.getOrNull() == TextToSpeech.SUCCESS) {
                _status.value = SpeechStatus.STOPPED
            }
        }
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String) = Unit
            override fun onDone(id: String) = finish(id, true)
            @Suppress("OVERRIDE_DEPRECATION")
            override fun onError(id: String) = finish(id, true)
            override fun onError(id: String, errorCode: Int) = finish(id, true)
            override fun onStop(id: String, interrupted: Boolean) = finish(id, false)
        })
    }

    private fun finish(id: String, ended: Boolean) {
        utterance?.takeIf { it.first == id }?.second?.complete(ended)
    }

    override suspend fun speak(text: String) {
        if (_status.value == SpeechStatus.UNAVAILABLE) return
        val chunks = TextChunker.chunk(text)
        val reading = synchronized(handover) {
            _status.value = SpeechStatus.PLAYING
            readings.incrementAndGet()
        }
        var index = 0
        try {
            while (index < chunks.size) {
                // Paused: wait. Stopped: done.
                if (_status.first { it != SpeechStatus.PAUSED } != SpeechStatus.PLAYING) return
                val id = "kudos-${utterances.incrementAndGet()}"
                val ended = CompletableDeferred<Boolean>()
                utterance = id to ended
                _spokenText.value = chunks[index]
                if (engine.speak(chunks[index], TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) return
                // Cut off by a pause: the same stretch again on resume.
                if (ended.await()) index++
            }
        } finally {
            // A newer reading has taken over: its status is not this one's to end.
            synchronized(handover) {
                if (readings.get() == reading) {
                    utterance = null
                    if (_status.value == SpeechStatus.PLAYING) _status.value = SpeechStatus.STOPPED
                }
            }
        }
    }

    override fun pause() {
        if (_status.value != SpeechStatus.PLAYING) return
        _status.value = SpeechStatus.PAUSED
        cutOff()
    }

    override fun resume() {
        if (_status.value == SpeechStatus.PAUSED) _status.value = SpeechStatus.PLAYING
    }

    override fun stop() {
        if (_status.value != SpeechStatus.UNAVAILABLE) _status.value = SpeechStatus.STOPPED
        _spokenText.value = ""
        cutOff()
    }

    /** The engine reports a stop as well; not every engine does it at once. */
    private fun cutOff() {
        utterance?.second?.complete(false)
        engine.stop()
    }

    /** Automatic: the voice the device's Settings chose; Kokoro's speakers mean nothing here. */
    override fun setVoice(id: String) = Unit

    override fun setRate(rate: Float) {
        engine.setSpeechRate(ReaderSpeechPreferences.clampRate(rate))
    }

    override fun setPitch(pitch: Float) {
        if (pitch.isFinite()) engine.setPitch(pitch.coerceIn(0.5f, 2f))
    }

    fun shutdown() {
        stop()
        engine.shutdown()
    }

    internal companion object {
        /**
         * The engine's own voice when it is on the device, or else an on-device voice in the
         * device's language. None, when every voice needs the network or is not installed.
         * ponytail: the device's language, not the work's; iOS picks by the work's language.
         */
        fun onDeviceVoice(current: Voice?, voices: Collection<Voice>, locale: Locale): Voice? {
            fun onDevice(voice: Voice) = !voice.isNetworkConnectionRequired &&
                TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in voice.features.orEmpty()
            if (current != null && onDevice(current)) return current
            val candidates = voices.filter(::onDevice)
            return candidates.firstOrNull { it.locale == locale }
                ?: candidates.firstOrNull { it.locale.language == locale.language }
        }
    }
}
