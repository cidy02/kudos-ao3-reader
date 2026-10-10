package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class ChallengeSettingsEditUiState(
    val data: AO3ChallengeSettingsEditPage? = null, val loading: Boolean = false,
    val failure: String? = null, val terminal: Boolean = false, val saving: Boolean = false,
    val notice: String? = null, val confirmReveal: Boolean = false
)

internal class AO3ChallengeSettingsEditState(private val slug: String, private val owner: Boolean,
    private val repository: AO3CollectionDetailRepository, private val writes: AO3WriteRepository) : androidx.lifecycle.ViewModel() {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private val mutable = MutableStateFlow(ChallengeSettingsEditUiState())
    val state = mutable.asStateFlow()
    private var active = true
    private var attempted = false
    private var loadJob: Job? = null
    private var saveJob: Job? = null
    override fun onCleared() { close() }
    private fun ownsSession() = active && auth.generation.value == generation
    fun close() { active = false; loadJob?.cancel(); saveJob?.cancel() }

    suspend fun load(refresh: Boolean = false) {
        if (!ownsSession() || state.value.loading || state.value.saving || state.value.terminal || attempted && !refresh) return
        attempted = true
        if (!auth.state.value.isSignedIn || !owner) {
            mutable.value = state.value.copy(failure = if (!owner) AO3Error.Forbidden.moderationMessage()
                else "Log in to AO3 before using this feature.", terminal = true)
            return
        }
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            val result = repository.getChallengeSettingsEdit(slug)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(data = state.value.data ?: result.value)
                is AO3Result.Failure -> state.value.copy(failure = result.error.moderationMessage(),
                    terminal = result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired)
            }
        } catch (_: CancellationException) {
            // A superseded opening cannot install another account's private form.
        } finally {
            if (active) mutable.value = state.value.copy(loading = false)
            loadJob = null
        }
    }

    fun change(name: String, value: String, collection: Boolean = false) {
        if (!ownsSession() || !owner || state.value.loading || state.value.saving || state.value.terminal) return
        val data = state.value.data ?: return
        mutable.value = state.value.copy(data = if (collection) data.copy(collection = data.collection?.changed(name, value))
            else data.copy(form = data.form.changed(name, value)), notice = null)
    }

    fun cancelReveal() { mutable.value = state.value.copy(confirmReveal = false) }
    fun revealsSomething(): Boolean {
        val form = state.value.data?.collection ?: return false
        return listOf("unrevealed", "anonymous").any { flag ->
            val key = AO3CollectionFields.preference(flag)
            form.copy(changes = emptyMap())[key] == "1" && form[key] == "0"
        }
    }

    suspend fun save(revealConfirmed: Boolean = false) {
        if (!ownsSession() || !owner || state.value.loading || state.value.saving || state.value.terminal) return
        val data = state.value.data ?: return
        if (revealsSomething() && !revealConfirmed) {
            mutable.value = state.value.copy(confirmReveal = true)
            return
        }
        val checked = data.form.validated()
        mutable.value = state.value.copy(data = data.copy(form = checked), notice = null, confirmReveal = false)
        if (!checked.isValid) return
        saveJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(saving = true)
        try {
            // Once the POST is sent, show its verdict even if the preparing session moved on.
            when (val result = writes.saveChallengeSettings(checked, generation)) {
                is AO3Result.Failure -> if (active) {
                    appendError(result.error.moderationMessage())
                    if (result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired)
                        mutable.value = state.value.copy(terminal = true)
                }
                is AO3Result.Success -> if (active) when (val outcome = result.value) {
                    is AO3ChallengeSettingsSaveOutcome.Invalid -> mutable.value = state.value.copy(
                        data = state.value.data?.copy(form = outcome.form))
                    is AO3ChallengeSettingsSaveOutcome.Saved -> {
                        mutable.value = state.value.copy(data = state.value.data?.copy(form = outcome.form), notice = outcome.message)
                        val collection = data.collection
                        val changed = collection != null && listOf("anonymous", "unrevealed", "moderated", "closed").any {
                            val key = AO3CollectionFields.preference(it)
                            collection[key] != collection.copy(changes = emptyMap())[key]
                        }
                        if (changed && collection != null && ownsSession()) {
                            when (val saved = writes.saveChallengeSettings(collection, generation, collectionSwitches = true)) {
                                is AO3Result.Failure -> if (active) appendError(saved.error.moderationMessage())
                                is AO3Result.Success -> if (active) when (val second = saved.value) {
                                    is AO3ChallengeSettingsSaveOutcome.Invalid -> appendError(second.form.generalErrors.firstOrNull()
                                        ?: "AO3 didn't save the collection settings.")
                                    is AO3ChallengeSettingsSaveOutcome.Saved -> mutable.value = state.value.copy(
                                        data = state.value.data?.copy(collection = second.form),
                                        notice = listOfNotNull(state.value.notice, second.message).joinToString(" "))
                                }
                            }
                        }
                    }
                }
            }
        } catch (_: CancellationException) {
            // Before dispatch only; the repository waits for an already sent POST.
        } catch (error: Exception) {
            if (active) appendError(error.message ?: "Couldn't save challenge settings.")
        } finally {
            if (active) mutable.value = state.value.copy(saving = false)
            saveJob = null
        }
    }

    private fun appendError(message: String) {
        val data = state.value.data ?: return
        mutable.value = state.value.copy(data = data.copy(form = data.form.copy(
            generalErrors = (data.form.generalErrors + message).distinct())))
    }
}
