package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetSnapshot
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class TagSetUiState(
    val data: AO3TagSetSnapshot? = null,
    val loading: Boolean = false,
    val failure: String? = null
)

/** One foreground page load, fenced to its opening session even when it is public. */
internal class AO3TagSetState(private val id: Int, private val repository: AO3CollectionDetailRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var loadJob: Job? = null
    private val mutable = MutableStateFlow(TagSetUiState())
    val state = mutable.asStateFlow()

    fun close() { active = false; loadJob?.cancel() }

    suspend fun load() {
        if (!active || generation != auth.generation.value || state.value.loading) return
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            val result = repository.getTagSet(id)
            currentCoroutineContext().ensureActive()
            if (!active || generation != auth.generation.value) return
            mutable.value = when (result) {
                is AO3Result.Success -> TagSetUiState(data = result.value)
                is AO3Result.Failure -> state.value.copy(loading = false, failure = result.error.moderationMessage())
            }
        } catch (e: CancellationException) {
            if (active && generation == auth.generation.value) mutable.value = state.value.copy(loading = false)
            throw e
        } finally { loadJob = null }
    }
}
