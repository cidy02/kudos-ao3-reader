package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItem
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemDraft
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemStaging
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsPage
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class AO3CollectionItemsUiState(
    val tab: AO3CollectionItemTab = AO3CollectionItemTab.Unreviewed,
    val page: AO3CollectionItemsPage? = null,
    val staging: AO3CollectionItemStaging = AO3CollectionItemStaging(),
    val phase: Phase = Phase.Idle,
    val loadError: String? = null,
    val submitError: String? = null
) {
    enum class Phase { Idle, Loading, Loaded, Submitting, Failed, SignedOut, NotMaintainer }
    val pending: List<AO3CollectionItemDraft> get() = staging.pending(page?.items.orEmpty())
    val busy: Boolean get() = phase == Phase.Loading || phase == Phase.Submitting
}

/** Owned by one visible screen/session; no jobs or requests survive it. */
internal class AO3CollectionItemsState(
    private val slug: String?,
    private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository
) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private val username = auth.username()
    private var loadGeneration = 0
    private val mutableState = MutableStateFlow(AO3CollectionItemsUiState(tab = AO3CollectionItemTab.defaultTab(slug)))
    val state = mutableState.asStateFlow()
    private fun ownsSession() = generation == auth.generation.value && auth.state.value.isSignedIn

    fun stage(item: AO3CollectionItem, change: (AO3CollectionItemDraft) -> AO3CollectionItemDraft) {
        val state = mutableState.value
        if (!ownsSession() || state.busy || state.page?.items?.any { it.id == item.id } != true) return
        mutableState.value = state.copy(staging = state.staging.set(item, change))
    }

    fun remove(item: AO3CollectionItem) {
        val state = mutableState.value
        if (!ownsSession() || state.busy || !item.removeEditable) return
        val removed = state.staging.shown(item).remove
        mutableState.value = state.copy(staging = state.staging.remove(item, !removed))
    }

    /** No repository call: Discard includes drafts kept on other tabs/pages. */
    fun discard() {
        if (mutableState.value.phase == AO3CollectionItemsUiState.Phase.Submitting) return
        mutableState.value = mutableState.value.copy(staging = AO3CollectionItemStaging())
    }

    suspend fun load(tab: AO3CollectionItemTab = state.value.tab, page: Int = state.value.page?.currentPage ?: 1) {
        if (state.value.phase == AO3CollectionItemsUiState.Phase.Submitting) return
        if (!ownsSession()) {
            if (generation == auth.generation.value) mutableState.value = AO3CollectionItemsUiState(
                tab = tab, phase = AO3CollectionItemsUiState.Phase.SignedOut, loadError = SIGNED_OUT
            )
            return
        }
        val request = ++loadGeneration
        val previous = mutableState.value
        mutableState.value = previous.copy(tab = tab,
            page = previous.page.takeIf { previous.tab == tab },
            phase = AO3CollectionItemsUiState.Phase.Loading, loadError = null)
        try {
            val result = if (slug != null) repository.getCollectionItems(slug, tab, page)
                else if (username != null) repository.getUserCollectionItems(username, tab, page)
                else AO3Result.Failure(AO3Error.AuthenticationRequired)
            currentCoroutineContext().ensureActive()
            if (!ownsSession() || request != loadGeneration) return
            val state = mutableState.value
            mutableState.value = when (result) {
                is AO3Result.Success -> state.copy(page = result.value, phase = AO3CollectionItemsUiState.Phase.Loaded)
                is AO3Result.Failure -> state.copy(
                    phase = if (result.error == AO3Error.Forbidden) AO3CollectionItemsUiState.Phase.NotMaintainer
                        else AO3CollectionItemsUiState.Phase.Failed,
                    loadError = result.error.displayMessage()
                )
            }
        } catch (error: CancellationException) {
            throw error
        }
    }

    /** Called only by the confirmation button; a busy submit cannot be repeated. */
    suspend fun confirmSubmit() {
        val previous = mutableState.value
        val drafts = previous.pending
        if (!ownsSession() || previous.busy || drafts.isEmpty()) return
        ++loadGeneration // Retire an older load before any POST can complete.
        mutableState.value = previous.copy(phase = AO3CollectionItemsUiState.Phase.Submitting, submitError = null)
        try {
            val result = if (slug != null) writes.updateCollectionItems(slug, drafts, generation)
                else if (username != null) writes.updateUserCollectionItems(username, drafts, generation)
                else AO3Result.Failure(AO3Error.AuthenticationRequired)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            val state = mutableState.value
            mutableState.value = state.copy(
                phase = AO3CollectionItemsUiState.Phase.Loaded,
                staging = if (result is AO3Result.Success) state.staging.clear(drafts.map { it.itemId }) else state.staging,
                submitError = (result as? AO3Result.Failure)?.error?.displayMessage()
            )
            // Also verify a partial batch: earlier writes may have succeeded before the refusal.
            load(previous.tab, previous.page?.currentPage ?: 1)
        } catch (_: CancellationException) {
            // Results from a departed screen/session do not clear or install anything.
        }
    }

    companion object {
        const val SIGNED_OUT = "Log in to AO3 to manage collection items."
    }
}
