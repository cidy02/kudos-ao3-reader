package io.github.cidy02.kudos.network.ao3.writing.recovery

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class WritingCheckpointPolicy(val idleDelay: Long = 1_500, val maxInterval: Long = 20_000) {
    fun deadline(lastEdit: Long, firstPendingEdit: Long): Long =
        minOf(lastEdit + idleDelay, firstPendingEdit + maxInterval)
}

/** Confined to the owner's thread, like iOS's MainActor. Clock returns monotonic milliseconds. */
class WritingCheckpointScheduler(
    private val scope: CoroutineScope,
    private val clock: () -> Long,
    private val policy: WritingCheckpointPolicy = WritingCheckpointPolicy(),
    private val checkpoint: () -> Unit,
) {
    private var firstPendingEdit: Long? = null
    private var lastEdit: Long? = null
    private var timer: Job? = null
    var checkpointCount: Int = 0
        private set

    /** O(1): no text, disk, digest or word count on the edit path. */
    fun noteEdit() {
        val now = clock()
        if (firstPendingEdit == null) firstPendingEdit = now
        lastEdit = now
        // Not `== null`: on an immediate dispatcher a timer that fires at once assigns itself after fireNow cleared it.
        if (timer?.isActive != true) {
            timer = scope.launch {
                while (true) {
                    val first = firstPendingEdit ?: return@launch
                    val last = lastEdit ?: return@launch
                    val remaining = policy.deadline(last, first) - clock()
                    if (remaining <= 0) {
                        fireNow()
                        return@launch
                    }
                    delay(remaining)
                }
            }
        }
    }

    /** Caller handles composition and unchanged text. Fires even with no pending edit. */
    fun fireNow() {
        cancel()
        checkpointCount += 1
        checkpoint()
    }

    fun cancel() {
        timer?.cancel()
        timer = null
        firstPendingEdit = null
        lastEdit = null
    }
}
