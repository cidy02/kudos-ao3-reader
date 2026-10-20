package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.asStateFlow

data class WritingBulkEditUiState(
    val form: AO3BulkEditForm? = null, val changes: AO3BulkEditChanges,
    val loading: Boolean = false, val saving: Boolean = false, val saved: Boolean = false,
    val failure: String? = null, val saveError: String? = null
)

class WritingBulkEditState(val ids: List<Long>, private val writes: AO3WriteRepository, val generation: Int) {
    private val mutable = MutableStateFlow(WritingBulkEditUiState(changes = AO3BulkEditChanges(ids)))
    val state = mutable.asStateFlow()
    private var attempted = false
    private var active = true
    suspend fun load(retry: Boolean = false) {
        val old = state.value
        if (!active || old.loading || old.form != null || (attempted && !retry)) return
        attempted = true
        mutable.value = old.copy(loading = true, failure = null)
        try {
            when (val answer = writes.loadBulkEditForm(ids, generation)) {
                is AO3Result.Success -> if (active) mutable.value = state.value.copy(form = answer.value, changes = state.value.changes.copy(workIDs = answer.value.workIDs))
                is AO3Result.Failure -> if (active) mutable.value = state.value.copy(failure = workFormFailure(answer.error))
            }
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(failure = WORK_FORM_SESSION_CHANGED)
        } catch (error: Exception) {
            if (active) mutable.value = state.value.copy(failure = workFormFailure(if (error is java.io.IOException) AO3Error.networkFromTransport(error) else AO3Error.Network(error.message.orEmpty(), error)))
        } finally { if (active) mutable.value = state.value.copy(loading = false) }
    }
    fun change(edit: (AO3BulkEditChanges) -> AO3BulkEditChanges) {
        if (active && !state.value.saving && !state.value.saved) mutable.value = state.value.copy(changes = edit(state.value.changes))
    }
    /**
     * True once AO3 took every work's change. The per-work writes run to the end even when the
     * screen is closed meanwhile (A64 F04: iOS's save is an unstructured task that goes on after
     * Cancel and still tells the opener; Android stopped part-way, some works written, and the
     * list behind kept the old values). Call it from a scope that outlives this screen.
     */
    suspend fun save(): Boolean {
        val old = state.value
        if (!active || old.form == null || old.saving || old.saved) return false
        mutable.value = old.copy(saving = true, saveError = null)
        try {
            when (val answer = withContext(NonCancellable) { writes.bulkEditWorks(old.changes, generation) }) {
                is AO3Result.Success -> { if (active) mutable.value = state.value.copy(saved = true); return true }
                is AO3Result.Failure -> if (active) mutable.value = state.value.copy(saveError = workFormFailure(answer.error))
            }
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(saveError = WORK_FORM_SESSION_CHANGED)
        } catch (error: Exception) {
            if (active) mutable.value = state.value.copy(saveError = workFormFailure(if (error is java.io.IOException) AO3Error.networkFromTransport(error) else AO3Error.Network(error.message.orEmpty(), error)))
        } finally { if (active) mutable.value = state.value.copy(saving = false) }
        return false
    }
    fun dismissError() { mutable.value = state.value.copy(saveError = null) }
    fun close() { active = false }
}
