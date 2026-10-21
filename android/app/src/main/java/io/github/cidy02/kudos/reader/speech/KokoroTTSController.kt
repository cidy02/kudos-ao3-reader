package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.util.Log
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsKokoroModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class KokoroTTSController(private val context: Context) : TTSService {
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    @Volatile private var tts: OfflineTts? = null
    private val engineLock = Any()
    private val pronunciations = KokoroPronunciationStore(context.filesDir)
    @Volatile private var pronunciationScope: Pair<String?, String?> = null to null
    private var loadedLexicon = ""
    private var lexiconFile: File? = null

    override fun setPronunciationScope(fandom: String?, workID: String?) {
        pronunciationScope = fandom to workID
    }

    private fun resolvedLexicon(): String = try {
        val tokensFile = File(TTSDownloadWorker.modelDirectory(context), "tokens.txt")
        val tokens = if (!tokensFile.isFile) emptySet() else tokensFile.readLines().mapNotNull { line ->
            line.trim().substringBeforeLast(' ', "").takeIf { it.isNotEmpty() }
        }.toSet()
        val (fandom, workID) = pronunciationScope
        KokoroPronunciationLexicon.render(pronunciations.load().corrections().lexicon(fandom, workID), tokens)
    } catch (_: Exception) {
        // A damaged correction file must not silence a working voice or leak its words to logcat.
        Log.w("KokoroTTS", "Could not read pronunciation corrections; saved file kept")
        ""
    }

    @Volatile private var disposed = false
    /** The pack is here but would not open: not tried again for every stretch (A49 F4). */
    @Volatile private var failedToOpen = false
    
    private val _status = MutableStateFlow(SpeechStatus.UNAVAILABLE)
    override val status: StateFlow<SpeechStatus> = _status.asStateFlow()

    private val _spokenText = MutableStateFlow("")
    override val spokenText: StateFlow<String> = _spokenText.asStateFlow()

    private val _availableVoices = MutableStateFlow<List<TTSVoice>>(emptyList())
    override val availableVoices: StateFlow<List<TTSVoice>> = _availableVoices.asStateFlow()

    private val audioLock = Any()
    private var audioTrack: AudioTrack? = null
    private var synthesisJob: Job? = null
    @Volatile private var currentRate: Float = 1.0f
    @Volatile private var currentVoiceId: Int = 0

    init {
        initEngine()
    }

    private fun initEngine() = synchronized(engineLock) {
        if (tts != null || disposed || failedToOpen) return
        if (!TTSDownloadWorker.isModelDownloaded(context)) {
            _status.value = SpeechStatus.UNAVAILABLE
            return
        }

        try {
            val modelDir = TTSDownloadWorker.modelDirectory(context)
            val modelPath = File(modelDir, "model.int8.onnx").absolutePath
            val voicesPath = File(modelDir, "voices.bin").absolutePath
            val tokensPath = File(modelDir, "tokens.txt").absolutePath
            val dataDir = File(modelDir, "espeak-ng-data").absolutePath

            loadedLexicon = resolvedLexicon()
            val customLexicon = lexiconFile ?: File.createTempFile("kokoro-pronunciations-", ".txt", context.cacheDir)
                .also { lexiconFile = it }
            customLexicon.writeText(loadedLexicon)

            val kokoroConfig = OfflineTtsKokoroModelConfig(
                model = modelPath,
                voices = voicesPath,
                tokens = tokensPath,
                dataDir = dataDir,
                lengthScale = 1.0f,
                // v1.13.6 accepts this path, but its v0.19 frontend IGNORES lexicon.
                // Audio corrections need a compatible frontend/pack; do not substitute IPA
                // into prose or claim current-pack pronunciation parity. It also exposes no
                // G2P for the iOS syllable-respelling preview. JSON remains the source of truth.
                lexicon = if (loadedLexicon.isEmpty()) "" else customLexicon.absolutePath,
                dictDir = ""
            )

            val modelConfig = OfflineTtsModelConfig(
                kokoro = kokoroConfig,
                numThreads = 2,
                debug = false,
                provider = "cpu"
            )

            val config = OfflineTtsConfig(
                model = modelConfig
            )

            tts = OfflineTts(context.assets, config)
            
            // Populate available voices (Kokoro has preset voices based on the bin, we'll try to list them or use indices)
            // Sherpa-onnx doesn't easily expose voices list for Kokoro. Let's just create generic ones or read the bin?
            // Wait, tts?.numSpeakers() might be available!
            val numSpeakers = tts?.numSpeakers() ?: 1
            val voices = (0 until numSpeakers).map {
                TTSVoice(it.toString(), "Voice $it")
            }
            _availableVoices.value = voices
            _status.value = SpeechStatus.STOPPED
        } catch (e: Exception) {
            Log.e("KokoroTTS", "Failed to initialize engine", e)
            failedToOpen = true
            _status.value = SpeechStatus.UNAVAILABLE
        }
    }

    /** Opens the pack if it is not open yet; false when it is missing or will not open. */
    fun ensureReady(): Boolean {
        if (disposed || failedToOpen) return false
        if (tts == null) initEngine()
        return tts != null
    }

    override suspend fun speak(text: String) {
        if (!ensureReady()) return
        
        val previous = synthesisJob
        stop()
        previous?.join() // Native generate may finish after cancellation; never run two generations together.
        if (disposed) return
        // Reopen only between utterances, after cancelled native work has joined. Changes
        // to an existing word's IPA count too, as in iOS's pronunciation revision token.
        withContext(Dispatchers.IO) {
            synchronized(engineLock) {
                if (!disposed && resolvedLexicon() != loadedLexicon) {
                    tts?.release()
                    tts = null
                    initEngine()
                }
            }
        }
        if (disposed || tts == null) return

        _status.value = SpeechStatus.PLAYING
        
        synthesisJob = scope.launch {
            val chunks = TextChunker.chunk(text)
            
            val sampleRate = tts?.sampleRate() ?: 24000
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
                
            val attr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
                
            val minBufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_FLOAT
            )
            
            val track = AudioTrack.Builder()
                .setAudioAttributes(attr)
                .setAudioFormat(format)
                .setBufferSizeInBytes(minBufferSize * 4)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
                
            synchronized(audioLock) {
                audioTrack = track
                track.play()
            }

            try {
                for (chunk in chunks) {
                    if (!isActive) break
                    
                    _spokenText.value = chunk
                    
                    try {
                        val generatedAudio = withContext(Dispatchers.Default) {
                            synchronized(engineLock) { tts?.generate(chunk, currentVoiceId, currentRate) }
                        }
                        
                        val samples = generatedAudio?.samples
                        if (samples == null || samples.isEmpty()) continue
                        
                        if (!isActive) break
                        
                        track.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
                    } catch (e: Exception) {
                        // The kind of failure only: the exception may quote the text being read aloud,
                        // and logcat has no private values (audit A21).
                        Log.e("KokoroTTS", "Error synthesizing chunk: ${e.javaClass.simpleName}")
                    }
                }
            } finally {
                synchronized(audioLock) {
                    track.stop()
                    track.release()
                    if (audioTrack == track) {
                        audioTrack = null
                        if (_status.value == SpeechStatus.PLAYING) {
                            _status.value = SpeechStatus.STOPPED
                        }
                    }
                }
            }
        }
        synthesisJob?.join()
    }

    override fun pause() {
        if (_status.value == SpeechStatus.PLAYING) {
            synchronized(audioLock) { audioTrack?.pause() }
            _status.value = SpeechStatus.PAUSED
        }
    }

    override fun resume() {
        if (_status.value == SpeechStatus.PAUSED) {
            synchronized(audioLock) { audioTrack?.play() }
            _status.value = SpeechStatus.PLAYING
        }
    }

    override fun stop() {
        synthesisJob?.cancel()
        synchronized(audioLock) {
            audioTrack?.stop()
            // The synthesis job's finally owns release; releasing here races its write/finally.
            audioTrack = null
        }
        _status.value = SpeechStatus.STOPPED
        _spokenText.value = ""
    }

    /** Wait for outstanding native synthesis before releasing the model. No new work after disposal. */
    fun shutdown() {
        if (disposed) return
        disposed = true
        val job = synthesisJob
        stop()
        scope.launch {
            job?.cancelAndJoin()
            try {
                synchronized(engineLock) {
                    tts?.release()
                    tts = null
                    lexiconFile?.delete()
                    lexiconFile = null
                }
            } finally {
                scope.cancel()
            }
        }
    }

    override fun setVoice(id: String) {
        currentVoiceId = availableVoices.value.firstOrNull { it.id == id }?.id?.toIntOrNull() ?: 0
    }

    override fun setRate(rate: Float) {
        currentRate = ReaderSpeechPreferences.clampRate(rate)
    }

    override fun setPitch(pitch: Float) {
        // No-op for Kokoro
    }
}
