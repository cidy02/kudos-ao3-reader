package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import androidx.lifecycle.asFlow
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

enum class SpeechStatus {
    UNAVAILABLE,
    STOPPED,
    PLAYING,
    PAUSED,
    MODEL_NOT_DOWNLOADED
}

/**
 * Android Text-to-Speech read-aloud with MediaSession lock-screen / notification
 * transport. Port of Apple `ReaderSpeechController` + `MPRemoteCommandCenter`.
 */
class ReaderSpeechController(
    private val context: Context,
    private val onUtteranceStart: ((String) -> Unit)? = null
) {
    private val appContext = context.applicationContext
    private val tts = KokoroTTSController(appContext)
    
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private val _status = MutableStateFlow(SpeechStatus.STOPPED)
    val status: StateFlow<SpeechStatus> = _status.asStateFlow()

    val spokenText: StateFlow<String> = tts.spokenText

    val availableVoices: StateFlow<List<TTSVoice>> = tts.availableVoices

    private val _downloadProgress = MutableStateFlow<Float?>(null)
    val downloadProgress: StateFlow<Float?> = _downloadProgress.asStateFlow()

    private var currentQueue: List<String> = emptyList()
    private var currentIndex = 0
    private var currentPreferences = ReaderPreferences()
    private var workTitle: String = "Kudos"
    private var currentSpeakJob: Job? = null

    private val mediaSession: MediaSession = MediaSession(appContext, "kudos.reader.tts").apply {
        setCallback(object : MediaSession.Callback() {
            override fun onPlay() {
                if (_status.value == SpeechStatus.PAUSED) resume()
            }

            override fun onPause() {
                pause()
            }

            override fun onStop() {
                stop()
            }

            override fun onSkipToNext() {
                skipForward()
            }

            override fun onSkipToPrevious() {
                skipBackward()
            }
        })
        isActive = true
    }

    init {
        scope.launch {
            tts.status.collect { ttsStatus ->
                // Map the inner TTS service status to the controller's status, except when we override it
                if (ttsStatus == SpeechStatus.UNAVAILABLE && !TTSDownloadWorker.isModelDownloaded(appContext)) {
                    _status.value = SpeechStatus.MODEL_NOT_DOWNLOADED
                } else if (_status.value != SpeechStatus.MODEL_NOT_DOWNLOADED) {
                    _status.value = ttsStatus
                    if (ttsStatus == SpeechStatus.STOPPED && currentIndex < currentQueue.size) {
                        // The chunk finished playing. We should speak the next one.
                        // Actually, tts.speak() is suspending and blocks until done, so we handle sequencing in speakCurrent().
                    }
                }
            }
        }
        
        scope.launch {
            WorkManager.getInstance(appContext)
                .getWorkInfosForUniqueWorkFlow("TTSDownloadWorker")
                .collectLatest { infos ->
                    val info = infos.firstOrNull()
                    if (info != null && info.state == WorkInfo.State.RUNNING) {
                        val p = info.progress.getFloat(TTSDownloadWorker.KEY_PROGRESS, -1f)
                        _downloadProgress.value = if (p >= 0f) p else null
                    } else if (info != null && info.state.isFinished) {
                        _downloadProgress.value = null
                        if (TTSDownloadWorker.isModelDownloaded(appContext)) {
                            _status.value = SpeechStatus.STOPPED
                        }
                    }
                }
        }

        if (!TTSDownloadWorker.isModelDownloaded(appContext)) {
            _status.value = SpeechStatus.MODEL_NOT_DOWNLOADED
        }
    }

    fun enqueueDownload() {
        TTSDownloadWorker.enqueue(appContext)
        _status.value = SpeechStatus.MODEL_NOT_DOWNLOADED
    }

    fun configure(preferences: ReaderPreferences, title: String = workTitle) {
        currentPreferences = preferences
        workTitle = title.ifBlank { "Kudos" }
        tts.setRate(preferences.speechRate)
        tts.setPitch(preferences.speechPitch)
        applyVoicePreference()
        updateMetadata()
    }

    fun startReading(paragraphs: List<String>) {
        if (paragraphs.isEmpty()) return
        if (_status.value == SpeechStatus.MODEL_NOT_DOWNLOADED) return
        
        currentQueue = paragraphs
        currentIndex = 0
        updateMetadata()
        speakCurrent()
    }

    fun skipForward() {
        if (currentIndex + 1 < currentQueue.size) {
            currentIndex++
            speakCurrent()
        } else {
            stop()
        }
    }

    fun skipBackward() {
        if (currentIndex > 0) {
            currentIndex--
            speakCurrent()
        } else if (currentQueue.isNotEmpty()) {
            speakCurrent()
        }
    }

    private fun applyVoicePreference() {
        val id = currentPreferences.speechVoiceIdentifier
        if (id != null) {
            tts.setVoice(id)
        }
    }

    private fun speakCurrent() {
        if (currentIndex >= currentQueue.size) {
            _status.value = SpeechStatus.STOPPED
            publishPlaybackState(PlaybackState.STATE_STOPPED)
            return
        }
        
        currentSpeakJob?.cancel()
        currentSpeakJob = scope.launch(Dispatchers.Default) {
            val text = currentQueue[currentIndex]
            tts.setRate(currentPreferences.speechRate)
            tts.setPitch(currentPreferences.speechPitch)
            onUtteranceStart?.invoke("utt_$currentIndex")
            publishPlaybackState(PlaybackState.STATE_PLAYING)
            
            tts.speak(text)
            
            launch(Dispatchers.Main) {
                currentIndex++
                if (currentIndex < currentQueue.size) {
                    speakCurrent()
                } else {
                    _status.value = SpeechStatus.STOPPED
                    publishPlaybackState(PlaybackState.STATE_STOPPED)
                }
            }
        }
    }

    fun pause() {
        if (_status.value == SpeechStatus.PLAYING) {
            tts.pause()
            _status.value = SpeechStatus.PAUSED
            publishPlaybackState(PlaybackState.STATE_PAUSED)
        }
    }

    fun resume() {
        if (_status.value == SpeechStatus.PAUSED) {
            tts.resume()
            _status.value = SpeechStatus.PLAYING
            publishPlaybackState(PlaybackState.STATE_PLAYING)
        }
    }

    fun stop() {
        currentSpeakJob?.cancel()
        currentSpeakJob = null
        tts.stop()
        _status.value = SpeechStatus.STOPPED
        publishPlaybackState(PlaybackState.STATE_STOPPED)
    }

    fun shutdown() {
        currentSpeakJob?.cancel()
        scope.cancel()
        tts.stop()
        mediaSession.isActive = false
        mediaSession.release()
    }

    private fun updateMetadata() {
        val builder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, workTitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, workTitle)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "Kudos")
        mediaSession.setMetadata(builder.build())
    }

    private fun publishPlaybackState(state: Int) {
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS
        val playback = PlaybackState.Builder()
            .setActions(actions)
            .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f)
            .build()
        mediaSession.setPlaybackState(playback)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaSession.setPlaybackToLocal(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
        }
    }
}
