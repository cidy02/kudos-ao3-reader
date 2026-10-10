package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
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
    suspend fun save() {
        val old = state.value
        if (!active || old.form == null || old.saving || old.saved) return
        mutable.value = old.copy(saving = true, saveError = null)
        try {
            when (val answer = writes.bulkEditWorks(old.changes, generation)) {
                is AO3Result.Success -> if (active) mutable.value = state.value.copy(saved = true)
                is AO3Result.Failure -> if (active) mutable.value = state.value.copy(saveError = workFormFailure(answer.error))
            }
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(saveError = WORK_FORM_SESSION_CHANGED)
        } catch (error: Exception) {
            if (active) mutable.value = state.value.copy(saveError = workFormFailure(if (error is java.io.IOException) AO3Error.networkFromTransport(error) else AO3Error.Network(error.message.orEmpty(), error)))
        } finally { if (active) mutable.value = state.value.copy(saving = false) }
    }
    fun dismissError() { mutable.value = state.value.copy(saveError = null) }
    fun close() { active = false }
}
