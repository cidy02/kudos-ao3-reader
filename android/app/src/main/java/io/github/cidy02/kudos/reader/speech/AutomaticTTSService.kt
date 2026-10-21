package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.settings.ReaderTTSEngineKind
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
    private val kokoro: TTSService = KokoroTTSController(context.applicationContext),
    private val device: TTSService = SystemTTSService(context),
    private val packInstalled: () -> Boolean = { TTSDownloadWorker.isModelDownloaded(context.applicationContext) }
) : TTSService {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    /**
     * Settings › Listening's Engine; null is Automatic. iOS `ReaderTTSEngineKind.effective`:
     * the device's voice when it is chosen, Kokoro otherwise once its pack is here and opens.
     * Kokoro chosen without its pack reads with the device's voice, as iOS reads with Apple's.
     */
    private val requested = MutableStateFlow<ReaderTTSEngineKind?>(null)
    /**
     * The engine of the reading under way, so Pause, Resume and the player's state stay with it
     * when the pack finishes downloading mid-reading; they followed the pack's arrival and
     * reached Kokoro while the device still spoke (A49 F3).
     */
    @Volatile private var owner: TTSService? = null
    private fun kokoroAllowed(): Boolean = requested.value != ReaderTTSEngineKind.SYSTEM
    /** Kokoro when its pack is here and has not failed to open; the device's voice otherwise. */
    private fun active(): TTSService =
        owner ?: if (kokoroAllowed() && packInstalled() && kokoro.status.value != SpeechStatus.UNAVAILABLE) kokoro else device

    override val status: StateFlow<SpeechStatus> =
        combine(kokoro.status, device.status, requested) { k, d, _ -> if (active() === kokoro) k else d }
            .stateIn(scope, SharingStarted.Eagerly, active().status.value)
    override val spokenText: StateFlow<String> =
        combine(kokoro.spokenText, device.spokenText) { k, d -> if (active() === kokoro) k else d }
            .stateIn(scope, SharingStarted.Eagerly, "")
    /**
     * Kokoro's voices; the device's own is the one its Settings chose (Automatic). With the
     * device's voice chosen there are none, as iOS lists only the chosen engine's voices.
     */
    override val availableVoices: StateFlow<List<TTSVoice>> =
        combine(kokoro.availableVoices, requested) { voices, engine ->
            if (engine == ReaderTTSEngineKind.SYSTEM) emptyList() else voices
        }.stateIn(scope, SharingStarted.Eagerly, kokoro.availableVoices.value)

    override fun setPronunciationScope(fandom: String?, workID: String?) = kokoro.setPronunciationScope(fandom, workID)

    override suspend fun speak(text: String) {
        // A pack that is there but will not open reads with the device's voice: Read Aloud
        // skipped silently through the text (A49 F4).
        val engine = if (kokoroAllowed() && packInstalled() && kokoro.ensureReady()) kokoro else device
        if (owner !== engine) owner?.stop()
        owner = engine
        engine.speak(text)
    }
    override fun pause() = active().pause()
    override fun resume() = active().resume()
    override fun stop() {
        owner = null
        kokoro.stop()
        device.stop()
    }
    override fun setVoice(id: String) = kokoro.setVoice(id)
    override fun setRate(rate: Float) {
        kokoro.setRate(rate)
        device.setRate(rate)
    }
    /**
     * The device's voice takes it; Kokoro cannot. sherpa-onnx's Kokoro has no pitch control,
     * the same as iOS's SherpaKokoroTTSService, so Pitch changes only the device's voice.
     */
    override fun setPitch(pitch: Float) {
        kokoro.setPitch(pitch)
        device.setPitch(pitch)
    }
    /** Takes effect from the next stretch read, as iOS's choice does on its next utterance. */
    override fun setEngine(engine: String) {
        requested.value = ReaderTTSEngineKind.from(engine)
    }

    override fun shutdown() {
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
// Android TextToSpeech has no portable word → IPA lexicon API; stored corrections cannot reach this engine.
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
                // Checked and handed over under Pause's and Stop's lock: a Stop between the
                // check above and the hand-over was followed by speech (A49 F2), and a reading
                // a newer one replaced must not speak.
                val handed = synchronized(handover) {
                    _status.value == SpeechStatus.PLAYING && readings.get() == reading && run {
                        utterance = id to ended
                        _spokenText.value = chunks[index]
                        engine.speak(chunks[index], TextToSpeech.QUEUE_FLUSH, null, id) == TextToSpeech.SUCCESS
                    }
                }
                if (!handed) return
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
        synchronized(handover) {
            if (_status.value != SpeechStatus.PLAYING) return
            _status.value = SpeechStatus.PAUSED
            cutOff()
        }
    }

    override fun resume() {
        if (_status.value == SpeechStatus.PAUSED) _status.value = SpeechStatus.PLAYING
    }

    override fun stop() = synchronized(handover) {
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

    override fun shutdown() {
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
