package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSettingsPage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class ChallengeSettingsUiState(
    val data: AO3ChallengeSettingsPage? = null,
    val loading: Boolean = false,
    val failure: String? = null
)

/** Foreground read owned by one visible screen and one authentication generation. */
internal class AO3ChallengeSettingsState(private val slug: String, private val repository: AO3CollectionDetailRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var loadJob: Job? = null
    private val mutable = MutableStateFlow(ChallengeSettingsUiState())
    val state = mutable.asStateFlow()

    fun close() { active = false; loadJob?.cancel() }

    suspend fun load() {
        if (!active || generation != auth.generation.value || state.value.loading) return
        if (!auth.state.value.isSignedIn) {
            mutable.value = ChallengeSettingsUiState(failure = "Log in to AO3 before using this feature.")
            return
        }
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            val result = repository.getChallengeSettings(slug)
            currentCoroutineContext().ensureActive()
            if (!active || generation != auth.generation.value) return
            mutable.value = when (result) {
                is AO3Result.Success -> ChallengeSettingsUiState(data = result.value)
                is AO3Result.Failure -> state.value.copy(loading = false, failure = result.error.moderationMessage())
            }
        } catch (e: CancellationException) {
            if (active && generation == auth.generation.value) mutable.value = state.value.copy(loading = false)
            throw e
        } finally { loadJob = null }
    }
}
