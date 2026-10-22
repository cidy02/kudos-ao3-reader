package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.DebugShotEffect
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow
import io.github.cidy02.kudos.ui.components.rememberStoredChoice
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.toggleable
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.strippingHtml
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.coverHue
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.WorkSelectionBubble
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

enum class CollectionDisplayMode {
    Detailed,
    Ledger
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CollectionDetailScreen(
    collectionId: String,
    workRepository: WorkRepository,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate(),
    downloadQueue: DownloadQueue? = null,
    metadataRefresh: WorkMetadataRefresh? = null,
    queueRepository: ReadingQueueRepository? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onCollectionDeleted: () -> Unit,
    onOpenComments: (Long) -> Unit = {},
    workImporter: io.github.cidy02.kudos.works.WorkImporter? = null
) {
    val privacy by (settingsRepository?.settings?.map { it.privacy }
        ?: flowOf(PrivacySettings()))
        .collectAsState(initial = PrivacySettings())
    val reveal by privacyGate.state.collectAsState()
    val confirmBeforeDelete by (settingsRepository?.settings?.map { it.app.confirmBeforeDelete }
        ?: flowOf(true))
        .collectAsState(initial = true)

    val tokens = LocalKudosTokens.current
    var loading by remember(collectionId) { mutableStateOf(true) }
    var working by remember(collectionId) { mutableStateOf(false) }
    var error by remember(collectionId) { mutableStateOf<String?>(null) }
    var collection by remember(collectionId) { mutableStateOf<WorkCollection?>(null) }
    var works by remember(collectionId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    // iOS `collection.displayMode`: one choice for every collection, kept between launches.
    var displayMode by rememberStoredChoice("collection.displayMode", CollectionDisplayMode.Detailed)
    var expandAll by rememberSaveable { mutableStateOf(false) }
    var isSelecting by remember(collectionId) { mutableStateOf(false) }
    var selectedIds by remember(collectionId) { mutableStateOf<Set<String>>(emptySet()) }
    var menuOpen by remember { mutableStateOf(false) }
    var showRename by remember(collectionId) { mutableStateOf(false) }
    var renameText by remember(collectionId) { mutableStateOf("") }
    var showDetails by remember(collectionId) { mutableStateOf(false) }
    var showReorder by remember(collectionId) { mutableStateOf(false) }
    DebugShotEffect("collection", ready = collection != null && works.isNotEmpty()) { name ->
        if (name == "collectionreorder") showReorder = true else showDetails = true
    }

    var showAddPicker by remember(collectionId) { mutableStateOf(false) }
    var confirmDeleteCollection by remember(collectionId) { mutableStateOf(false) }
    var pendingRemoveWork by remember(collectionId) { mutableStateOf<SavedWork?>(null) }
    var confirmBulkRemove by remember(collectionId) { mutableStateOf(false) }
    var filterText by remember(collectionId) { mutableStateOf("") }
    var filters by remember(collectionId) { mutableStateOf(LibraryFilterState()) }
    var sort by remember(collectionId) { mutableStateOf(LibrarySort.Natural) }
    val index by remember(workRepository) { workRepository.observeLibraryIndex() }
        .collectAsState(initial = io.github.cidy02.kudos.works.WorkLibraryIndex())
    val filtersActive = filterText.isNotBlank() || filters.hasActiveFilters || sort != LibrarySort.Natural
    fun clearFilters() { filterText = ""; filters = LibraryFilterState(); sort = LibrarySort.Natural }
    var showFilterDialog by remember(collectionId) { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val activity = LocalContext.current as? FragmentActivity

    val palette = remember(collection?.hue, collection?.colorHex, collection?.name, tokens.theme) {
        val col = collection
        if (col != null) {
            collectionDraftPalette(col.name, col.hue, col.colorHex, tokens.theme)
        } else {
            tokens.scopePalette
        }
    }

    suspend fun refresh() {
        loading = true
        error = null
        try {
            collection = workRepository.getCollection(collectionId)
            works = if (collection != null) {
                workRepository.worksForCollection(collectionId)
            } else {
                emptyList()
            }
            if (collection == null) {
                error = "This collection no longer exists."
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load collection."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(collectionId) { refresh() }

    val workActions = scopedWorkActions(
        workRepository, queueRepository, downloadQueue, workImporter, confirmBeforeDelete,
        onOpenWork, onOpenReader, onOpenComments,
        onSelect = { isSelecting = true; selectedIds = setOf(it) },
        onReveal = { privacyGate.reveal(it, activity) },
        onChanged = { scope.launch { refresh() } }
    )

    val orderedWorks = remember(collection?.workOrderRaw, works) {
        val col = collection
        if (col != null) {
            HomeFacts.inReadingOrder(
                col.workOrderRaw,
                works,
                { it.id },
                { it.dateAdded }
            )
        } else {
            works
        }
    }

    val visibleWorks = remember(orderedWorks, filterText, filters, sort, index, privacy, reveal) {
        LibraryQuery.applyScoped(orderedWorks, index, filterText, filters, sort).filter { work ->
            LibraryPrivacy.visibility(work, privacy, reveal) != LibraryPrivacyVisibility.Hidden
        }
    }

    // Remove acts on what the filter still shows (audit A12-5, the same fault on iOS).
    val visibleIds = remember(visibleWorks) { visibleWorks.mapTo(linkedSetOf()) { it.id } }
    LaunchedEffect(visibleIds, selectedIds) {
        val seen = LibrarySelection.visible(selectedIds, visibleIds)
        if (seen.size != selectedIds.size) selectedIds = seen
    }

    val tallyLine = remember(works.size, collection?.keepsWorksOffline) {
        val count = works.size
        val base = "$count ${if (count == 1) "work" else "works"}"
        if (collection?.keepsWorksOffline == true) "$base · kept offline" else base
    }

    fun addWorks(workIds: Set<String>) {
        scope.launch {
            working = true
            error = null
            try {
                workIds.forEach { workRepository.addWorkToCollection(it, collectionId) }
                val current = collection
                if (current?.keepsWorksOffline == true && downloadQueue != null) {
                    for (id in workIds) {
                        val work = workRepository.getWork(id) ?: continue
                        if (!work.hasEpub) {
                            val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
                            if (ao3Id != null) {
                                downloadQueue.enqueueLocal(ao3Id, work.title, work.sourceUrl, force = false)
                            }
                        }
                    }
                }
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not add works."
            } finally {
                working = false
            }
        }
    }

    fun removeWork(workId: String) {
        scope.launch {
            working = true
            error = null
            try {
                workRepository.removeFromCollection(workId, collectionId)
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not remove work."
            } finally {
                working = false
            }
        }
    }

    fun bulkRemove(ids: Set<String>) {
        scope.launch {
            working = true
            error = null
            try {
                ids.forEach { workRepository.removeFromCollection(it, collectionId) }
                isSelecting = false
                selectedIds = emptySet()
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not remove works."
            } finally {
                working = false
            }
        }
    }

    fun renameCollection() {
        val name = renameText.trim()
        if (name.isEmpty() || working) return
        scope.launch {
            working = true
            error = null
            try {
                val updated = workRepository.renameCollection(collectionId, name)
                if (updated != null) {
                    collection = updated
                    showRename = false
                } else {
                    error = "Could not rename collection."
                }
            } catch (e: Exception) {
                error = e.message ?: "Could not rename collection."
            } finally {
                working = false
            }
        }
    }

    fun deleteCollection() {
        scope.launch {
            working = true
            error = null
            try {
                workRepository.softDeleteCollection(collectionId)
                confirmDeleteCollection = false
                onCollectionDeleted()
            } catch (e: Exception) {
                error = e.message ?: "Could not delete collection."
                working = false
            }
        }
    }

    BackHandler(enabled = isSelecting) {
        isSelecting = false
        selectedIds = emptySet()
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = isSelecting,
        customTitle = if (isSelecting) "${selectedIds.size} selected" else null,
        onBack = if (isSelecting) {
            {
                isSelecting = false
                selectedIds = emptySet()
            }
        } else null,
        trailingContent = {
            if (isSelecting) {
                val allSelected = visibleWorks.isNotEmpty() && visibleWorks.all { it.id in selectedIds }
                TextButton(
                    onClick = {
                        selectedIds = if (allSelected) emptySet() else visibleWorks.map { it.id }.toSet()
                    }
                ) {
                    Text(
                        if (allSelected) "Deselect All" else "Select All",
                        color = palette.accent
                    )
                }
                IconButton(
                    onClick = {
                        isSelecting = false
                        selectedIds = emptySet()
                    }
                ) {
                    Icon(Icons.Filled.Check, contentDescription = "Done", tint = palette.accent)
                }
            } else {
                ToolbarAddButton(
                    onClick = { showAddPicker = true },
                    accessibilityName = "Add Works",
                    palette = palette
                )
                if (works.isNotEmpty()) {
                    FilterButton(
                        filtersActive = filtersActive,
                        badgeCount = filters.activeCount + (if (filterText.isNotBlank()) 1 else 0),
                        onClick = { showFilterDialog = true },
                        onClearFilters = ::clearFilters
                    )
                }
                Box {
                    ToolbarCircleButton(
                        onClick = { menuOpen = true },
                        accessibilityName = "More"
                    ) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        if (privacy.hideMatureContent) {
                            DropdownMenuItem(
                                text = { Text(if (reveal.revealAll) "Hide mature" else "Show mature") },
                                leadingIcon = {
                                    Icon(
                                        if (reveal.revealAll) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                        contentDescription = null
                                    )
                                },
                                onClick = {
                                    menuOpen = false
                                    privacyGate.toggleRevealAll(activity)
                                }
                            )
                        }
                        if (works.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text("Select") },
                                leadingIcon = { Icon(Icons.Outlined.Checklist, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    isSelecting = true
                                }
                            )
                            if (works.size > 1) {
                                // Reorder draws every work in the collection: while Hide mode is keeping
                                // some out of sight it would put them back on screen (the queue page's rule).
                                val hidesMature = works.any {
                                    LibraryPrivacy.visibility(it, privacy, reveal) == LibraryPrivacyVisibility.Hidden
                                }
                                val canReorder = !filtersActive && !hidesMature
                                DropdownMenuItem(
                                    text = {
                                        Text(when {
                                            canReorder -> "Reorder"
                                            filtersActive -> "Clear Filters to Reorder"
                                            else -> "Show Mature to Reorder"
                                        })
                                    },
                                    leadingIcon = { Icon(Icons.Outlined.SwapVert, contentDescription = null) },
                                    enabled = canReorder,
                                    onClick = {
                                        menuOpen = false
                                        showReorder = true
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = {
                                    Text(if (displayMode == CollectionDisplayMode.Ledger) "Display · Detailed" else "Display · Ledger")
                                },
                                onClick = {
                                    menuOpen = false
                                    displayMode = if (displayMode == CollectionDisplayMode.Ledger) {
                                        CollectionDisplayMode.Detailed
                                    } else {
                                        CollectionDisplayMode.Ledger
                                    }
                                }
                            )
                            if (displayMode == CollectionDisplayMode.Detailed) DropdownMenuItem(
                                text = { Text(if (expandAll) "Collapse All" else "Expand All") },
                                onClick = { expandAll = !expandAll; menuOpen = false }
                            )
                            HorizontalDivider()
                        }
                        DropdownMenuItem(
                            text = { Text("Rename") },
                            leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                renameText = collection?.name.orEmpty()
                                showRename = true
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Details") },
                            onClick = {
                                menuOpen = false
                                showDetails = true
                            }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Delete Collection", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = {
                                Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                            },
                            onClick = {
                                menuOpen = false
                                confirmDeleteCollection = true
                            }
                        )
                    }
                }
            }
        }
    )

    DestructiveConfirmation(
        show = confirmDeleteCollection,
        title = "Delete “${collection?.name}”?",
        text = "Kudos will move this collection to Recently Deleted for 90 days. Its works will stay in your Library.",
        confirmText = "Delete",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = { deleteCollection() },
        onDismissRequest = { confirmDeleteCollection = false }
    )

    DestructiveConfirmation(
        show = pendingRemoveWork != null,
        title = "Remove this work?",
        text = "“${pendingRemoveWork?.title}” will no longer be in “${collection?.name}”. The work itself stays in your Library.",
        confirmText = "Remove",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = {
            val workId = pendingRemoveWork?.id ?: return@DestructiveConfirmation
            pendingRemoveWork = null
            removeWork(workId)
        },
        onDismissRequest = { pendingRemoveWork = null }
    )

    DestructiveConfirmation(
        show = confirmBulkRemove,
        title = if (selectedIds.size == 1) "Remove 1 work?" else "Remove ${selectedIds.size} works?",
        text = "Kudos will remove the selected works from this collection. They will stay in your Library.",
        confirmText = "Remove",
        confirmBeforeDelete = true,
        onConfirm = {
            confirmBulkRemove = false
            bulkRemove(selectedIds)
        },
        onDismissRequest = { confirmBulkRemove = false }
    )

    if (showRename) {
        AlertDialog(
            onDismissRequest = {
                if (!working) {
                    showRename = false
                    renameText = ""
                }
            },
            title = { Text("Rename Collection") },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    label = { Text("Name") },
                    singleLine = true,
                    enabled = !working,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = !working && renameText.trim().isNotEmpty(),
                    onClick = { renameCollection() }
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !working,
                    onClick = {
                        showRename = false
                        renameText = ""
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showFilterDialog) {
        LibraryFilterPanel(
            filters = filters, sort = sort, userTags = index.userTags, collections = index.collections,
            works = orderedWorks, searchQuery = filterText, onSearchQueryChange = { filterText = it },
            onFiltersChange = { filters = it }, onSortChange = { sort = it },
            onClear = ::clearFilters, onApply = { showFilterDialog = false },
            onDismiss = { showFilterDialog = false }
        )
    }

    if (showDetails && collection != null) {
        CollectionEditorSheet(
            workRepository = workRepository,
            existing = collection,
            downloadQueue = downloadQueue,
            onDismiss = { showDetails = false },
            onSaved = { updated ->
                collection = updated
                showDetails = false
                scope.launch { refresh() }
            }
        )
    }

    if (showReorder && collection != null) {
        CollectionReorderSheet(
            collection = collection!!,
            // The reading order the page shows, not newest-added: Done saved that over it (A62 F26).
            works = orderedWorks,
            workRepository = workRepository,
            onDismiss = { showReorder = false },
            onSaved = {
                showReorder = false
                scope.launch { refresh() }
            }
        )
    }

    if (showAddPicker) {
        val allSavedWorks by workRepository.observeLibraryWorks().collectAsState(initial = emptyList())
        val currentWorkIds = works.map { it.id }.toSet()
        val availableToAdd = WorkRepository.collectionCandidates(allSavedWorks, currentWorkIds)

        AddLibraryWorksSheet(
            destinationName = collection?.name.orEmpty(),
            scopeName = "collection",
            candidates = availableToAdd,
            privacy = privacy,
            reveal = reveal,
            onToggleMature = { privacyGate.toggleRevealAll(activity) },
            onDismiss = { showAddPicker = false },
            onAdd = { chosen ->
                showAddPicker = false
                addWorks(chosen.mapTo(linkedSetOf()) { it.id })
            }
        )
    }

    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        KudosRefreshBox(
            onRefresh = {
                refresh()
                metadataRefresh?.let { ref ->
                    works.forEach { runCatching { ref.refresh(it) } }
                    refresh()
                }
            },
            modifier = Modifier.fillMaxSize()
        ) {
            val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()

            when {
                loading && collection == null -> {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(top = topInset + 56.dp)
                    ) {
                        LoadingStateCard("Loading collection", Modifier.padding(16.dp))
                    }
                }
                error != null && collection == null -> {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(top = topInset + 56.dp)
                    ) {
                        ErrorStateCard("Collection unavailable", error.orEmpty(), Modifier.padding(16.dp))
                    }
                }
                works.isEmpty() -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(top = topInset + 56.dp, bottom = 16.dp)
                    ) {
                        item {
                            SubjectHeaderBlock(
                                kicker = "Library",
                                title = collection?.name ?: "Collection",
                                subtitle = tallyLine,
                                palette = palette,
                                modifier = Modifier.padding(bottom = 24.dp)
                            )
                        }
                        item {
                            EmptyStateCard(
                                title = collection?.name ?: "Collection",
                                message = "Add works from your Library here, or choose Add to Collection on a work's page.",
                                primaryActionLabel = "Add Works",
                                onPrimaryAction = { showAddPicker = true },
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(
                            top = topInset + 56.dp,
                            bottom = if (isSelecting) 96.dp else 24.dp
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        item {
                            SubjectHeaderBlock(
                                kicker = "Library",
                                title = collection?.name ?: "Collection",
                                subtitle = tallyLine,
                                palette = palette
                            )
                        }
                        item {
                            SectionRuleHeader(
                                title = "Works",
                                count = visibleWorks.size,
                                modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                            )
                        }
                        if (visibleWorks.isEmpty() && !filtersActive && works.isNotEmpty()) {
                            // Hide Mature has emptied the page on its own; that is not an empty
                            // collection, and the page said nothing (iOS says this since T-394).
                            item {
                                EmptyStateCard(
                                    title = "Mature works are hidden",
                                    message = "Hide Mature is hiding every work in this collection.",
                                    primaryActionLabel = "Show mature",
                                    onPrimaryAction = { privacyGate.toggleRevealAll(activity) },
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                            }
                        } else if (visibleWorks.isEmpty() && filtersActive) {
                            item {
                                EmptyStateCard(
                                    title = "No matching works",
                                    message = "Your filters don't match any works in this collection.",
                                    primaryActionLabel = "Clear Filters",
                                    onPrimaryAction = ::clearFilters,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                            }
                        } else {
                            items(visibleWorks, key = { it.id }) { work ->
                                CollectionWorkListItem(
                                    work = work,
                                    collection = collection!!,
                                    displayMode = displayMode,
                                    expandAll = expandAll,
                                    isSelecting = isSelecting,
                                    isSelected = work.id in selectedIds,
                                    obscured = LibraryPrivacy.visibility(work, privacy, reveal) ==
                                        LibraryPrivacyVisibility.Obscured,
                                    palette = palette,
                                    actions = workActions,
                                    onToggleSelection = {
                                        selectedIds = if (work.id in selectedIds) {
                                            selectedIds - work.id
                                        } else {
                                            selectedIds + work.id
                                        }
                                    },
                                    onOpenWork = { onOpenWork(work.id) },
                                    onOpenReader = {
                                        if (work.hasEpub) onOpenReader(work.id) else onOpenWork(work.id)
                                    },
                                    onReveal = { privacyGate.reveal(work.id, activity) },
                                    onRemove = {
                                        if (confirmBeforeDelete) {
                                            pendingRemoveWork = work
                                        } else {
                                            removeWork(work.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        if (isSelecting) {
            // iOS `ScopedRemovalBulkActionBar`: Remove, and an Actions menu (brief 3ck).
            ScopedSelectionBar(
                selectedWorks = works.filter { it.id in selectedIds },
                removeLabel = "Remove from Collection",
                scopeName = "collection",
                workRepository = workRepository,
                workImporter = workImporter,
                queueRepository = queueRepository,
                downloadQueue = downloadQueue,
                palette = palette,
                onRemove = { selectedIds.forEach { workRepository.removeFromCollection(it, collectionId) } },
                // This page asks in its own dialog, which honours "Confirm before delete".
                onRequestRemove = { confirmBulkRemove = true },
                onChanged = { scope.launch { refresh() } },
                onDone = {
                    isSelecting = false
                    selectedIds = emptySet()
                    scope.launch { refresh() }
                },
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CollectionWorkListItem(
    work: SavedWork,
    collection: WorkCollection,
    displayMode: CollectionDisplayMode,
    expandAll: Boolean,
    isSelecting: Boolean,
    isSelected: Boolean,
    obscured: Boolean,
    palette: SubjectPalette,
    actions: LibraryCardActions,
    onToggleSelection: () -> Unit,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit,
    onReveal: () -> Unit,
    onRemove: () -> Unit
) {
    var menuOpen by remember(work.id) { mutableStateOf(false) }

    val rowContent = @Composable {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (isSelecting) {
                WorkSelectionBubble(
                    isSelected = isSelected,
                    palette = palette
                )
            }
            Box(Modifier.weight(1f)) {
                // Detailed is the full card and Ledger the dense row, as on iOS. They were the
                // other way round, so a collection opened on the dense row under "Detailed".
                if (displayMode == CollectionDisplayMode.Detailed) {
                    val progress = work.readingProgressFraction() ?: 0.0
                    SensitiveWorkRow(
                        work = work,
                        expandAll = expandAll,
                        onOpenWork = { 
                            if (work.hasEpub) onOpenReader() else onOpenWork()
                        },
                        selected = isSelecting && isSelected,
                        selecting = isSelecting,
                        obscured = obscured,
                        onReveal = onReveal,
                        onSelect = onToggleSelection,
                        onLongClick = {
                            // Not on a blurred work: its menu opens what the blur hides.
                            if (!isSelecting && !obscured) menuOpen = true
                        },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                } else {
                    // The row Home's lists draw (iOS `WorkRow.ledger`): the reading ring, the
                    // kicker and the tray. This page had a thinner copy of its own.
                    WorkLedgerRow(
                        downloadFraction = io.github.cidy02.kudos.ui.subject.rememberWorkDownloadFraction(work),
                        title = work.title,
                        author = work.author.ifBlank { "Anonymous" },
                        fandoms = work.workFandoms,
                        metadata = HomeFacts.localWorkMetadata(work.author, work.wordCount, work.chapters)
                            .joinToString(" · "),
                        progress = work.readingProgressFraction() ?: 0.0,
                        progressState = when {
                            work.isFinished -> "Finished"
                            work.readingProgressFraction() != null -> "Reading"
                            else -> null
                        },
                        rating = work.rating,
                        categories = work.workCategories,
                        warnings = work.workWarnings,
                        isComplete = work.knownCompletion,
                        obscured = obscured,
                        favorite = work.isFavorite,
                        selected = isSelecting && isSelected,
                        onClick = {
                            when {
                                isSelecting -> onToggleSelection()
                                obscured -> onReveal()
                                work.hasEpub -> onOpenReader()
                                else -> onOpenWork()
                            }
                        },
                        onLongClick = {
                            // Not on a blurred work: its menu opens what the blur hides.
                            if (!isSelecting && !obscured) menuOpen = true
                        }
                    )
                }
            }
        }
    }

    if (isSelecting || obscured) {
        rowContent()
    } else {
        SwipeActionRow(
            leading = emptyList(),
            trailing = listOf(
                SwipeAction(
                    label = "Remove",
                    icon = Icons.Outlined.Delete,
                    color = MaterialTheme.colorScheme.error,
                    onClick = onRemove
                )
            ),
            content = rowContent
        )
    }

    LibraryWorkMenu(
        expanded = menuOpen, onDismiss = { menuOpen = false }, work = work, actions = actions,
        scopedRemovalLabel = "Remove from Collection", onScopedRemove = onRemove
    )
}
