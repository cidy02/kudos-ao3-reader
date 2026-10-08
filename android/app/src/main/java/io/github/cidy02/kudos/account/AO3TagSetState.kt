package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetSnapshot
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetField
import io.github.cidy02.kudos.network.ao3.account.AO3TagNomination
import io.github.cidy02.kudos.network.ao3.account.AO3TagNominationState
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class TagSetUiState(
    val data: AO3TagSetSnapshot? = null,
    val loading: Boolean = false,
    val failure: String? = null,
    val fields: Map<AO3TagSetField, String> = emptyMap(),
    val saving: Boolean = false,
    val saveError: String? = null,
    val saveNotice: String? = null,
    val nominationInFlight: Int? = null,
    val queueError: String? = null
)

/** One foreground page load, fenced to its opening session even when it is public. */
internal class AO3TagSetState(private val id: Int, private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var loadJob: Job? = null
    private var saveJob: Job? = null
    private var rejectJob: Job? = null
    private val mutable = MutableStateFlow(TagSetUiState())
    val state = mutable.asStateFlow()

    private fun ownsSession() = active && generation == auth.generation.value
    fun close() { active = false; loadJob?.cancel(); saveJob?.cancel(); rejectJob?.cancel() }

    fun change(field: AO3TagSetField, text: String) {
        if (ownsSession()) mutable.value = state.value.copy(fields = state.value.fields + (field to text))
    }

    suspend fun save() {
        val data = state.value.data ?: return
        if (!ownsSession() || state.value.loading || state.value.saving) return
        saveJob = currentCoroutineContext()[Job]
        val fields = state.value.fields.toMap()
        mutable.value = state.value.copy(saving = true, saveError = null, saveNotice = null)
        try {
            val result = writes.saveTagSetFields(data, fields, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(saving = false, saveNotice = "Tags saved.")
                is AO3Result.Failure -> state.value.copy(saving = false, saveError = result.error.moderationMessage())
            }
        } catch (_: CancellationException) {
            if (ownsSession()) mutable.value = state.value.copy(saving = false)
        } finally { saveJob = null }
    }

    suspend fun reject(nomination: AO3TagNomination) {
        if (!ownsSession() || state.value.loading || state.value.nominationInFlight != null ||
            state.value.data?.reviewQueue?.any { it.id == nomination.id && it.state == AO3TagNominationState.Unreviewed } != true) return
        rejectJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(nominationInFlight = nomination.id, queueError = null)
        try {
            val result = writes.reportRejectedTag(id, nomination, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(nominationInFlight = null,
                    data = state.value.data?.let { current ->
                        val index = current.reviewQueue.indexOfFirst { it.id == nomination.id }
                        current.copy(reviewQueue = current.reviewQueue.mapIndexed { rowIndex, row ->
                            if (rowIndex == index) row.copy(state = AO3TagNominationState.Rejected) else row
                        })
                    })
                is AO3Result.Failure -> state.value.copy(nominationInFlight = null,
                    queueError = "Couldn't reject “${nomination.tagName}”: ${result.error.moderationMessage()}")
            }
        } catch (_: CancellationException) {
            if (ownsSession()) mutable.value = state.value.copy(nominationInFlight = null)
        } finally { rejectJob = null }
    }

    suspend fun load() {
        if (!ownsSession() || state.value.loading || state.value.saving || state.value.nominationInFlight != null) return
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            val result = repository.getTagSet(id)
            currentCoroutineContext().ensureActive()
            if (!active || generation != auth.generation.value) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(data = result.value, fields = result.value.tagnames, loading = false)
                is AO3Result.Failure -> state.value.copy(loading = false, failure = result.error.moderationMessage())
            }
        } catch (e: CancellationException) {
            if (active && generation == auth.generation.value) mutable.value = state.value.copy(loading = false)
            throw e
        } finally { loadJob = null }
    }
}
