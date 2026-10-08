package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemePage
import io.github.cidy02.kudos.network.ao3.account.challengeDateText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class PromptMemeUiState(
    val data: AO3PromptMemePage? = null,
    val closeDateText: String = "",
    val loading: Boolean = false,
    val failure: String? = null
)

/** A visible screen owns these remote values and cancels its load on departure/session change. */
internal class AO3PromptMemeState(private val slug: String, private val repository: AO3CollectionDetailRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var loadJob: Job? = null
    private val mutable = MutableStateFlow(PromptMemeUiState())
    val state = mutable.asStateFlow()

    private fun ownsSession() = active && generation == auth.generation.value
    fun close() { active = false; loadJob?.cancel() }

    /** Opening/refresh attempt the schedule once; explicit page/retry loads never do. */
    suspend fun load(page: Int = 1, readSchedule: Boolean = false) {
        if (!ownsSession() || state.value.loading || page < 1) return
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            if (readSchedule && auth.state.value.isSignedIn) {
                val schedule = repository.getChallengeSettingsForm(slug)
                currentCoroutineContext().ensureActive()
                if (!ownsSession()) return
                val raw = when (schedule) {
                    is AO3Result.Success -> schedule.value.dates.getOrNull(1).orEmpty()
                    is AO3Result.Failure -> ""
                }
                mutable.value = state.value.copy(closeDateText = if (raw.isBlank()) "" else "open until ${challengeDateText(raw)}")
            }
            if (!ownsSession()) return
            val result = repository.getPromptMemePrompts(slug, page)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(data = result.value, loading = false, failure = null)
                is AO3Result.Failure -> state.value.copy(loading = false, failure = result.error.moderationMessage())
            }
        } catch (e: CancellationException) {
            if (ownsSession()) mutable.value = state.value.copy(loading = false)
            throw e
        } finally { loadJob = null }
    }
}
