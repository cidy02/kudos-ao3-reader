package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class WritingSeriesUiState(val form: AO3SeriesForm? = null, val rows: List<AO3SeriesWorkRow>? = null,
    val loading: Boolean = false, val failure: String? = null, val saving: Boolean = false,
    val error: String? = null, val notice: String? = null, val orderSaved: Boolean = false)

/** One opening session, draft kept even when that session fails. No implicit retries. */
internal class WritingSeriesState(val id: Long, private val repository: AO3SeriesFormRepository,
    private val writes: AO3WriteRepository, private val reorderOnly: Boolean = false,
    private val blurbs: List<AO3WorkSummary> = emptyList()) {
    private val auth = repository.auth
    val account = auth.username().orEmpty()
    private val generation = auth.generation.value
    private var active = true
    private var attempted = false
    private var manageAttempted = false
    private var loadJob: Job? = null
    private var writeJob: Job? = null
    private val mutable = MutableStateFlow(WritingSeriesUiState())
    val state = mutable.asStateFlow()
    private fun current() = active && generation == auth.generation.value && auth.state.value.isSignedIn
    fun close() { active = false; loadJob?.cancel(); writeJob?.cancel() }

    suspend fun load(retry: Boolean = false) {
        if (!active || state.value.loading || state.value.form != null || state.value.rows != null || attempted && !retry) return
        attempted = true
        if (!current()) { mutable.value = state.value.copy(failure = "Log in to AO3 first."); return }
        loadJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            if (reorderOnly) {
                when (val result = repository.loadManage(id)) {
                    is AO3Result.Success -> if (current()) mutable.value = state.value.copy(rows = result.value.sortedBy { it.position })
                    is AO3Result.Failure -> if (current()) mutable.value = state.value.copy(failure = workFormFailure(result.error))
                }
            } else {
                when (val result = repository.loadForm(id)) {
                    is AO3Result.Failure -> if (current()) mutable.value = state.value.copy(failure = workFormFailure(result.error))
                    is AO3Result.Success -> {
                        var form = result.value
                        // Stamp BEFORE suspension: failures and cancellations consume the best-effort read.
                        if (!manageAttempted) {
                            manageAttempted = true
                            try {
                                val managed = repository.loadManage(id)
                                if (managed is AO3Result.Success) form = form.copy(works = attachSeriesBlurbs(managed.value, blurbs))
                            } catch (cancelled: CancellationException) {
                                // iOS's try? keeps the required form if only the optional read was cancelled.
                                if (!current()) throw cancelled
                            }
                            catch (_: Exception) { /* iOS keeps the editor when the optional read fails. */ }
                        }
                        if (current()) mutable.value = state.value.copy(form = form)
                    }
                }
            }
            if (active && !current() && state.value.form == null && state.value.rows == null)
                mutable.value = state.value.copy(failure = "Your AO3 session expired. Please log in again.")
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(failure = if (current()) "The request was cancelled."
                else "Your AO3 session expired. Please log in again.")
        } catch (_: Exception) {
            if (active) mutable.value = state.value.copy(failure = "Couldn't reach AO3. Check your connection and try again.")
        } finally { if (active) mutable.value = state.value.copy(loading = false); loadJob = null }
    }

    fun edit(change: (AO3SeriesForm) -> AO3SeriesForm) {
        if (current() && !state.value.saving) state.value.form?.let { mutable.value = state.value.copy(form = change(it)) }
    }
    fun beginReorder() {
        if (active && !state.value.saving) mutable.value = state.value.copy(
            rows = state.value.form?.works?.sortedBy { it.position } ?: state.value.rows?.sortedBy { it.position },
            error = null, orderSaved = false)
    }
    fun move(from: Int, to: Int) {
        val rows = state.value.rows ?: return
        if (!current() || state.value.saving || from !in rows.indices || to !in rows.indices || from == to) return
        val changed = rows.toMutableList().apply { add(to, removeAt(from)) }
        mutable.value = state.value.copy(rows = changed, orderSaved = false)
    }
    suspend fun save(order: Boolean = false) {
        if (!active || state.value.saving) return
        val form = state.value.form
        val rows = state.value.rows
        if (order && (rows == null || rows.size < 2) || !order && (form == null || seriesTitleIsBlank(form.title))) return
        if (!current()) { mutable.value = state.value.copy(error = if (order)
            "Your AO3 session changed, so the order was not saved." else WORK_FORM_SESSION_CHANGED); return }
        writeJob = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(saving = true, error = null, notice = null, orderSaved = false)
        try {
            if (order) {
                when (val result = writes.reorderSeries(id, rows!!.map { it.serialWorkID }, generation)) {
                    is AO3Result.Success -> if (current()) {
                        val fresh = keepingMetadata(rows, result.value)
                        mutable.value = state.value.copy(rows = fresh, form = state.value.form?.copy(works = fresh), orderSaved = true)
                    }
                    is AO3Result.Failure -> if (active) mutable.value = state.value.copy(error = workFormFailure(result.error))
                }
            } else when (val result = writes.saveSeries(form!!, generation)) {
                is AO3Result.Success -> if (current()) mutable.value = state.value.copy(notice = result.value)
                is AO3Result.Failure -> if (active) mutable.value = state.value.copy(error = workFormFailure(result.error))
            }
            currentCoroutineContext().ensureActive()
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(error = if (order) "Your AO3 session changed, so the order was not saved."
                else WORK_FORM_SESSION_CHANGED)
        } catch (_: Exception) {
            if (active) mutable.value = state.value.copy(error = "Couldn't reach AO3. Check your connection and try again.")
        } finally { if (active) mutable.value = state.value.copy(saving = false); writeJob = null }
    }

    suspend fun remove(row: AO3SeriesWorkRow) {
        if (!active || state.value.saving || state.value.form?.works?.size?.let { it <= 1 } != false) return
        if (!current()) { mutable.value = state.value.copy(error = "Your AO3 session changed, so nothing was removed."); return }
        mutable.value = state.value.copy(saving = true, error = null)
        writeJob = currentCoroutineContext()[Job]
        try {
            when (val result = writes.removeWorkFromSeries(id, row.serialWorkID, generation)) {
                is AO3Result.Success -> if (current()) mutable.value = state.value.copy(form = state.value.form?.let {
                    it.copy(works = keepingMetadata(it.works, result.value)) })
                is AO3Result.Failure -> if (active) mutable.value = state.value.copy(
                    error = "${row.displayTitle} was not removed. " + workFormFailure(result.error))
            }
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(error = "Your AO3 session changed, so nothing was removed.")
        } catch (_: Exception) {
            if (active) mutable.value = state.value.copy(error = "${row.displayTitle} was not removed. " +
                "Couldn't reach AO3. Check your connection and try again.")
        } finally { if (active) mutable.value = state.value.copy(saving = false); writeJob = null }
    }

    private fun keepingMetadata(old: List<AO3SeriesWorkRow>, fresh: List<AO3SeriesWorkRow>) = fresh.sortedBy { it.position }.map { row ->
        old.firstOrNull { it.serialWorkID == row.serialWorkID }?.let { row.copy(words = it.words, dateText = it.dateText) } ?: row
    }
}
