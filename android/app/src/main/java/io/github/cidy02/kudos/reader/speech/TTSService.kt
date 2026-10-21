package io.github.cidy02.kudos.reader.speech

import kotlinx.coroutines.flow.StateFlow
import io.github.cidy02.kudos.reader.settings.ReaderPreferences

data class TTSVoice(val id: String, val name: String)

interface TTSService {
    val status: StateFlow<SpeechStatus>
    val spokenText: StateFlow<String>
    val availableVoices: StateFlow<List<TTSVoice>>

    suspend fun speak(text: String)
    fun pause()
    fun resume()
    fun stop()
    fun setVoice(id: String)
    fun setRate(rate: Float)
    fun setPitch(pitch: Float)
    /** Which fandom's and work's pronunciation corrections apply (Kokoro only). */
    fun setPronunciationScope(fandom: String?, workID: String?) {}
    /**
     * Settings › Listening's Engine ([io.github.cidy02.kudos.reader.settings.ReaderTTSEngineKind]
     * raw value, "" for Automatic). Only [AutomaticTTSService] has more than one engine to choose.
     */
    fun setEngine(engine: String) = Unit
    fun ensureReady(): Boolean = status.value != SpeechStatus.UNAVAILABLE
    fun shutdown() = Unit
}

/** Shared application path for the reader and Settings' sample playback. */
fun TTSService.applySpeechPreferences(preferences: ReaderPreferences) {
    setEngine(preferences.speechEngine)
    setRate(preferences.speechRate)
    setPitch(preferences.speechPitch)
    setVoice(preferences.speechVoiceIdentifier ?: "0")
}
