package io.github.cidy02.kudos.reader

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Debounces reader progress so rapid location callbacks do not hammer the
 * database. The latest progress wins; [flush] persists any pending value
 * immediately (used on reader close/background).
 */
class ReaderProgressSaver(
    private val scope: CoroutineScope,
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MS,
    private val save: suspend (ReaderProgress) -> Unit
) {
    private var pending: ReaderProgress? = null
    private var job: Job? = null

    fun onProgress(progress: ReaderProgress) {
        pending = progress
        job?.cancel()
        job = scope.launch {
            delay(debounceMillis)
            flushPending()
        }
    }

    suspend fun flush() {
        job?.cancel()
        flushPending()
    }

    private suspend fun flushPending() {
        val toSave = pending ?: return
        pending = null
        save(toSave)
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MS = 1500L
    }
}
