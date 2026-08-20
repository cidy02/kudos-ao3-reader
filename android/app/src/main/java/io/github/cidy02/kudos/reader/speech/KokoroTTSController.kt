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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class KokoroTTSController(private val context: Context) : TTSService {
    private val scope = CoroutineScope(Dispatchers.Default + Job())
    private var tts: OfflineTts? = null
    
    private val _status = MutableStateFlow(SpeechStatus.UNAVAILABLE)
    override val status: StateFlow<SpeechStatus> = _status.asStateFlow()

    private val _spokenText = MutableStateFlow("")
    override val spokenText: StateFlow<String> = _spokenText.asStateFlow()

    private val _availableVoices = MutableStateFlow<List<TTSVoice>>(emptyList())
    override val availableVoices: StateFlow<List<TTSVoice>> = _availableVoices.asStateFlow()

    private var audioTrack: AudioTrack? = null
    private var synthesisJob: Job? = null
    private var currentRate: Float = 1.0f
    private var currentVoiceId: Int = 0

    init {
        initEngine()
    }

    private fun initEngine() {
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

            val kokoroConfig = OfflineTtsKokoroModelConfig(
                model = modelPath,
                voices = voicesPath,
                tokens = tokensPath,
                dataDir = dataDir,
                lengthScale = 1.0f,
                lexicon = "",
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
            _status.value = SpeechStatus.UNAVAILABLE
        }
    }

    override suspend fun speak(text: String) {
        if (tts == null) {
            initEngine()
            if (tts == null) return
        }
        
        stop() // Stop any current speech
        
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
                
            audioTrack = track
            track.play()

            try {
                for (chunk in chunks) {
                    if (!isActive) break
                    
                    _spokenText.value = chunk
                    
                    try {
                        val generatedAudio = withContext(Dispatchers.Default) {
                            tts?.generate(chunk, currentVoiceId, currentRate)
                        }
                        
                        val samples = generatedAudio?.samples
                        if (samples == null || samples.isEmpty()) continue
                        
                        if (!isActive) break
                        
                        track.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
                    } catch (e: Exception) {
                        Log.e("KokoroTTS", "Error synthesizing chunk", e)
                    }
                }
            } finally {
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
        synthesisJob?.join()
    }

    override fun pause() {
        if (_status.value == SpeechStatus.PLAYING) {
            audioTrack?.pause()
            _status.value = SpeechStatus.PAUSED
        }
    }

    override fun resume() {
        if (_status.value == SpeechStatus.PAUSED) {
            audioTrack?.play()
            _status.value = SpeechStatus.PLAYING
        }
    }

    override fun stop() {
        synthesisJob?.cancel()
        synthesisJob = null
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        _status.value = SpeechStatus.STOPPED
        _spokenText.value = ""
    }

    override fun setVoice(id: String) {
        currentVoiceId = id.toIntOrNull() ?: 0
    }

    override fun setRate(rate: Float) {
        currentRate = rate.coerceIn(0.5f, 2.0f)
    }

    override fun setPitch(pitch: Float) {
        // No-op for Kokoro
    }
}
