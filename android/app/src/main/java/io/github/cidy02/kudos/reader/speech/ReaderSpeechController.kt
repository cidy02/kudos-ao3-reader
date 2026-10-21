package io.github.cidy02.kudos.reader.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.github.cidy02.kudos.reader.ReaderPlaybackClock
import io.github.cidy02.kudos.reader.ReaderSpeechSource
import io.github.cidy02.kudos.reader.ReaderTimeEstimate
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    private val onUtteranceStart: ((String) -> Unit)? = null,
    private val tts: TTSService = AutomaticTTSService(context.applicationContext)
) {
    private val appContext = context.applicationContext
    
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private val _status = MutableStateFlow(SpeechStatus.STOPPED)
    val status: StateFlow<SpeechStatus> = _status.asStateFlow()

    private val seekPreview = MutableStateFlow<String?>(null)
    val spokenText: StateFlow<String> = combine(tts.spokenText, seekPreview) { spoken, preview -> preview ?: spoken }
        .stateIn(scope, SharingStarted.Eagerly, "")

    val availableVoices: StateFlow<List<TTSVoice>> = tts.availableVoices

    private val _downloadProgress = MutableStateFlow<Float?>(null)
    val downloadProgress: StateFlow<Float?> = _downloadProgress.asStateFlow()

    private val _downloadFailure = MutableStateFlow<String?>(null)
    val downloadFailure: StateFlow<String?> = _downloadFailure.asStateFlow()

    private val currentQueue = mutableListOf<String>()
    private var source: ReaderSpeechSource? = null
    private var pausedAtQueuePosition = false
    private var seekWasPlaying = false
    private var pullingParagraph = false
    private var currentIndex = 0
    private var currentPreferences = ReaderPreferences()
    private var workTitle: String = "Kudos"
    private var currentSpeakJob: Job? = null
    private var restartAfterPull: Job? = null
    private var totalPositions = 0
    private var currentPosition: Int? = null
    private var playbackState = PlaybackState.STATE_STOPPED
    private val playbackClock = ReaderPlaybackClock()

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
                // No voice at all, neither the device's nor a downloaded one: the reader offers
                // the Kokoro pack. It used to be offered, and reading refused, whenever the pack
                // was missing, however good the device's own voice.
                if (pausedAtQueuePosition ||
                    (ttsStatus == SpeechStatus.STOPPED && currentSpeakJob?.isActive == true)) return@collect
                _status.value = if (ttsStatus == SpeechStatus.UNAVAILABLE &&
                    !TTSDownloadWorker.isModelDownloaded(appContext)) SpeechStatus.MODEL_NOT_DOWNLOADED else ttsStatus
            }
        }
        
        scope.launch {
            WorkManager.getInstance(appContext)
                .getWorkInfosForUniqueWorkFlow(TTSDownloadWorker.WORK_NAME)
                .collectLatest { infos ->
                    val info = infos.firstOrNull()
                    if (info != null && info.state == WorkInfo.State.RUNNING) {
                        val p = info.progress.getFloat(TTSDownloadWorker.KEY_PROGRESS, -1f)
                        _downloadProgress.value = if (p >= 0f) p else 0f
                        _downloadFailure.value = null
                    } else if (info?.state == WorkInfo.State.ENQUEUED || info?.state == WorkInfo.State.BLOCKED) {
                        _downloadProgress.value = 0f
                        _downloadFailure.value = null
                    } else if (info != null && info.state.isFinished) {
                        _downloadProgress.value = null
                        _downloadFailure.value = if (info.state == WorkInfo.State.FAILED)
                            info.outputData.getString(TTSDownloadWorker.KEY_ERROR) ?: "Could not download the voice pack." else null
                        // Only a player waiting for the pack is ready now; a reading under way
                        // goes on (A49 F3: it was marked stopped while the device spoke).
                        if (TTSDownloadWorker.isModelDownloaded(appContext) &&
                            _status.value == SpeechStatus.MODEL_NOT_DOWNLOADED) {
                            _status.value = SpeechStatus.STOPPED
                        }
                    }
                }
        }
    }

    fun enqueueDownload() {
        _downloadFailure.value = null
        _downloadProgress.value = 0f
        TTSDownloadWorker.enqueue(appContext)
    }

    fun cancelDownload() {
        WorkManager.getInstance(appContext).cancelUniqueWork(TTSDownloadWorker.WORK_NAME)
    }

    fun configure(preferences: ReaderPreferences, title: String = workTitle) {
        currentPreferences = preferences
        workTitle = title.ifBlank { "Kudos" }
        tts.applySpeechPreferences(preferences)
        updateMetadata()
        publishPlaybackState(playbackState)
    }

    fun updateReadingPosition(total: Int, position: Int?) {
        totalPositions = total.coerceAtLeast(0)
        currentPosition = position
        playbackClock.reset()
        updateMetadata()
        publishPlaybackState(playbackState)
    }

    private fun timing() = ReaderTimeEstimate.ttsNowPlayingTiming(
        totalPositions = totalPositions,
        remainingPositions = totalPositions - (currentPosition ?: 0).coerceIn(0, totalPositions),
        rate = currentPreferences.speechRate.toDouble()
    )

    fun startReading(paragraphs: List<String>) {
        val iterator = paragraphs.iterator()
        startReading(ReaderSpeechSource { if (iterator.hasNext()) iterator.next() else null })
    }

    fun startReading(paragraphs: ReaderSpeechSource) {
        if (_status.value == SpeechStatus.MODEL_NOT_DOWNLOADED) return
        stop()
        currentQueue.clear()
        source = paragraphs
        currentIndex = 0
        playbackClock.reset()
        updateMetadata()
        speakCurrent()
    }

    fun skipForward() {
        currentIndex++
        restartAfterSkip()
    }

    fun skipBackward() {
        currentIndex = (currentIndex - 1).coerceAtLeast(0)
        restartAfterSkip()
    }

    private fun restartAfterSkip() {
        if (!pullingParagraph) {
            speakCurrent()
            return
        }
        // The IO source may already have taken its text. Queue it before restarting.
        pausedAtQueuePosition = true
        _status.value = SpeechStatus.PLAYING
        if (restartAfterPull?.isActive == true) return
        val pull = currentSpeakJob
        restartAfterPull = scope.launch {
            pull?.join()
            if (pausedAtQueuePosition && _status.value == SpeechStatus.PLAYING) speakCurrent()
        }
    }

    fun beginSeeking() {
        seekWasPlaying = _status.value == SpeechStatus.PLAYING
        pausedAtQueuePosition = true
        // Let an in-flight paragraph pull finish so seeking cannot drop its text.
        tts.stop()
        seekPreview.value = currentQueue.getOrNull(currentIndex)
        _status.value = SpeechStatus.PAUSED
        publishPlaybackState(PlaybackState.STATE_PAUSED)
    }

    /** Re-anchor to the reader's release locator, preserving a paused session as on iOS. */
    fun endSeeking(paragraphs: ReaderSpeechSource) {
        if (!pausedAtQueuePosition) return
        val resumePlaying = seekWasPlaying
        stop()
        currentQueue.clear()
        source = paragraphs
        currentIndex = 0
        pausedAtQueuePosition = true
        _status.value = SpeechStatus.PAUSED
        publishPlaybackState(PlaybackState.STATE_PAUSED)
        if (resumePlaying) speakCurrent()
    }

    private suspend fun nextParagraph(): String? {
        pullingParagraph = true
        return try {
            source?.next()
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        } finally {
            pullingParagraph = false
        }
    }

    private fun speakCurrent() {
        currentSpeakJob?.cancel()
        tts.stop()
        pausedAtQueuePosition = false
        seekPreview.value = null
        _status.value = SpeechStatus.PLAYING
        currentSpeakJob = scope.launch {
            while (true) {
                while (currentIndex >= currentQueue.size) {
                    val next = nextParagraph()
                    if (next == null) {
                        source = null
                        if (pausedAtQueuePosition) return@launch
                        _status.value = SpeechStatus.STOPPED
                        publishPlaybackState(PlaybackState.STATE_STOPPED)
                        return@launch
                    }
                    currentQueue.add(next)
                    if (pausedAtQueuePosition) return@launch
                }
                if (pausedAtQueuePosition) return@launch
                val text = currentQueue[currentIndex]
                tts.setRate(currentPreferences.speechRate)
                tts.setPitch(currentPreferences.speechPitch)
                onUtteranceStart?.invoke("utt_$currentIndex")
                publishPlaybackState(PlaybackState.STATE_PLAYING)
                // Pack checks and a newly downloaded Kokoro model may perform blocking IO.
                withContext(Dispatchers.Default) { tts.speak(text) }
                if (pausedAtQueuePosition) return@launch
                currentIndex++
            }
        }
    }

    fun pause() {
        if (_status.value == SpeechStatus.PLAYING) {
            if (pullingParagraph) {
                // No engine owns the next paragraph yet; park it before it can start speaking.
                pausedAtQueuePosition = true
                tts.stop()
            } else {
                tts.pause()
            }
            _status.value = SpeechStatus.PAUSED
            publishPlaybackState(PlaybackState.STATE_PAUSED)
        }
    }

    fun resume() {
        if (_status.value == SpeechStatus.PAUSED) {
            if (pausedAtQueuePosition) {
                val seeking = currentSpeakJob
                scope.launch {
                    seeking?.join()
                    if (pausedAtQueuePosition && _status.value == SpeechStatus.PAUSED) speakCurrent()
                }
                return
            }
            tts.resume()
            _status.value = SpeechStatus.PLAYING
            publishPlaybackState(PlaybackState.STATE_PLAYING)
        }
    }

    fun stop() {
        restartAfterPull?.cancel()
        restartAfterPull = null
        currentSpeakJob?.cancel()
        currentSpeakJob = null
        tts.stop()
        source = null
        pausedAtQueuePosition = false
        seekWasPlaying = false
        seekPreview.value = null
        _status.value = SpeechStatus.STOPPED
        publishPlaybackState(PlaybackState.STATE_STOPPED)
    }

    fun shutdown() {
        restartAfterPull?.cancel()
        currentSpeakJob?.cancel()
        scope.cancel()
        (tts as? AutomaticTTSService)?.shutdown()
        mediaSession.isActive = false
        mediaSession.release()
    }

    private fun updateMetadata() {
        val builder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, workTitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, workTitle)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "Kudos")
        timing()?.let { builder.putLong(MediaMetadata.METADATA_KEY_DURATION, (it.duration * 1000).toLong()) }
        mediaSession.setMetadata(builder.build())
    }

    private fun publishPlaybackState(state: Int) {
        playbackState = state
        val timing = playbackClock.update(timing(), state == PlaybackState.STATE_PLAYING, SystemClock.elapsedRealtime())
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS
        val playback = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                state,
                timing?.let { (it.elapsed * 1000).toLong() } ?: PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                if (state == PlaybackState.STATE_PLAYING) 1f else 0f
            )
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
