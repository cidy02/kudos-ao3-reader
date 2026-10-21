package io.github.cidy02.kudos.reader.speech

import androidx.work.WorkInfo

/**
 * What Settings › Listening shows for the Kokoro pack: iOS `TTSDownloadManager.Status` as
 * `ReaderSpeechSettingsSection.packStatusViews` draws it (idle, downloading, extracting,
 * cancelling, completed, failed), read from [TTSDownloadWorker]'s WorkManager state, the same
 * work the reader starts and watches.
 */
sealed interface VoicePackState {
    /** iOS `.idle`: "Download Voice Pack". */
    data object NotDownloaded : VoicePackState
    /** iOS `.downloading(progress)`: a bar, "Downloading... N%" and Cancel. Queued work is 0%. */
    data class Downloading(val progress: Float) : VoicePackState
    /** iOS `.extracting`: "Extracting..." with Cancel. */
    data object Extracting : VoicePackState
    /** iOS `.cancelling`: "Cancelling…" until the work has stopped. */
    data object Cancelling : VoicePackState
    /** iOS `.completed`: "Voice Pack Downloaded" with a check. */
    data object Downloaded : VoicePackState
    /** iOS `.failed(error)`: the error, then "Retry Download". */
    data class Failed(val message: String) : VoicePackState

    companion object {
        /** The reader's wording for a failure the worker gave no reason for. */
        const val DEFAULT_FAILURE = "Could not download the voice pack."

        fun from(info: WorkInfo?, installed: Boolean, cancelling: Boolean): VoicePackState = from(
            state = info?.state,
            phase = info?.progress?.getString(TTSDownloadWorker.KEY_PHASE),
            progress = info?.progress?.getFloat(TTSDownloadWorker.KEY_PROGRESS, -1f) ?: -1f,
            error = info?.outputData?.getString(TTSDownloadWorker.KEY_ERROR),
            installed = installed,
            cancelling = cancelling
        )

        /**
         * Work under way wins (a reader may have started it); then the pack on disk; then a
         * failed attempt; else nothing yet. A cancelled download is nothing yet, as on iOS.
         */
        fun from(
            state: WorkInfo.State?,
            phase: String?,
            progress: Float,
            error: String?,
            installed: Boolean,
            cancelling: Boolean
        ): VoicePackState = when {
            state != null && !state.isFinished -> when {
                cancelling -> Cancelling
                state == WorkInfo.State.RUNNING && phase == "extracting" -> Extracting
                state == WorkInfo.State.RUNNING -> Downloading(if (progress >= 0f) progress.coerceAtMost(1f) else 0f)
                else -> Downloading(0f) // ENQUEUED or BLOCKED, as ReaderSpeechController reads them.
            }
            installed -> Downloaded
            state == WorkInfo.State.FAILED -> Failed(error?.takeIf { it.isNotBlank() } ?: DEFAULT_FAILURE)
            else -> NotDownloaded
        }
    }
}
