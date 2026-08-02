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
import kotlinx.coroutines.launch

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
    val pageUrl: String? = null
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

    init {
        load(page = 1)
    }

    fun load(page: Int) {
        if (mutableState.value.isPerformingBulkAction) return
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
                    filterValues = filterValues
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
                            actionError = null
                        )
                    }
                    startWorkContextEnrichment(pageData.items)
                }
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) {
                        mutableState.update {
                            it.copy(
                                phase = AccountInboxUiState.Phase.Failed,
                                items = emptyList(),
                                actionError = result.error.displayMessage()
                            )
                        }
                    } else {
                        mutableState.update {
                            it.copy(
                                phase = if (it.items.isEmpty()) {
                                    AccountInboxUiState.Phase.Failed
                                } else {
                                    AccountInboxUiState.Phase.Loaded
                                },
                                actionError = result.error.displayMessage()
                            )
                        }
                    }
                }
            }
        }
    }

    fun retry() {
        load(mutableState.value.currentPage)
    }

    fun refresh() {
        load(mutableState.value.currentPage)
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
        val state = mutableState.value
        if (state.isPerformingBulkAction) return
        val field = state.filterForm?.fields?.firstOrNull { it.name == fieldName } ?: return
        if (field.options.none { it.value == value }) return
        mutableState.update {
            it.copy(
                filterValues = it.filterValues + (fieldName to value),
                isSelecting = false,
                selectedItemIds = emptySet()
            )
        }
        load(page = 1)
    }

    fun clearActionError() {
        mutableState.update { it.copy(actionError = null) }
    }

    fun clearActionNotice() {
        mutableState.update { it.copy(actionNotice = null) }
    }

    fun canPerformItemAction(action: AO3InboxBulkAction, item: AO3InboxItem): Boolean {
        val form = mutableState.value.bulkForm ?: return false
        if (item.id !in mutableState.value.selectableItemIds) return false
        return form.parameters(listOf(item), action) != null
    }

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
                        mutableState.update {
                            it.copy(
                                isPerformingBulkAction = false,
                                actionError = result.error.displayMessage()
                            )
                        }
                    }
                }
            } catch (error: CancellationException) {
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
                mutableState.update {
                    it.copy(
                        isPerformingBulkAction = false,
                        actionError = error.message
                            ?: "Couldn't confirm this posted — reload to check AO3's current state."
                    )
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
                filterValues = state.filterValues
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
                        pageUrl = pageData.pageUrl
                    )
                }
                startWorkContextEnrichment(pageData.items)
            }
            is AO3Result.Failure -> {
                mutableState.update {
                    it.copy(actionError = result.error.displayMessage())
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
                if (mutableState.value.workAuthorsById.containsKey(workId)) continue
                try {
                    coordinator.coordinate {
                        when (
                            val result = commentRepository.loadThread(
                                AO3CommentTarget.Work(workId)
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
                            }
                            is AO3Result.Failure -> {
                                // Leave row without a badge; don't block the page.
                                if (result.error == AO3Error.AuthenticationRequired) {
                                    return@coordinate
                                }
                            }
                        }
                    }
                } catch (_: CancellationException) {
                    return@launch
                } catch (_: Exception) {
                    // Offline / rate-limit / parse — skip this work, continue.
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
