package io.github.cidy02.kudos.reader.speech

import kotlinx.coroutines.flow.StateFlow

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
}
