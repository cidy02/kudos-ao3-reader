package io.github.cidy02.kudos.reader.settings

/** Device-local speech settings, shared by Listening and the reader; not a backup DTO. */
data class ReaderSpeechPreferences(
    val rate: Float = DEFAULT_RATE,
    val voiceIdentifier: String? = null,
    /** iOS's "Read author's notes" (on unless turned off): off skips a note and its label. */
    val readAuthorNotes: Boolean = true,
    /** iOS `readerSpeechPitch`: 0.75–1.25, 1.0 the engine's own pitch. */
    val pitch: Float = DEFAULT_PITCH,
    /** iOS `readerSpeechEngine`: a [ReaderTTSEngineKind.rawValue], or "" for Automatic. */
    val engine: String = AUTOMATIC_ENGINE
) {
    fun applyTo(preferences: ReaderPreferences): ReaderPreferences = preferences.copy(
        speechRate = rate,
        speechPitch = pitch,
        speechVoiceIdentifier = voiceIdentifier,
        speechEngine = engine
    )

    companion object {
        const val DEFAULT_RATE = 1.0f
        val RATE_RANGE = 0.5f..1.5f
        const val RATE_STEPS = 19 // 0.05 apart, excluding the two endpoints.

        /** iOS ReaderSpeechPreferences.pitchRange / defaultPitch, slider step 0.05. */
        const val DEFAULT_PITCH = 1.0f
        val PITCH_RANGE = 0.75f..1.25f
        const val PITCH_STEPS = 9 // 0.05 apart, excluding the two endpoints.

        /** iOS: an empty engine identifier means Automatic. */
        const val AUTOMATIC_ENGINE = ""

        fun clampRate(rate: Float): Float =
            if (rate.isFinite()) rate.coerceIn(RATE_RANGE) else DEFAULT_RATE

        fun clampPitch(pitch: Float): Float =
            if (pitch.isFinite()) pitch.coerceIn(PITCH_RANGE) else DEFAULT_PITCH

        /**
         * iOS `normalizeEngineID`: an engine this build does not know reads as Automatic, so a
         * removed engine can never block Read Aloud.
         */
        fun normalizeEngine(raw: String?): String =
            ReaderTTSEngineKind.from(raw)?.rawValue ?: AUTOMATIC_ENGINE
    }
}

/**
 * iOS `ReaderTTSEngineKind` (TTSService.swift), in iOS's order. The raw values are iOS's;
 * "Apple" is the device's own voice here. Kokoro runs on the processor, not a Neural Engine,
 * so it is plain "Kokoro".
 */
enum class ReaderTTSEngineKind(val rawValue: String, val displayName: String) {
    SYSTEM("system", "Device voice"),
    KOKORO("kokoro", "Kokoro");

    companion object {
        fun from(raw: String?): ReaderTTSEngineKind? = when (raw) {
            "device" -> SYSTEM
            else -> entries.firstOrNull { it.rawValue == raw }
        }

        /** iOS `preferred(modelDownloaded:)`: Automatic. */
        fun preferred(modelDownloaded: Boolean): ReaderTTSEngineKind =
            if (modelDownloaded) KOKORO else SYSTEM

        /**
         * iOS `effective(requestedRawValue:modelDownloaded:)`: Kokoro is never used until its
         * pack is here, and then reads with the device's voice instead.
         */
        fun effective(requestedRawValue: String?, modelDownloaded: Boolean): ReaderTTSEngineKind =
            when (from(requestedRawValue)) {
                null -> preferred(modelDownloaded)
                SYSTEM -> SYSTEM
                KOKORO -> if (modelDownloaded) KOKORO else SYSTEM
            }
    }
}
