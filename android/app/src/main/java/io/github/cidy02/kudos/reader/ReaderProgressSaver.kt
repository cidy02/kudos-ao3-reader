package io.github.cidy02.kudos.reader

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

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
    private val writing = Mutex()

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

    /**
     * A save, once begun, finishes, and a flush waits for it. The debounced job used to take
     * the value out of [pending] and then suspend in the database: a flush in that moment
     * cancelled it, found nothing pending and wrote nothing, so leaving the reader lost the
     * last page turn (audit A5-1). iOS keeps the latest locator across the cancel and writes
     * it before its flush returns.
     */
    private suspend fun flushPending() = withContext(NonCancellable) {
        writing.withLock {
            val toSave = pending ?: return@withLock
            pending = null
            save(toSave)
        }
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MS = 1500L
    }
}
