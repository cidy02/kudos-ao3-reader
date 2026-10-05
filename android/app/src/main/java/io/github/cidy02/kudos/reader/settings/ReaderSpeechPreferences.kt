package io.github.cidy02.kudos.reader.settings

/** Device-local speech settings, shared by Listening and the reader; not a backup DTO. */
data class ReaderSpeechPreferences(
    val rate: Float = DEFAULT_RATE,
    val voiceIdentifier: String? = null
) {
    fun applyTo(preferences: ReaderPreferences): ReaderPreferences = preferences.copy(
        speechRate = rate,
        speechVoiceIdentifier = voiceIdentifier
    )

    companion object {
        const val DEFAULT_RATE = 1.0f
        val RATE_RANGE = 0.5f..1.5f
        const val RATE_STEPS = 19 // 0.05 apart, excluding the two endpoints.

        fun clampRate(rate: Float): Float =
            if (rate.isFinite()) rate.coerceIn(RATE_RANGE) else DEFAULT_RATE
    }
}
