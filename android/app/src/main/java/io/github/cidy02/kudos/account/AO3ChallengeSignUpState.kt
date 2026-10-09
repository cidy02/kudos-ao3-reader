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

internal data class SignUpUiState(
    val form: AO3ChallengeSignUpForm? = null, val loading: Boolean = false,
    val failure: String? = null, val terminal: Boolean = false,
    val saving: Boolean = false, val notice: String? = null,
    val withdrawing: Boolean = false, val withdrawn: Boolean = false
)

internal class AO3ChallengeSignUpState(private val slug: String, private val id: Int?,
    private val repository: AO3CollectionDetailRepository, private val writes: AO3WriteRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private val mutable = MutableStateFlow(SignUpUiState())
    val state = mutable.asStateFlow()
    private var active = true
    private var attempted = false
    private var loadJob: Job? = null
    private var saveJob: Job? = null
    private var withdrawJob: Job? = null
    private fun ownsSession() = active && generation == auth.generation.value
    fun close() { active = false; loadJob?.cancel(); saveJob?.cancel(); withdrawJob?.cancel() }

    suspend fun load(refresh: Boolean = false) {
        if (!ownsSession() || state.value.loading || state.value.saving || state.value.withdrawing || state.value.withdrawn || state.value.terminal || attempted && !refresh) return
        attempted = true // a failed/refused attempt still counts
        if (!auth.state.value.isSignedIn) {
            mutable.value = SignUpUiState(failure = "Log in to AO3 before using this feature.", terminal = true)
            return
        }
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null, notice = null)
        try {
            val result = repository.getChallengeSignUp(slug, id)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(form = state.value.form ?: result.value.withMinimumPrompts(), loading = false)
                is AO3Result.Failure -> state.value.copy(loading = false, failure = result.error.moderationMessage(),
                    terminal = result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired ||
                        result.error is AO3Error.Parse || result.error is AO3Error.Validation)
            }
        } catch (e: CancellationException) {
            if (ownsSession()) mutable.value = state.value.copy(loading = false)
            throw e
        } finally { loadJob = null }
    }

    fun update(prompt: SignUpPrompt) {
        if (ownsSession() && !state.value.saving && !state.value.withdrawing && !state.value.withdrawn && !state.value.loading)
            mutable.value = state.value.copy(form = state.value.form?.update(prompt), notice = null)
    }

    fun add(kind: SignUpPromptKind) {
        val form = state.value.form ?: return
        val max = if (kind == SignUpPromptKind.Request) form.limits?.requests?.last else form.limits?.offers?.last
        if (!ownsSession() || state.value.saving || state.value.withdrawing || state.value.withdrawn || state.value.loading || form.live(kind).size >= (max ?: Int.MAX_VALUE)) return
        val draft = SignUpPrompt(form.nextDraftID, kind)
        mutable.value = state.value.copy(form = if (kind == SignUpPromptKind.Request) form.copy(requests = form.requests + draft)
            else form.copy(offers = form.offers + draft), notice = null)
    }

    suspend fun save() {
        val form = state.value.form ?: return
        if (!ownsSession() || state.value.saving || state.value.withdrawing || state.value.withdrawn || state.value.loading || state.value.terminal) return
        val checked = form.validated()
        if (!checked.isValid) { mutable.value = state.value.copy(form = checked, notice = null); return }
        saveJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(saving = true, notice = null)
        try {
            val result = writes.saveChallengeSignUp(checked, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Failure -> state.value.copy(saving = false,
                    terminal = result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired,
                    form = checked.copy(generalErrors = listOf(result.error.moderationMessage())))
                is AO3Result.Success -> when (val outcome = result.value) {
                    is AO3SignUpSaveOutcome.Invalid -> state.value.copy(saving = false, form = outcome.form)
                    is AO3SignUpSaveOutcome.Saved -> state.value.copy(saving = false, form = outcome.form,
                        notice = "Sign-up submitted successfully!")
                }
            }
        } catch (_: CancellationException) {
            if (ownsSession()) mutable.value = state.value.copy(saving = false)
        } finally { saveJob = null }
    }

    suspend fun withdraw() {
        val form = state.value.form ?: return
        val signUpID = form.signUpID ?: return
        if (!ownsSession() || state.value.loading || state.value.saving || state.value.withdrawing ||
            state.value.withdrawn || state.value.terminal) return
        withdrawJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(withdrawing = true, notice = null)
        try {
            // Once sent, show the repository's verdict even if the preparing session moved on.
            // The screen keys its private model on generation, so no old form crosses accounts.
            val result = writes.withdrawSignUp(slug, signUpID, generation)
            if (!active) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(withdrawn = true, notice = "Sign-up withdrawn.")
                is AO3Result.Failure -> state.value.copy(
                    terminal = result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired,
                    form = form.copy(generalErrors = listOf(result.error.moderationMessage())))
            }
        } catch (_: CancellationException) {
            // This cancellation is only before dispatch; an in-flight POST is NonCancellable.
        } finally {
            if (active) mutable.value = state.value.copy(withdrawing = false)
            withdrawJob = null
        }
    }
}
