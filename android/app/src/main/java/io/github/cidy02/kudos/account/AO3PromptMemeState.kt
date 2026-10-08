package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemePage
import io.github.cidy02.kudos.network.ao3.account.challengeDateText
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
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
    val failure: String? = null,
    val promptInFlight: Int? = null,
    val actionError: String? = null
)

/**
 * iOS PromptMemeView.readsSchedule (owner, 2026-10-07). The close date is on the challenge's settings
 * form, which AO3 serves to the collection's owners and refuses to everyone else, moderators included.
 * So: only for an owner, only until a date is known, once per opening and once more per refresh.
 */
internal fun readsPromptMemeSchedule(viewerIsOwner: Boolean, attempted: Boolean, hasDate: Boolean): Boolean =
    viewerIsOwner && !attempted && !hasDate

/** A visible screen owns these remote values and cancels its load on departure/session change. */
internal class AO3PromptMemeState(
    private val slug: String,
    private val repository: AO3CollectionDetailRepository,
    private val viewerIsOwner: Boolean,
    private val writes: AO3WriteRepository
) {
    private var scheduleAttempted = false
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var loadJob: Job? = null
    private var actionJob: Job? = null
    private val mutable = MutableStateFlow(PromptMemeUiState())
    val state = mutable.asStateFlow()

    private fun ownsSession() = active && generation == auth.generation.value
    fun close() { active = false; loadJob?.cancel(); actionJob?.cancel() }
    fun dismissActionError() { if (ownsSession()) mutable.value = state.value.copy(actionError = null) }

    suspend fun claim(promptID: Int) = changeClaim(promptID, release = false)
    suspend fun release(promptID: Int) = changeClaim(promptID, release = true)

    private suspend fun changeClaim(promptID: Int, release: Boolean) {
        if (!ownsSession() || state.value.loading || state.value.promptInFlight != null) return
        val prompt = state.value.data?.prompts?.firstOrNull { it.id == promptID } ?: return
        if (release && prompt.claimID == null || !release && (!prompt.canClaim || prompt.claimedByCurrentUser)) return
        actionJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(promptInFlight = promptID, actionError = null)
        try {
            val result = if (release) writes.releasePrompt(slug, prompt.claimID!!, generation)
                else writes.claimPrompt(slug, prompt.id, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            when (result) {
                is AO3Result.Success -> loadPage(state.value.data?.currentPage ?: 1, readSchedule = false)
                is AO3Result.Failure -> mutable.value = state.value.copy(actionError =
                    "Couldn't ${if (release) "release" else "claim"} that prompt: ${result.error.moderationMessage()}")
            }
        } finally {
            if (ownsSession()) mutable.value = state.value.copy(promptInFlight = null)
            actionJob = null
        }
    }

    /** [readSchedule] marks an opening or a refresh, the two moments the close date may be asked for. */
    suspend fun load(page: Int = 1, readSchedule: Boolean = false) {
        if (state.value.promptInFlight != null) return
        loadPage(page, readSchedule)
    }

    private suspend fun loadPage(page: Int, readSchedule: Boolean) {
        if (!ownsSession() || state.value.loading || page < 1) return
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            if (readSchedule) scheduleAttempted = false
            if (auth.state.value.isSignedIn &&
                readsPromptMemeSchedule(viewerIsOwner, scheduleAttempted, state.value.closeDateText.isNotEmpty())
            ) {
                scheduleAttempted = true
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
