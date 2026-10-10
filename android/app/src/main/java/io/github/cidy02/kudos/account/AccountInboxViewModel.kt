package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3RequestCoordinator
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkAction
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkForm
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterForm
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.network.ao3.displayMessage

/**
 * State machine for Account › Activity › Inbox.
 *
 * Mirrors iOS `AO3InboxModel`: page load + filter + selection (current page only)
 * + fail-closed bulk actions that reload from AO3 on success (never local-mutate
 * read/unread). Work-author enrichment for role badges is progressive and never
 * blocks first paint.
 */
data class AccountInboxUiState(
    val phase: Phase = Phase.Idle,
    val items: List<AO3InboxItem> = emptyList(),
    val currentPage: Int = 1,
    val totalPages: Int = 1,
    val totalComments: Int? = null,
    val unreadCount: Int? = null,
    val bulkForm: AO3InboxBulkForm? = null,
    val filterForm: AO3InboxFilterForm? = null,
    val filterValues: Map<String, String> = emptyMap(),
    val isSelecting: Boolean = false,
    val selectedItemIds: Set<Long> = emptySet(),
    val isPerformingBulkAction: Boolean = false,
    val actionError: String? = null,
    val actionNotice: String? = null,
    /** Work id → authors from progressive enrichment (unbounded per VM instance). */
    val workAuthorsById: Map<Long, List<AO3CommentWorkAuthor>> = emptyMap(),
    val pageUrl: String? = null,
    val isShowingStaleCache: Boolean = false
) {
    enum class Phase {
        Idle,
        Loading,
        Loaded,
        Failed
    }

    val selectableItemIds: Set<Long>
        get() = items.mapNotNull { item ->
            if (item.bulkSelectionField != null) item.id else null
        }.toSet()

    val selectedItems: List<AO3InboxItem>
        get() = items.filter { it.id in selectedItemIds }

    val allCurrentPageSelected: Boolean
        get() = selectableItemIds.isNotEmpty() && selectableItemIds.all { it in selectedItemIds }

    val canSelectItems: Boolean
        get() = bulkForm != null && selectableItemIds.isNotEmpty()

    fun canPerformItemAction(action: AO3InboxBulkAction, item: AO3InboxItem): Boolean =
        item.id in selectableItemIds && bulkForm?.parameters(listOf(item), action) != null

    val canFilter: Boolean
        get() = filterForm != null
}

class AccountInboxViewModel(
    private val repository: AO3InboxRepository,
    private val commentRepository: AO3CommentRepository,
    private val coordinator: AO3RequestCoordinator = AO3RequestCoordinator()
) : ViewModel() {
    private val mutableState = MutableStateFlow(AccountInboxUiState())
    val uiState: StateFlow<AccountInboxUiState> = mutableState.asStateFlow()

    private var loadJob: Job? = null
    private var enrichmentJob: Job? = null
    private var bulkJob: Job? = null
    private val attemptedWorkIds = mutableSetOf<Long>()

    init {
        load(page = 1, bypassCache = true)
        viewModelScope.launch {
            var first = true
            repository.sessionChanges.collect {
                if (first) { first = false; return@collect }
                loadJob?.cancel(); enrichmentJob?.cancel(); bulkJob?.cancel()
                mutableState.value = AccountInboxUiState()
                attemptedWorkIds.clear()
                load(page = 1, bypassCache = true)
            }
        }
    }

    fun load(page: Int, bypassCache: Boolean = false): Job? {
        if (mutableState.value.isPerformingBulkAction) return null
        loadJob?.cancel()
        enrichmentJob?.cancel()
        val previous = mutableState.value
        loadJob = viewModelScope.launch {
            mutableState.update {
                it.copy(
                    phase = if (it.items.isEmpty()) {
                        AccountInboxUiState.Phase.Loading
                    } else {
                        AccountInboxUiState.Phase.Loaded
                    },
                    actionError = null
                )
            }
            val filterForm = previous.filterForm
            val filterValues = previous.filterValues
            when (
                val result = repository.load(
                    page = page,
                    filterForm = filterForm,
                    filterValues = filterValues,
                    bypassCache = bypassCache
                )
            ) {
                is AO3Result.Success -> {
                    val pageData = result.value
                    mutableState.update {
                        it.copy(
                            phase = AccountInboxUiState.Phase.Loaded,
                            items = pageData.items,
                            currentPage = pageData.currentPage,
                            totalPages = pageData.totalPages,
                            totalComments = pageData.totalComments,
                            unreadCount = pageData.unreadCount,
                            bulkForm = pageData.bulkForm,
                            filterForm = pageData.filterForm,
                            filterValues = pageData.filterForm?.selectedValues
                                ?: it.filterValues,
                            isSelecting = false,
                            selectedItemIds = emptySet(),
                            pageUrl = pageData.pageUrl,
                            isShowingStaleCache = result.isStale,
                            actionError = null
                        )
                    }
                    if (!result.isStale) {
                        if (bypassCache) attemptedWorkIds.clear()
                        startWorkContextEnrichment(pageData.items)
                    }
                }
                is AO3Result.Failure -> {
                    mutableState.update {
                        it.copy(phase = AccountInboxUiState.Phase.Failed,
                            items = emptyList(), bulkForm = null, filterForm = null,
                            isShowingStaleCache = false, actionError = result.error.displayMessage())
                    }
                }
            }
        }
        return loadJob
    }

    fun retry() {
        load(mutableState.value.currentPage, bypassCache = true)
    }

    suspend fun refresh() {
        val job = load(mutableState.value.currentPage, bypassCache = true) ?: return
        try { job.join() } finally { if (job.isActive) job.cancel() }
    }

    fun goToPage(page: Int) {
        load(page)
    }

    fun beginSelection() {
        val state = mutableState.value
        if (!state.canSelectItems || state.isPerformingBulkAction) return
        mutableState.update { it.copy(isSelecting = true) }
    }

    fun endSelection() {
        mutableState.update {
            it.copy(isSelecting = false, selectedItemIds = emptySet())
        }
    }

    fun toggleSelection(item: AO3InboxItem) {
        val state = mutableState.value
        if (state.isPerformingBulkAction) return
        if (item.id !in state.selectableItemIds) return
        mutableState.update {
            val next = it.selectedItemIds.toMutableSet()
            if (item.id in next) next.remove(item.id) else next.add(item.id)
            it.copy(selectedItemIds = next)
        }
    }

    fun toggleSelectAllCurrentPage() {
        val state = mutableState.value
        if (state.isPerformingBulkAction) return
        mutableState.update {
            it.copy(
                selectedItemIds = if (it.allCurrentPageSelected) {
                    emptySet()
                } else {
                    it.selectableItemIds
                }
            )
        }
    }

    fun applyFilter(fieldName: String, value: String) {
        applyFilters(mapOf(fieldName to value))
    }

    fun applyFilters(values: Map<String, String>) {
        val state = mutableState.value
        if (state.isPerformingBulkAction) return
        if (values.isEmpty()) return
        val fields = state.filterForm?.fields ?: return
        if (values.any { (name, value) ->
                fields.firstOrNull { it.name == name }
                    ?.options
                    ?.none { it.value == value } != false
            }
        ) {
            return
        }
        mutableState.update {
            it.copy(
                filterValues = it.filterValues + values,
                isSelecting = false,
                selectedItemIds = emptySet()
            )
        }
        load(page = 1, bypassCache = true)
    }

    fun clearActionError() {
        mutableState.update { it.copy(actionError = null) }
    }

    fun clearActionNotice() {
        mutableState.update { it.copy(actionNotice = null) }
    }

    fun canPerformItemAction(action: AO3InboxBulkAction, item: AO3InboxItem): Boolean =
        mutableState.value.canPerformItemAction(action, item)

    fun startItemAction(action: AO3InboxBulkAction, item: AO3InboxItem) {
        startAction(action, listOf(item))
    }

    fun startBulkAction(action: AO3InboxBulkAction) {
        startAction(action, mutableState.value.selectedItems)
    }

    private fun startAction(action: AO3InboxBulkAction, items: List<AO3InboxItem>) {
        val state = mutableState.value
        if (state.isPerformingBulkAction) return
        val form = state.bulkForm ?: return
        val referer = state.pageUrl ?: return
        if (items.isEmpty()) return
        if (!items.all { it.id in state.selectableItemIds }) return
        if (form.parameters(items, action) == null) return

        val expectedViewer = repository.viewerScope()
        bulkJob?.cancel()
        bulkJob = viewModelScope.launch {
            mutableState.update {
                it.copy(isPerformingBulkAction = true, actionError = null, actionNotice = null)
            }
            try {
                when (
                    val result = repository.performBulkAction(
                        action = action,
                        form = form,
                        items = items,
                        referer = referer
                    )
                ) {
                    is AO3Result.Success -> {
                        if (repository.viewerScope() != expectedViewer) return@launch
                        mutableState.update {
                            it.copy(
                                isSelecting = false,
                                selectedItemIds = emptySet(),
                                isPerformingBulkAction = false,
                                actionNotice = result.value
                            )
                        }
                        // Reload from AO3 — never locally fake read/unread state.
                        reloadAfterWrite(state.currentPage)
                    }
                    is AO3Result.Failure -> {
                        if (repository.viewerScope() != expectedViewer) return@launch
                        mutableState.update {
                            it.copy(
                                isPerformingBulkAction = false,
                                actionError = result.error.displayMessage()
                            )
                        }
                    }
                }
            } catch (error: CancellationException) {
                if (repository.viewerScope() != expectedViewer) throw error
                // POST may have landed — do not silently retry.
                mutableState.update {
                    it.copy(
                        isPerformingBulkAction = false,
                        actionError =
                            "Couldn't confirm this posted — reload to check AO3's current state."
                    )
                }
                throw error
            } catch (error: Exception) {
                if (repository.viewerScope() != expectedViewer) return@launch
                mutableState.update {
                    it.copy(
                        isPerformingBulkAction = false,
                        actionError = error.message
                            ?: "Couldn't confirm this posted — reload to check AO3's current state."
                    )
                }
            } finally {
                if (repository.viewerScope() == expectedViewer) {
                    mutableState.update { it.copy(isPerformingBulkAction = false) }
                }
            }
        }
    }

    private suspend fun reloadAfterWrite(page: Int) {
        val state = mutableState.value
        when (
            val result = repository.load(
                page = page,
                filterForm = state.filterForm,
                filterValues = state.filterValues,
                bypassCache = true
            )
        ) {
            is AO3Result.Success -> {
                val pageData = result.value
                mutableState.update {
                    it.copy(
                        phase = AccountInboxUiState.Phase.Loaded,
                        items = pageData.items,
                        currentPage = pageData.currentPage,
                        totalPages = pageData.totalPages,
                        totalComments = pageData.totalComments,
                        unreadCount = pageData.unreadCount,
                        bulkForm = pageData.bulkForm,
                        filterForm = pageData.filterForm,
                        filterValues = pageData.filterForm?.selectedValues ?: it.filterValues,
                        pageUrl = pageData.pageUrl,
                        isShowingStaleCache = result.isStale
                    )
                }
                startWorkContextEnrichment(pageData.items)
            }
            is AO3Result.Failure -> {
                mutableState.update {
                    it.copy(phase = AccountInboxUiState.Phase.Failed, items = emptyList(),
                        bulkForm = null, filterForm = null, isShowingStaleCache = false,
                        actionError = result.error.displayMessage())
                }
            }
        }
    }

    /**
     * Progressive Author-role enrichment. Uses [AO3CommentRepository.loadThread]
     * for workAuthors (AO3WorkMetadata has no authors field). Sequential + paced
     * via [AO3RequestCoordinator]; failures on one work do not block the rest.
     * Cache is unbounded for this ViewModel instance (AO3 page size bounds growth).
     */
    private fun startWorkContextEnrichment(items: List<AO3InboxItem>) {
        enrichmentJob?.cancel()
        val workIds = items.mapNotNull { it.workId }.distinct()
        if (workIds.isEmpty()) return
        enrichmentJob = viewModelScope.launch {
            for (workId in workIds) {
                if (mutableState.value.workAuthorsById.containsKey(workId) || workId in attemptedWorkIds) continue
                // Remember the attempt before the read, including a failed or cancelled one.
                attemptedWorkIds.add(workId)
                try {
                    val canContinue = coordinator.coordinate {
                        when (
                            val result = commentRepository.loadThread(
                                AO3CommentTarget.Work(workId), useCache = false
                            )
                        ) {
                            is AO3Result.Success -> {
                                val authors = result.value.workAuthors
                                mutableState.update { state ->
                                    state.copy(
                                        workAuthorsById = state.workAuthorsById +
                                            (workId to authors)
                                    )
                                }
                                true
                            }
                            is AO3Result.Failure -> {
                                // One unavailable work does not block the rest; a systemic
                                // failure stops the batch rather than spending more reads.
                                result.error == AO3Error.NotFound || result.error == AO3Error.Forbidden
                            }
                        }
                    }
                    if (!canContinue) return@launch
                } catch (_: CancellationException) {
                    return@launch
                } catch (_: Exception) {
                    // A systemic failure stops the batch.
                    return@launch
                }
            }
        }
    }

    fun workAuthorsFor(item: AO3InboxItem): List<AO3CommentWorkAuthor> {
        val workId = item.workId ?: return emptyList()
        return mutableState.value.workAuthorsById[workId].orEmpty()
    }

    companion object {
        fun factory(
            repository: AO3InboxRepository,
            commentRepository: AO3CommentRepository
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountInboxViewModel(
                        repository = repository,
                        commentRepository = commentRepository
                    ) as T
                }
            }
        }
    }
}
