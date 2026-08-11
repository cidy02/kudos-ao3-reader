package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class SpeechStatus {
    UNAVAILABLE,
    STOPPED,
    PLAYING,
    PAUSED
}

/**
 * Android Text-to-Speech read-aloud with MediaSession lock-screen / notification
 * transport. Port of Apple `ReaderSpeechController` + `MPRemoteCommandCenter`.
 */
class ReaderSpeechController(
    context: Context,
    private val onUtteranceStart: ((String) -> Unit)? = null
) : TextToSpeech.OnInitListener {

    private val appContext = context.applicationContext
    private var tts: TextToSpeech? = TextToSpeech(appContext, this)
    private var isInitialized = false

    private val _status = MutableStateFlow(SpeechStatus.STOPPED)
    val status: StateFlow<SpeechStatus> = _status.asStateFlow()

    private val _spokenText = MutableStateFlow("")
    val spokenText: StateFlow<String> = _spokenText.asStateFlow()

    private val _availableVoices = MutableStateFlow<List<Voice>>(emptyList())
    val availableVoices: StateFlow<List<Voice>> = _availableVoices.asStateFlow()

    private var currentQueue: List<String> = emptyList()
    private var currentIndex = 0
    private var currentPreferences = ReaderPreferences()
    private var workTitle: String = "Kudos"

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

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isInitialized = true
            tts?.language = Locale.getDefault()
            _availableVoices.value = tts?.voices?.toList().orEmpty()
            applyVoicePreference()
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    _status.value = SpeechStatus.PLAYING
                    publishPlaybackState(PlaybackState.STATE_PLAYING)
                    onUtteranceStart?.invoke(utteranceId.orEmpty())
                }

                override fun onDone(utteranceId: String?) {
                    speakNext()
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    speakNext()
                }
            })
        } else {
            _status.value = SpeechStatus.UNAVAILABLE
        }
    }

    fun configure(preferences: ReaderPreferences, title: String = workTitle) {
        currentPreferences = preferences
        workTitle = title.ifBlank { "Kudos" }
        if (!isInitialized) return
        tts?.setSpeechRate(preferences.speechRate)
        tts?.setPitch(preferences.speechPitch)
        applyVoicePreference()
        updateMetadata()
    }

    fun startReading(paragraphs: List<String>) {
        if (!isInitialized || paragraphs.isEmpty()) return
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
        val id = currentPreferences.speechVoiceIdentifier ?: return
        val voice = tts?.voices?.firstOrNull { it.name == id } ?: return
        tts?.voice = voice
    }

    private fun speakCurrent() {
        if (currentIndex >= currentQueue.size) {
            _status.value = SpeechStatus.STOPPED
            _spokenText.value = ""
            publishPlaybackState(PlaybackState.STATE_STOPPED)
            return
        }
        val text = currentQueue[currentIndex]
        _spokenText.value = text
        tts?.setSpeechRate(currentPreferences.speechRate)
        tts?.setPitch(currentPreferences.speechPitch)
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "utt_$currentIndex")
        publishPlaybackState(PlaybackState.STATE_PLAYING)
    }

    private fun speakNext() {
        currentIndex++
        if (currentIndex < currentQueue.size) {
            speakCurrent()
        } else {
            _status.value = SpeechStatus.STOPPED
            _spokenText.value = ""
            publishPlaybackState(PlaybackState.STATE_STOPPED)
        }
    }

    fun pause() {
        if (_status.value == SpeechStatus.PLAYING) {
            tts?.stop()
            _status.value = SpeechStatus.PAUSED
            publishPlaybackState(PlaybackState.STATE_PAUSED)
        }
    }

    fun resume() {
        if (_status.value == SpeechStatus.PAUSED && currentIndex < currentQueue.size) {
            speakCurrent()
        }
    }

    fun stop() {
        tts?.stop()
        _status.value = SpeechStatus.STOPPED
        _spokenText.value = ""
        publishPlaybackState(PlaybackState.STATE_STOPPED)
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        tts = null
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
