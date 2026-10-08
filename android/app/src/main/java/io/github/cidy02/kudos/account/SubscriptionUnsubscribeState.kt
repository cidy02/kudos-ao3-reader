package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A visible screen's confirmed write. Construction/staging never make requests. */
internal class SubscriptionUnsubscribeState(
    private val repository: AO3WriteRepository,
    private val auth: AO3AuthRepository
) {
    private val generation = auth.generation.value
    private val mutableBusyPath = MutableStateFlow<String?>(null)
    val busyPath = mutableBusyPath.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    fun dismissError() { mutableError.value = null }

    /** Called only by the destructive confirmation's confirm button. */
    suspend fun confirm(path: String, page: Int, onSuccess: () -> Unit) =
        confirmWrite(path, { repository.unsubscribe(path, page) }, onSuccess)

    /** One row of AO3's reading history, by the id its own delete form carries. */
    suspend fun confirmDeleteReading(readingId: Long, page: Int, onSuccess: () -> Unit) =
        confirmWrite("reading:$readingId", { repository.deleteReading(readingId, page) }, onSuccess)

    /** One write at a time for this screen and this session; the row changes only on AO3's confirmation. */
    private suspend fun confirmWrite(key: String, write: suspend () -> AO3Result<*>, onSuccess: () -> Unit) {
        if (mutableBusyPath.value != null || generation != auth.generation.value) return
        mutableBusyPath.value = key
        try {
            val result = write()
            currentCoroutineContext().ensureActive()
            if (generation != auth.generation.value) return
            when (result) {
                is AO3Result.Success -> onSuccess()
                is AO3Result.Failure -> mutableError.value = result.error.displayMessage()
            }
        } catch (_: CancellationException) {
            // A completed POST belongs to its original session and screen only.
        } finally {
            mutableBusyPath.value = null
        }
    }
}
