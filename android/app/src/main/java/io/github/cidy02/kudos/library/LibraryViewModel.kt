package io.github.cidy02.kudos.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class LibraryViewModel(
    private val repository: LibraryRepository,
    private val workRepository: WorkRepository,
    private val settingsRepository: SettingsRepository? = null,
    private val queueRepository: ReadingQueueRepository? = null,
    private val privacyGate: PrivacyGate = PrivacyGate()
) : ViewModel() {
    private val searchQuery = MutableStateFlow("")
    private val filters = MutableStateFlow(LibraryFilterState())
    private val sort = MutableStateFlow(LibrarySort.RecentlyAdded)
    private val selectionMode = MutableStateFlow(false)
    private val selectedWorkIds = MutableStateFlow<Set<String>>(emptySet())
    private val readingQueues = MutableStateFlow<List<LibraryQueuePreview>>(emptyList())
    private val queueRefreshTick = MutableStateFlow(0)

    private val libraryBase: StateFlow<LibraryUiState> = combine(
        repository.observeSnapshot(),
        searchQuery,
        filters,
        sort,
        privacyGate.state
    ) { snapshot, query, filters, sort, revealed ->
        // Reveal has to reach the visibility decision itself, not be re-applied to
        // the result: in Hide mode the hidden works are gone from these lists before
        // any later pass could bring them back.
        LibraryQuery.buildState(snapshot, query, filters, sort, revealed)
    }.catch { throwable ->
        emit(
            LibraryUiState(
                loading = false,
                error = throwable.message ?: "Library could not be loaded."
            )
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = LibraryUiState(loading = true)
    )

    val state: StateFlow<LibraryUiState> = combine(
        libraryBase,
        selectionMode,
        selectedWorkIds,
        privacyGate.state,
        readingQueues
    ) { base, selecting, ids, revealed, queues ->
        base.copy(
            selectionMode = selecting,
            selectedWorkIds = if (selecting) ids else emptySet(),
            revealedWorkIds = revealed.revealedIds,
            revealAllActive = revealed.revealAll,
            readingQueues = queues
            // Reveal is already folded into every shelf by LibraryQuery.buildState.
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = LibraryUiState(loading = true)
    )

    init {
        refreshQueues()
        // Re-load queues when an external tick is bumped after create/add.
        viewModelScope.launch {
            queueRefreshTick.collect { refreshQueues() }
        }
    }

    fun updateSearchQuery(query: String) {
        searchQuery.value = query
    }

    fun updateSort(next: LibrarySort) {
        sort.value = next
    }

    /** Fandom chip bar: empty = All; single fandom = filter to that name. */
    fun setFandomFilter(fandom: String?) {
        filters.update { current ->
            val next = fandom?.trim().orEmpty()
            current.copy(
                fandoms = if (next.isEmpty()) emptySet() else setOf(next)
            )
        }
    }

    fun toggleFavoriteOnly() {
        filters.update { it.copy(favoriteOnly = !it.favoriteOnly) }
    }

    fun setFinishedFilter(next: LibraryFinishedFilter) {
        filters.update { it.copy(finished = next) }
    }

    fun setDownloadFilter(next: LibraryDownloadFilter) {
        filters.update { it.copy(download = next) }
    }

    fun toggleUserTag(tagId: String) {
        filters.update { it.copy(userTagIds = it.userTagIds.toggle(tagId)) }
    }

    fun toggleCollection(collectionId: String) {
        filters.update { it.copy(collectionIds = it.collectionIds.toggle(collectionId)) }
    }

    fun clearFilters() {
        filters.value = LibraryFilterState()
    }

    // region Multi-select

    fun enterSelectionMode(initialWorkId: String? = null) {
        selectionMode.value = true
        selectedWorkIds.value = if (initialWorkId != null) {
            LibrarySelection.selectOnly(initialWorkId)
        } else {
            LibrarySelection.clear()
        }
    }

    fun exitSelectionMode() {
        selectionMode.value = false
        selectedWorkIds.value = LibrarySelection.clear()
    }

    fun toggleWorkSelection(workId: String) {
        if (!selectionMode.value) {
            enterSelectionMode(workId)
            return
        }
        selectedWorkIds.update { LibrarySelection.toggle(it, workId) }
    }

    fun bulkSetFavorite(favorite: Boolean) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.setFavorite(id, favorite)
            }
            exitSelectionMode()
        }
    }

    fun bulkSetSaved(saved: Boolean) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.setSaved(id, saved)
            }
            exitSelectionMode()
        }
    }

    fun bulkSetFinished(finished: Boolean) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.setFinished(id, finished)
            }
            exitSelectionMode()
        }
    }

    fun bulkSoftDelete() {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.softDelete(id)
            }
            exitSelectionMode()
        }
    }

    fun bulkRemoveFromSaveForLater() {
        val ids = selectedWorkIds.value
        val repo = queueRepository ?: return
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                repo.removeFromSavedForLater(id)
            }
            exitSelectionMode()
        }
    }

    fun bulkAddToQueue(queueId: String) {
        val ids = selectedWorkIds.value
        val queues = queueRepository ?: return
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                runCatching { queues.addWork(queueId, id) }
            }
            queueRefreshTick.update { it + 1 }
            exitSelectionMode()
        }
    }

    fun bulkAddToCollection(collectionName: String) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                runCatching { workRepository.addToCollection(id, collectionName) }
            }
            exitSelectionMode()
        }
    }

    // endregion

    // region Context-menu single-work actions

    fun toggleFavoriteOne(workId: String) {
        viewModelScope.launch {
            val work = workRepository.getWork(workId) ?: return@launch
            workRepository.setFavorite(workId, !work.isFavorite)
        }
    }

    fun toggleFinishedOne(workId: String) {
        viewModelScope.launch {
            workRepository.toggleFinished(workId)
        }
    }

    fun softDeleteOne(workId: String) {
        viewModelScope.launch {
            workRepository.softDelete(workId)
        }
    }

    fun setSavedOne(workId: String, saved: Boolean) {
        viewModelScope.launch {
            workRepository.setSaved(workId, saved)
        }
    }

    fun toggleSavedOne(workId: String) {
        viewModelScope.launch {
            val work = workRepository.getWork(workId) ?: return@launch
            workRepository.setSaved(workId, !work.isSaved)
        }
    }

    /**
     * [alreadyQueued] must be the same [SavedWork.isQueuedForLater] the caller's UI
     * already showed (e.g. to decide an "Add"/"Remove" label) — not re-derived here via
     * the precise [ReadingQueueRepository.isInSavedForLater] check, which can disagree
     * with the coarse flag for a work that's only in a *different* queue. Re-deriving
     * here previously let a "Remove from Saved for Later" label add the work instead,
     * because the label used the coarse flag while this function used the precise one.
     */
    fun toggleSavedForLaterOne(workId: String, alreadyQueued: Boolean) {
        val repo = queueRepository ?: return
        viewModelScope.launch {
            if (alreadyQueued) {
                repo.removeFromSavedForLater(workId)
            } else {
                runCatching { repo.addToSavedForLater(workId) }
            }
            queueRefreshTick.update { it + 1 }
        }
    }

    fun addToQueue(workId: String, queueId: String) {
        val queues = queueRepository ?: return
        viewModelScope.launch {
            runCatching { queues.addWork(queueId, workId) }
            queueRefreshTick.update { it + 1 }
        }
    }

    fun addToCollection(workId: String, collectionName: String) {
        viewModelScope.launch {
            runCatching { workRepository.addToCollection(workId, collectionName) }
        }
    }

    /**
     * Toggle a work's membership in an existing collection by id (checklist picker).
     * Prefer this over name-based [addToCollection] so renames/duplicates don't matter.
     */
    fun setCollectionMembership(workId: String, collectionId: String, member: Boolean) {
        viewModelScope.launch {
            runCatching {
                if (member) {
                    workRepository.addWorkToCollection(workId, collectionId)
                } else {
                    workRepository.removeFromCollection(workId, collectionId)
                }
            }
        }
    }

    fun createCollection(name: String, onCreated: (String) -> Unit = {}) {
        viewModelScope.launch {
            val created = runCatching { workRepository.createCollection(name) }.getOrNull()
            if (created != null) onCreated(created.id)
        }
    }

    fun createQueue(name: String, onCreated: (String) -> Unit = {}) {
        val queues = queueRepository ?: return
        viewModelScope.launch {
            val created = runCatching { queues.createQueue(name) }.getOrNull()
            queueRefreshTick.update { it + 1 }
            if (created != null) onCreated(created.id)
        }
    }

    /** Session reveal for an obscured mature card (Apple `PrivacyGate.reveal`). */
    fun revealWork(workId: String, activity: androidx.fragment.app.FragmentActivity? = null) {
        privacyGate.reveal(workId, activity)
    }

    /**
     * Apple `MatureRevealToggle`: session-only show/re-hide of every mature work,
     * shared app-wide via `PrivacyGate` — NOT a change to the persisted "Hide mature
     * content" setting.
     *
     * This used to call `settingsRepository.updateHideMatureContent`, which permanently
     * flipped that app-wide setting (surfaced in Settings, and gating Home/Search/
     * Browse too) from a single toolbar tap meant only to peek at one item for the
     * current session — a real behavioural mismatch from Apple's session-only toggle,
     * found in review and fixed here.
     */
    fun toggleRevealAll(activity: androidx.fragment.app.FragmentActivity? = null) {
        privacyGate.toggleRevealAll(activity)
    }

    // endregion

    /**
     * Pull-to-refresh for Library. The work list itself is a Room Flow and is
     * already live, so this re-reads the reading-queue previews, whose counts do
     * go stale when queues change elsewhere.
     *
     * ponytail: deliberately does not sweep AO3 metadata on every pull — that
     * would be an unbounded scrape on a gesture users repeat. The paced sweep in
     * KudosApplication and the per-work "Refresh Metadata" action cover that.
     */
    suspend fun refresh() {
        val queues = queueRepository ?: return
        runCatching {
            queues.ensureSavedForLaterQueue()
            queues.listQueues().map { queue ->
                LibraryQueuePreview(
                    id = queue.id,
                    name = queue.displayName,
                    workCount = queues.listWorks(queue.id).size
                )
            }
        }.onSuccess { readingQueues.value = it }
    }

    private fun refreshQueues() {
        val queues = queueRepository ?: return
        viewModelScope.launch {
            runCatching {
                queues.ensureSavedForLaterQueue()
                queues.listQueues().map { queue ->
                    LibraryQueuePreview(
                        id = queue.id,
                        name = queue.displayName,
                        workCount = queues.listWorks(queue.id).size
                    )
                }
            }.onSuccess { readingQueues.value = it }
        }
    }

    companion object {
        fun factory(
            repository: LibraryRepository,
            workRepository: WorkRepository,
            settingsRepository: SettingsRepository? = null,
            queueRepository: ReadingQueueRepository? = null,
            privacyGate: PrivacyGate = PrivacyGate()
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    LibraryViewModel(
                        repository,
                        workRepository,
                        settingsRepository,
                        queueRepository,
                        privacyGate
                    )
                }
            }
    }
}

private fun Set<String>.toggle(value: String): Set<String> {
    return if (value in this) this - value else this + value
}
