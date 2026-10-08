package io.github.cidy02.kudos.writing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.network.ao3.writing.WritingWordCount
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingCheckpointScheduler
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingRecoveryWriter
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** One field session, confined to main. No auth, repository or network client. */
class WritingEditorSession(
    val editor: WritingNativeTextField,
    private val original: String,
    private val store: WritingTextRecovery,
    account: String,
    target: String,
    field: String,
    private val scope: CoroutineScope,
    clock: () -> Long,
    private val onCheckpoint: (String) -> Unit = {},
    // Test seams exercise the actual scheduling/count fencing without disk/thread timing.
    private val count: suspend (String) -> Int = { withContext(Dispatchers.Default) { WritingWordCount.count(it) } },
    write: (suspend (String, Int) -> Unit)? = null,
) {
    val key = store.fileURL(account, target, field)
    val recoveryURL = store.sessionURL(key)
    private val writer = WritingRecoveryWriter(store, recoveryURL, original)
    private val save: suspend (String, Int) -> Unit = write ?: { value, sequence -> writer.write(value, sequence); Unit }
    private val writes = mutableListOf<Job>()
    private var countedCheckpoint = 0
    private var previewGeneration = 0
    private var finished = false
    var wordCount: Int? by mutableStateOf(null)
        private set
    var error: String? by mutableStateOf(null)
    var recoveries: List<WritingTextRecovery.Copy> by mutableStateOf(emptyList())
        private set
    var selectedRecovery: WritingTextRecovery.Copy? by mutableStateOf(null)
        private set
    var recoveryFormChanged: Boolean by mutableStateOf(false)
        private set
    var isPreviewing by mutableStateOf(false)
        private set
    var previewState: WritingBufferPreview.State? by mutableStateOf(null)
        private set
    var checkpointText = original
        private set

    val scheduler = WritingCheckpointScheduler(scope, clock) { checkpoint() }

    internal val opening: Job

    init {
        editor.onEdited = scheduler::noteEdit
        recount(original, 0)
        opening = scope.launch {
            try {
                recoveries = store.copiesOnOpen(key, recoveryURL, original)
                selectRecovery(recoveries.firstOrNull())
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                this@WritingEditorSession.error = "The local recovery copy could not be read: ${message(error)}"
            }
        }
    }

    private fun checkpoint() {
        val value = editor.takeCheckpoint() ?: return
        checkpointText = value
        onCheckpoint(value)
        val sequence = scheduler.checkpointCount
        writes.removeAll { it.isCompleted }
        writes += scope.launch {
            try { save(value, sequence) } catch (error: Exception) {
                if (error is CancellationException) throw error
                this@WritingEditorSession.error = "Local recovery could not be saved: ${message(error)}"
            }
        }
        recount(value, sequence)
    }

    internal suspend fun awaitWrites() { writes.toList().joinAll() }

    private fun recount(value: String, sequence: Int) {
        countedCheckpoint = sequence
        scope.launch {
            val result = count(value)
            if (countedCheckpoint == sequence) wordCount = result
        }
    }

    fun selectRecovery(copy: WritingTextRecovery.Copy?): Job {
        selectedRecovery = copy
        return scope.launch {
            val changed = copy != null && withContext(Dispatchers.Default) {
                copy.entry.originalDigest != WritingTextRecovery.digest(original)
            }
            if (selectedRecovery == copy) recoveryFormChanged = changed
        }
    }

    fun restore() {
        val copy = selectedRecovery ?: return
        editor.setText(copy.entry.text)
        scheduler.fireNow()
        keepFormText()
    }

    fun keepFormText() { recoveries = emptyList(); selectedRecovery = null }

    fun deleteSelectedCopy(): Job? {
        val copy = selectedRecovery ?: return null
        return scope.launch {
            try {
                store.deleteCopy(copy)
                recoveries = recoveries.filter { it.url != copy.url }
                selectRecovery(recoveries.firstOrNull())
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                this@WritingEditorSession.error = message(error)
            }
        }
    }

    fun togglePreview() {
        previewGeneration++
        if (isPreviewing) { isPreviewing = false; return }
        editor.commitComposition()
        editor.endEditing()
        val value = editor.takeText()
        val generation = previewGeneration
        previewState = null
        isPreviewing = true
        scope.launch {
            val result = withContext(Dispatchers.Default) { WritingBufferPreview.state(value) }
            if (WritingBufferPreview.publishes(generation, previewGeneration, isPreviewing)) previewState = result
        }
    }

    fun done(): String {
        editor.commitComposition()
        scheduler.fireNow()
        return checkpointText
    }

    /** Departure flushes before detaching, and queued writes outlive Compose disposal. */
    fun finish() {
        if (finished) return
        finished = true
        editor.commitComposition()
        scheduler.fireNow()
        scheduler.cancel()
        editor.onEdited = null
        previewGeneration++
        scope.launch { writes.toList().joinAll(); scope.cancel() }
    }

    private fun message(error: Exception): String = error.localizedMessage ?: "The operation could not be completed."
}
