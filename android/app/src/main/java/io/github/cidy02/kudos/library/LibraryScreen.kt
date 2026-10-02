package io.github.cidy02.kudos.library

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.DownloadDone
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Queue
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.AlertDialog
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.core.model.WorkDownloadSemantics
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.LocalShellOverlayState
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.WorkCardCarousel
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow as SubjectWorkLedgerRow
import io.github.cidy02.kudos.ui.subject.WorkSectionLayout
import io.github.cidy02.kudos.ui.subject.defaultWorkSignals
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

private const val ShelfLimit = 12

/**
 * Library dashboard — Material expression of Apple Library:
 * fandom chips · collapsible cover carousels · Reading Queues / Collections create tiles ·
 * Reading History · toolbar pill (privacy / select / overflow) · long-press context menu.
 */
@Composable
fun LibraryScreen(
    repository: LibraryRepository,
    workRepository: WorkRepository,
    workImporter: WorkImporter? = null,
    settingsRepository: SettingsRepository? = null,
    queueRepository: ReadingQueueRepository? = null,
    downloadQueue: DownloadQueue? = null,
    privacyGate: PrivacyGate = PrivacyGate(),
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit = {},
    onOpenReadingQueues: () -> Unit = {},
    onOpenReadingStatistics: () -> Unit = {},
    onOpenCollections: () -> Unit = {},
    onOpenQueue: (String) -> Unit = {},
    onOpenCollection: (String) -> Unit = {},
    onOpenComments: (Long) -> Unit = {},
    section: LibrarySectionKind? = null,
    onOpenSection: (LibrarySectionKind) -> Unit = {},
    libraryChrome: LibraryShellChrome? = null
) {
    val viewModel: LibraryViewModel = viewModel(
        factory = LibraryViewModel.factory(
            repository,
            workRepository,
            settingsRepository,
            queueRepository,
            downloadQueue,
            privacyGate
        )
    )
    val state by viewModel.state.collectAsState()
    val shellOverlay = LocalShellOverlayState.current
    DisposableEffect(state.selectionMode, section) {
        shellOverlay.hidesTabBar = state.selectionMode
        onDispose {
            shellOverlay.hidesTabBar = false
        }
    }
    val localContext = LocalContext.current
    val activity = localContext as? androidx.fragment.app.FragmentActivity
    val scope = rememberCoroutineScope()
    var confirmBulkRemove by remember { mutableStateOf(false) }
    var confirmRemoveOne by remember { mutableStateOf<String?>(null) }
    var createQueueName by remember { mutableStateOf<String?>(null) }
    var createCollectionName by remember { mutableStateOf<String?>(null) }
    var addToQueueWorkId by remember { mutableStateOf<String?>(null) }
    var addToCollectionWorkId by remember { mutableStateOf<String?>(null) }
    var bulkAddToQueueOpen by remember { mutableStateOf(false) }
    var bulkAddToCollectionOpen by remember { mutableStateOf(false) }
    var showFilters by remember { mutableStateOf(false) }
    var confirmRemoveFromHistory by remember { mutableStateOf<String?>(null) }
    var confirmDeleteCollection by remember { mutableStateOf<String?>(null) }
    val layoutPreferences = remember {
        localContext.getSharedPreferences("library-dashboard", android.content.Context.MODE_PRIVATE)
    }
    var dashboardLayout by remember {
        mutableStateOf(
            if (layoutPreferences.getString("layout", "shelves") == "ledger") {
                WorkSectionLayout.Ledger
            } else {
                WorkSectionLayout.Shelves
            }
        )
    }

    if (libraryChrome != null && section == null) {
        val selectableIds = remember(state.items) {
            state.items.mapTo(linkedSetOf()) { it.item.work.id }
        }
        val allSelected = selectableIds.isNotEmpty() &&
            state.selectedWorkIds.containsAll(selectableIds)
        val selectionTitle = if (state.selectionMode) {
            if (state.selectedCount == 0) "Select Works" else "${state.selectedCount} Selected"
        } else null
        SideEffect {
            libraryChrome.mounted = true
            libraryChrome.hideTabBar = state.selectionMode
            libraryChrome.selectionTitle = selectionTitle
            libraryChrome.allSelected = allSelected
            libraryChrome.showPrivacyToggle = state.showPrivacyToggle
            libraryChrome.revealAll = state.revealAllActive
            libraryChrome.hasSavedWorks = state.hasSavedWorks
            libraryChrome.filtersActive = state.hasActiveQueryOrFilters
            libraryChrome.filterBadgeCount = state.filters.activeCount + if (state.searchQuery.isBlank()) 0 else 1
            libraryChrome.layout = dashboardLayout
            libraryChrome.actions.onNewCollection = { createCollectionName = "" }
            libraryChrome.actions.onShowFilters = { showFilters = true }
            libraryChrome.actions.onSelectAll = {
                viewModel.setSelection(if (allSelected) emptySet() else selectableIds)
            }
            libraryChrome.actions.onEnterSelect = { viewModel.enterSelectionMode() }
            libraryChrome.actions.onTogglePrivacy = { viewModel.toggleRevealAll(activity) }
            libraryChrome.actions.onLayoutChange = { layout ->
                dashboardLayout = layout
                layoutPreferences.edit().putString(
                    "layout",
                    if (layout == WorkSectionLayout.Ledger) "ledger" else "shelves"
                ).apply()
            }
            libraryChrome.actions.onOpenReadingQueues = onOpenReadingQueues
            libraryChrome.actions.onOpenReadingStatistics = onOpenReadingStatistics
            libraryChrome.actions.onOpenRecentlyDeleted = onOpenRecentlyDeleted
        }
        DisposableEffect(libraryChrome) {
            onDispose { libraryChrome.reset() }
        }
    }

    if (bulkAddToQueueOpen) {
        AlertDialog(
            onDismissRequest = { bulkAddToQueueOpen = false },
            title = { Text("Add Selection to Queue") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (state.readingQueues.isEmpty()) {
                        Text("No custom queues yet.", style = MaterialTheme.typography.bodyMedium)
                    } else {
                        state.readingQueues.forEach { queue ->
                            TextButton(
                                onClick = {
                                    bulkAddToQueueOpen = false
                                    viewModel.bulkAddToQueue(queue.id)
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(queue.name, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { bulkAddToQueueOpen = false }) { Text("Close") } }
        )
    }

    if (bulkAddToCollectionOpen) {
        var newName by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { bulkAddToCollectionOpen = false },
            title = { Text("Add Selection to Collection") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("New or existing collection") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (state.collections.isNotEmpty()) {
                        Text("Existing collections:", style = MaterialTheme.typography.labelMedium)
                        state.collections.forEach { col ->
                            TextButton(
                                onClick = {
                                    bulkAddToCollectionOpen = false
                                    viewModel.bulkAddToCollection(col.name)
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(col.name, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = newName.trim().isNotEmpty(),
                    onClick = {
                        val name = newName.trim()
                        bulkAddToCollectionOpen = false
                        viewModel.bulkAddToCollection(name)
                    }
                ) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { bulkAddToCollectionOpen = false }) { Text("Cancel") } }
        )
    }

    DestructiveConfirmation(
        show = confirmBulkRemove,
        title = if (state.selectedCount == 1) "Delete 1 work?" else "Delete ${state.selectedCount} works?",
        text = "Selected works move to Recently Deleted for 90 days.",
        confirmText = "Delete",
        confirmBeforeDelete = state.confirmBeforeDelete,
        onConfirm = {
            confirmBulkRemove = false
            viewModel.bulkSoftDelete()
        },
        onDismissRequest = { confirmBulkRemove = false }
    )

    DestructiveConfirmation(
        show = confirmRemoveFromHistory != null,
        title = "Remove this work?",
        text = "This work will leave your reading history. Reading it again brings it back.",
        confirmText = "Remove",
        confirmBeforeDelete = true,
        onConfirm = {
            val workId = confirmRemoveFromHistory ?: return@DestructiveConfirmation
            confirmRemoveFromHistory = null
            viewModel.removeFromHistoryOne(workId)
        },
        onDismissRequest = { confirmRemoveFromHistory = null }
    )

    DestructiveConfirmation(
        show = confirmDeleteCollection != null,
        title = "Delete this collection?",
        text = "Kudos will move this collection to Recently Deleted for 90 days. Its works will stay in your Library.",
        confirmText = "Delete",
        confirmBeforeDelete = true,
        onConfirm = {
            val collectionId = confirmDeleteCollection ?: return@DestructiveConfirmation
            confirmDeleteCollection = null
            viewModel.deleteCollection(collectionId)
        },
        onDismissRequest = { confirmDeleteCollection = null }
    )

    DestructiveConfirmation(
        show = confirmRemoveOne != null,
        title = "Delete this work?",
        text = "This work moves to Recently Deleted for 90 days.",
        confirmText = "Delete",
        confirmBeforeDelete = state.confirmBeforeDelete,
        onConfirm = {
            val workId = confirmRemoveOne ?: return@DestructiveConfirmation
            confirmRemoveOne = null
            viewModel.softDeleteOne(workId)
        },
        onDismissRequest = { confirmRemoveOne = null }
    )

    createQueueName?.let { draft ->
        AlertDialog(
            onDismissRequest = { createQueueName = null },
            title = { Text("New Queue") },
            text = {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { createQueueName = it },
                    label = { Text("Queue name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = draft.trim().isNotEmpty(),
                    onClick = {
                        val name = draft.trim()
                        createQueueName = null
                        viewModel.createQueue(name) { id -> onOpenQueue(id) }
                    }
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { createQueueName = null }) { Text("Cancel") }
            }
        )
    }

    createCollectionName?.let { draft ->
        AlertDialog(
            onDismissRequest = { createCollectionName = null },
            title = { Text("New Collection") },
            text = {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { createCollectionName = it },
                    label = { Text("Collection name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = draft.trim().isNotEmpty(),
                    onClick = {
                        val name = draft.trim()
                        createCollectionName = null
                        viewModel.createCollection(name) { id -> onOpenCollection(id) }
                    }
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { createCollectionName = null }) { Text("Cancel") }
            }
        )
    }

    addToQueueWorkId?.let { workId ->
        AlertDialog(
            onDismissRequest = { addToQueueWorkId = null },
            title = { Text("Add to Queue") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (state.readingQueues.isEmpty()) {
                        Text(
                            "No queues yet. Create one from Reading Queues.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        state.readingQueues.forEach { queue ->
                            TextButton(
                                onClick = {
                                    addToQueueWorkId = null
                                    viewModel.addToQueue(workId, queue.id)
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(queue.name, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { addToQueueWorkId = null }) { Text("Close") }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        addToQueueWorkId = null
                        onOpenReadingQueues()
                    }
                ) { Text("Manage queues") }
            }
        )
    }

    addToCollectionWorkId?.let { workId ->
        // Checklist of existing shelves + create-new (iOS AddToCollectionView).
        // Membership is tracked locally because Library snapshot only re-emits when
        // the works Flow changes, not on cross-ref-only membership toggles.
        var newName by remember(workId) { mutableStateOf("") }
        var memberIds by remember(workId) { mutableStateOf<Set<String>>(emptySet()) }
        var membershipLoaded by remember(workId) { mutableStateOf(false) }
        LaunchedEffect(workId) {
            membershipLoaded = false
            memberIds = runCatching {
                workRepository.collectionsForWork(workId).map { it.id }.toSet()
            }.getOrDefault(emptySet())
            membershipLoaded = true
        }
        AlertDialog(
            onDismissRequest = { addToCollectionWorkId = null },
            title = { Text("Add to Collection") },
            text = {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 420.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = newName,
                            onValueChange = { newName = it },
                            label = { Text("New collection") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(
                            enabled = newName.trim().isNotEmpty(),
                            onClick = {
                                val name = newName.trim()
                                if (name.isEmpty()) return@TextButton
                                newName = ""
                                // Create-or-match by name and attach; update local
                                // checklist from the returned membership list.
                                scope.launch {
                                    val updated = runCatching {
                                        workRepository.addToCollection(workId, name)
                                    }.getOrDefault(emptyList())
                                    memberIds = updated.map { it.id }.toSet()
                                }
                            }
                        ) { Text("Add") }
                    }
                    if (state.collections.isEmpty()) {
                        Text(
                            "No collections yet. Create one above to start grouping works.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Text(
                            text = "Collections",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        state.collections
                            .sortedBy { it.name.lowercase() }
                            .forEach { collection ->
                                val isMember = collection.id in memberIds
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable(enabled = membershipLoaded) {
                                            val next = !isMember
                                            memberIds = if (next) {
                                                memberIds + collection.id
                                            } else {
                                                memberIds - collection.id
                                            }
                                            viewModel.setCollectionMembership(
                                                workId,
                                                collection.id,
                                                member = next
                                            )
                                        }
                                        .padding(vertical = 2.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Checkbox(
                                        checked = isMember,
                                        onCheckedChange = null,
                                        enabled = membershipLoaded
                                    )
                                    Text(
                                        text = collection.name,
                                        style = MaterialTheme.typography.bodyLarge,
                                        modifier = Modifier.weight(1f)
                                    )
                                    Text(
                                        text = collection.workIds.size.toString(),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { addToCollectionWorkId = null }) { Text("Done") }
            }
        )
    }

    LibraryContent(
        state = state,
        section = section,
        dashboardLayout = dashboardLayout,
        onLayoutChange = { layout ->
            dashboardLayout = layout
            layoutPreferences.edit().putString(
                "layout",
                if (layout == WorkSectionLayout.Ledger) "ledger" else "shelves"
            ).apply()
        },
        onShowFilters = { showFilters = true },
        onUpdateSearchQuery = viewModel::updateSearchQuery,
        onUpdateSort = viewModel::updateSort,
        onSetFandomFilter = viewModel::setFandomFilter,
        onClearFilters = viewModel::clearFilters,
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onOpenReadingQueues = onOpenReadingQueues,
        onOpenRecentlyDeleted = onOpenRecentlyDeleted,
        onOpenReadingStatistics = onOpenReadingStatistics,
        onOpenCollections = onOpenCollections,
        onOpenQueue = onOpenQueue,
        onOpenCollection = onOpenCollection,
        onOpenSection = onOpenSection,
        onCreateQueue = { createQueueName = "" },
        onCreateCollection = { createCollectionName = "" },
        onEnterSelection = { viewModel.enterSelectionMode() },
        onExitSelection = viewModel::exitSelectionMode,
        onToggleSelection = viewModel::toggleWorkSelection,
        onSetSelection = viewModel::setSelection,
        onBulkFavorite = { viewModel.bulkSetFavorite(true) },
        onBulkUnfavorite = { viewModel.bulkSetFavorite(false) },
        onBulkSave = { viewModel.bulkSetSaved(true) },
        onBulkUnsave = { viewModel.bulkSetSaved(false) },
        onBulkAddToQueue = { bulkAddToQueueOpen = true },
        onBulkAddToCollection = { bulkAddToCollectionOpen = true },
        onBulkMarkFinished = { viewModel.bulkSetFinished(true) },
        onBulkMarkUnfinished = { viewModel.bulkSetFinished(false) },
        onBulkRemove = { confirmBulkRemove = true },
        onBulkSaveForLater = viewModel::bulkAddToSaveForLater,
        onBulkRemoveFromSaveForLater = viewModel::bulkRemoveFromSaveForLater,
        onToggleFavoriteOne = viewModel::toggleFavoriteOne,
        onToggleFinishedOne = viewModel::toggleFinishedOne,
        onRemoveOne = { confirmRemoveOne = it },
        onRemoveFromHistory = { confirmRemoveFromHistory = it },
        onRemoveFromAllQueues = viewModel::removeFromAllQueuesOne,
        onDeleteCollection = { confirmDeleteCollection = it },
        onDownloadAction = viewModel::performDownloadAction,
        onToggleSavedForLaterOne = viewModel::toggleSavedForLaterOne,
        onRevealWork = { viewModel.revealWork(it, activity) },
        onAddToQueue = { addToQueueWorkId = it },
        onAddToCollection = { addToCollectionWorkId = it },
        onOpenComments = onOpenComments,
        canRebuildFromOriginal = { work ->
            workImporter?.canRebuildFromOriginal(work) == true
        },
        onRebuildFromOriginal = { work ->
            workImporter?.let { importer ->
                scope.launch { importer.rebuildFromOriginal(work) }
            }
        },
        onTogglePrivacy = { viewModel.toggleRevealAll(activity) },
        onRefresh = { viewModel.refresh() }
    )

    if (showFilters) {
        LibraryFilterPanel(
            filters = state.filters,
            sort = state.sort,
            userTags = state.userTags,
            collections = state.collections,
            onFiltersChange = viewModel::updateFilters,
            onSortChange = viewModel::updateSort,
            onApply = { showFilters = false },
            onClear = viewModel::clearFilters,
            onDismiss = { showFilters = false },
            searchQuery = state.searchQuery,
            onSearchQueryChange = viewModel::updateSearchQuery
        )
    }
}

@Composable
private fun LibraryContent(
    state: LibraryUiState,
    section: LibrarySectionKind?,
    dashboardLayout: WorkSectionLayout,
    onLayoutChange: (WorkSectionLayout) -> Unit,
    onShowFilters: () -> Unit,
    onUpdateSearchQuery: (String) -> Unit,
    onUpdateSort: (LibrarySort) -> Unit,
    onSetFandomFilter: (String?) -> Unit,
    onClearFilters: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit,
    onOpenReadingQueues: () -> Unit,
    onOpenReadingStatistics: () -> Unit,
    onOpenCollections: () -> Unit,
    onOpenQueue: (String) -> Unit,
    onOpenCollection: (String) -> Unit,
    onOpenSection: (LibrarySectionKind) -> Unit,
    onCreateQueue: () -> Unit,
    onCreateCollection: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onToggleSelection: (String) -> Unit,
    onSetSelection: (Set<String>) -> Unit,
    onBulkFavorite: () -> Unit,
    onBulkUnfavorite: () -> Unit,
    onBulkSave: () -> Unit,
    onBulkUnsave: () -> Unit,
    onBulkAddToQueue: () -> Unit,
    onBulkAddToCollection: () -> Unit,
    onBulkMarkFinished: () -> Unit,
    onBulkMarkUnfinished: () -> Unit,
    onBulkRemove: () -> Unit,
    onBulkSaveForLater: () -> Unit,
    onBulkRemoveFromSaveForLater: () -> Unit,
    onToggleFavoriteOne: (String) -> Unit,
    onToggleFinishedOne: (String) -> Unit,
    onRemoveOne: (String) -> Unit,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit,
    onDeleteCollection: (String) -> Unit,
    onDownloadAction: (String, WorkDownloadAction) -> Unit,
    onToggleSavedForLaterOne: (String, Boolean) -> Unit = { _, _ -> },
    onRevealWork: (String) -> Unit,
    onAddToQueue: (String) -> Unit,
    onAddToCollection: (String) -> Unit,
    onOpenComments: (Long) -> Unit,
    canRebuildFromOriginal: suspend (SavedWork) -> Boolean,
    onRebuildFromOriginal: (SavedWork) -> Unit,
    onTogglePrivacy: () -> Unit,
    onRefresh: suspend () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val collapsed = io.github.cidy02.kudos.ui.components.rememberCollapsedSections()
    val bottomPad = if (state.selectionMode) 88.dp else 12.dp
    val cardActions = LibraryCardActions(
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onToggleFavorite = onToggleFavoriteOne,
        onToggleFinished = onToggleFinishedOne,
        onRemove = onRemoveOne,
        onDownloadAction = onDownloadAction,
        onToggleSavedForLater = onToggleSavedForLaterOne,
        onSelect = { id ->
            if (!state.selectionMode) onEnterSelection()
            onToggleSelection(id)
        },
        onReveal = onRevealWork,
        onAddToQueue = onAddToQueue,
        onAddToCollection = onAddToCollection,
        onOpenComments = onOpenComments,
        canRebuildFromOriginal = canRebuildFromOriginal,
        onRebuildFromOriginal = onRebuildFromOriginal
    )

    if (section != null) {
        LibrarySectionContent(
            kind = section,
            state = state,
            cardActions = cardActions,
            onShowFilters = onShowFilters,
            onTogglePrivacy = onTogglePrivacy,
            onEnterSelection = onEnterSelection,
            onExitSelection = onExitSelection,
            onToggleSelection = onToggleSelection,
            onSetSelection = onSetSelection,
            onBulkFavorite = onBulkFavorite,
            onBulkUnfavorite = onBulkUnfavorite,
            onBulkSave = onBulkSave,
            onBulkUnsave = onBulkUnsave,
            onBulkAddToQueue = onBulkAddToQueue,
            onBulkAddToCollection = onBulkAddToCollection,
            onBulkMarkFinished = onBulkMarkFinished,
            onBulkMarkUnfinished = onBulkMarkUnfinished,
            onBulkRemove = onBulkRemove,
            onBulkSaveForLater = onBulkSaveForLater,
            onBulkRemoveFromSaveForLater = onBulkRemoveFromSaveForLater,
            onRemoveFromHistory = onRemoveFromHistory,
            onRemoveFromAllQueues = onRemoveFromAllQueues,
            onRefresh = onRefresh
        )
        return
    }

    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        KudosRefreshBox(onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 8.dp,
                bottom = bottomPad
            ),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            if (state.loading) {
                item {
                    LoadingStateCard(
                        "Loading your Library",
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
                return@LazyColumn
            }

            state.error?.let { error ->
                item {
                    ErrorStateCard(
                        title = "Library could not load",
                        message = error,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
                return@LazyColumn
            }

            if (!state.selectionMode &&
                (state.topFandoms.isNotEmpty() || state.filters.hasActiveFilters)
            ) {
                item {
                    FandomFilterChips(
                        topFandoms = state.topFandoms,
                        selectedFandom = state.filters.fandoms.singleOrNull(),
                        hasActiveFilters = state.filters.hasActiveFilters,
                        onSelectAll = { onSetFandomFilter(null) },
                        onSelectFandom = { onSetFandomFilter(it) },
                        onReset = onClearFilters,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            }

            if (state.selectionMode) {
                items(state.items, key = { "sel-${it.item.work.id}" }) { display ->
                    SelectableWorkRow(
                        display = display,
                        selected = display.item.work.id in state.selectedWorkIds,
                        onToggle = { onToggleSelection(display.item.work.id) },
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            } else {
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.ReadingNow,
                        items = state.continueReading,
                        layout = dashboardLayout,
                        collapsed = collapsed["readingNow"],
                        onToggleCollapsed = { collapsed.toggle("readingNow") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.ReadingNow) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.SavedForLater,
                        items = state.savedForLater,
                        layout = dashboardLayout,
                        collapsed = collapsed["savedForLater"],
                        onToggleCollapsed = { collapsed.toggle("savedForLater") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.SavedForLater) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.Finished,
                        items = state.finished,
                        layout = dashboardLayout,
                        collapsed = collapsed["finished"],
                        onToggleCollapsed = { collapsed.toggle("finished") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.Finished) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                item {
                    CollectionsShelf(
                        collections = state.collections,
                        allItems = state.items,
                        layout = dashboardLayout,
                        collapsed = collapsed["collections"],
                        onToggleCollapsed = { collapsed.toggle("collections") },
                        onSeeAll = onOpenCollections,
                        onOpenCollection = onOpenCollection,
                        onDeleteCollection = onDeleteCollection
                    )
                }
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.Downloaded,
                        items = state.downloaded,
                        layout = dashboardLayout,
                        collapsed = collapsed["downloaded"],
                        onToggleCollapsed = { collapsed.toggle("downloaded") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.Downloaded) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.History,
                        items = state.readingHistory,
                        layout = dashboardLayout,
                        collapsed = collapsed["history"],
                        onToggleCollapsed = { collapsed.toggle("history") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.History) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                item {
                    LibraryDashboardWorkSection(
                        kind = LibrarySectionKind.Favorites,
                        items = state.favorites,
                        layout = dashboardLayout,
                        collapsed = collapsed["favorites"],
                        onToggleCollapsed = { collapsed.toggle("favorites") },
                        onSeeAll = { onOpenSection(LibrarySectionKind.Favorites) },
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
                if (state.recentlyDeletedCount > 0) {
                    item {
                        RecentlyDeletedRow(
                            count = state.recentlyDeletedCount,
                            onClick = onOpenRecentlyDeleted
                        )
                    }
                }
            }
        }
        }

        if (state.selectionMode) {
            LibrarySelectionActionBar(
                hasSelection = state.hasSelection,
                onFavorite = onBulkFavorite,
                onUnfavorite = onBulkUnfavorite,
                onSave = onBulkSave,
                onUnsave = onBulkUnsave,
                onAddToQueue = onBulkAddToQueue,
                onAddToCollection = onBulkAddToCollection,
                onMarkFinished = onBulkMarkFinished,
                onMarkUnfinished = onBulkMarkUnfinished,
                onRemove = onBulkRemove,
                onSaveForLater = onBulkSaveForLater,
                onRemoveFromSaveForLater = onBulkRemoveFromSaveForLater,
                onCancel = onExitSelection,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun LibraryDashboardWorkSection(
    kind: LibrarySectionKind,
    items: List<LibraryDisplayItem>,
    layout: WorkSectionLayout,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: () -> Unit,
    actions: LibraryCardActions,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit
) {
    io.github.cidy02.kudos.ui.subject.WorkCarouselSection(
        title = kind.title,
        count = items.size,
        collapsed = collapsed,
        onToggleCollapsed = onToggleCollapsed,
        onSeeAll = onSeeAll,
        emptyMessage = kind.emptyMessage,
        layout = layout
    ) {
        if (layout == WorkSectionLayout.Shelves) {
            WorkCardCarousel(items.take(ShelfLimit), key = { it.item.work.id }) { display ->
                LibrarySubjectWorkCard(display, kind, actions)
            }
        } else {
            Column(
                Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items.take(ShelfLimit).forEach { display ->
                    LibrarySubjectLedgerRow(
                        display = display,
                        kind = kind,
                        actions = actions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LibrarySubjectWorkCard(
    display: LibraryDisplayItem,
    kind: LibrarySectionKind,
    actions: LibraryCardActions,
    selected: Boolean = false,
    selecting: Boolean = false
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    val progress = work.readingProgressFraction() ?: 0.0
    Box {
        Box(
            Modifier.combinedClickable(
                onClick = {
                    when {
                        selecting -> actions.onSelect(work.id)
                        obscured -> actions.onReveal(work.id)
                        work.hasEpub -> actions.onOpenReader(work.id)
                        else -> actions.onOpenWork(work.id)
                    }
                },
                onLongClick = { if (!obscured && !selecting) menuOpen = true }
            )
        ) {
            SubjectWorkCoverCard(
                work = work,
                obscured = obscured,
                downloading = false,
                footer = if (kind == LibrarySectionKind.Finished) "Finished" else null,
                progress = if (kind == LibrarySectionKind.ReadingNow) progress else null,
                isSelecting = selecting,
                isSelected = selected
            )
        }
        LibraryWorkMenu(menuOpen, { menuOpen = false }, work, actions)
    }
}

@Composable
private fun LibrarySubjectLedgerRow(
    display: LibraryDisplayItem,
    kind: LibrarySectionKind,
    actions: LibraryCardActions,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit,
    selected: Boolean = false,
    selecting: Boolean = false
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    val progress = work.readingProgressFraction() ?: 0.0
    val row: @Composable () -> Unit = {
        SubjectWorkLedgerRow(
            title = work.title,
            author = work.author,
            fandoms = work.workFandoms,
            metadata = listOfNotNull(
                work.author.ifBlank { null },
                work.wordCount.takeIf { it > 0 }?.let(::compactWords),
                work.chapters.takeIf { it.isNotBlank() }
            ).joinToString(" · "),
            progress = progress,
            progressState = when {
                work.isFinished -> "Finished"
                progress > 0 -> "Reading"
                else -> null
            },
            signals = defaultWorkSignals(work.rating, work.workCategories, work.workWarnings, work.isComplete),
            obscured = obscured,
            favorite = kind == LibrarySectionKind.Favorites && work.isFavorite,
            selected = selected,
            onClick = {
                when {
                    selecting -> actions.onSelect(work.id)
                    obscured -> actions.onReveal(work.id)
                    work.hasEpub -> actions.onOpenReader(work.id)
                    else -> actions.onOpenWork(work.id)
                }
            },
            onLongClick = { if (!obscured && !selecting) menuOpen = true }
        )
    }
    if (selecting || obscured) {
        row()
    } else {
        SwipeActionRow(
            leading = leadingSwipeActions(work, kind, actions),
            trailing = trailingSwipeActions(work, kind, actions, onRemoveFromHistory, onRemoveFromAllQueues),
            content = row
        )
    }
    LibraryWorkMenu(menuOpen, { menuOpen = false }, work, actions)
}

@Composable
private fun leadingSwipeActions(
    work: SavedWork,
    kind: LibrarySectionKind,
    actions: LibraryCardActions
): List<SwipeAction> {
    val tokens = LocalKudosTokens.current
    return buildList {
        if (kind == LibrarySectionKind.History || kind == LibrarySectionKind.Favorites) {
            add(
                SwipeAction(
                    if (work.isQueuedForLater) "Unsave" else "Save for Later",
                    Icons.Outlined.Schedule,
                    tokens.accent
                ) { actions.onToggleSavedForLater(work.id, work.isQueuedForLater) }
            )
        }
        WorkDownloadSemantics.action(
            work.hasEpub,
            work.isDownloaded,
            work.hasAo3WorkId,
            work.keptOfflineBy
        )?.takeIf { it !is WorkDownloadAction.KeptBy }?.let { action ->
            add(
                SwipeAction(
                    if (action == WorkDownloadAction.RemoveDownload) "Remove Download" else "Download",
                    Icons.Outlined.CloudDownload,
                    Color(0xFF2E7D32)
                ) { actions.onDownloadAction(work.id, action) }
            )
        }
        if (kind != LibrarySectionKind.Favorites) {
            add(
                SwipeAction(
                    if (work.isFavorite) "Unfavorite" else "Favorite",
                    Icons.Outlined.Star,
                    Color(0xFFF9A825)
                ) { actions.onToggleFavorite(work.id) }
            )
        }
    }
}

@Composable
private fun trailingSwipeActions(
    work: SavedWork,
    kind: LibrarySectionKind,
    actions: LibraryCardActions,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit
): List<SwipeAction> = when {
    kind == LibrarySectionKind.Favorites -> listOf(
        SwipeAction("Unfavorite", Icons.Outlined.Star, Color(0xFFF9A825)) {
            actions.onToggleFavorite(work.id)
        }
    )
    kind == LibrarySectionKind.History -> listOf(
        SwipeAction("Remove", Icons.Outlined.RemoveCircleOutline, MaterialTheme.colorScheme.error) {
            onRemoveFromHistory(work.id)
        }
    )
    work.isQueueOnlyWork -> listOf(
        SwipeAction("Remove", Icons.Outlined.RemoveCircleOutline, MaterialTheme.colorScheme.error) {
            onRemoveFromAllQueues(work.id)
        }
    )
    else -> listOf(
        SwipeAction("Delete", Icons.Outlined.Delete, MaterialTheme.colorScheme.error) {
            actions.onRemove(work.id)
        }
    )
}

@Composable
private fun LibraryWorkMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    work: SavedWork,
    actions: LibraryCardActions
) {
    val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
    var canRebuild by remember(work.id) { mutableStateOf(false) }
    LaunchedEffect(expanded, work.id) {
        canRebuild = expanded && actions.canRebuildFromOriginal(work)
    }
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        if (work.hasEpub) {
            ContextMenuItem(Icons.AutoMirrored.Outlined.MenuBook, "Read", {
                onDismiss(); actions.onOpenReader(work.id)
            })
        }
        if (ao3Id != null) {
            ContextMenuItem(Icons.Outlined.Info, "Comments", {
                onDismiss(); actions.onOpenComments(ao3Id)
            })
        }
        ContextMenuItem(Icons.Outlined.Checklist, "Select", {
            onDismiss(); actions.onSelect(work.id)
        })
        WorkDownloadSemantics.action(
            work.hasEpub,
            work.isDownloaded,
            work.hasAo3WorkId,
            work.keptOfflineBy
        )?.let { action ->
            ContextMenuItem(
                if (action == WorkDownloadAction.RemoveDownload) Icons.Outlined.DownloadDone else Icons.Outlined.Download,
                when (action) {
                    WorkDownloadAction.Download -> "Download"
                    WorkDownloadAction.RemoveDownload -> "Remove Download"
                    is WorkDownloadAction.KeptBy -> "Kept Offline by ${action.name}"
                },
                { onDismiss(); actions.onDownloadAction(work.id, action) },
                enabled = action !is WorkDownloadAction.KeptBy
            )
        }
        ContextMenuItem(
            if (work.isFavorite) Icons.Outlined.Star else Icons.Outlined.StarBorder,
            if (work.isFavorite) "Unfavorite" else "Favorite",
            { onDismiss(); actions.onToggleFavorite(work.id) }
        )
        ContextMenuItem(Icons.Outlined.Schedule, if (work.isQueuedForLater) "Remove from Saved for Later" else "Save for Later", {
            onDismiss(); actions.onToggleSavedForLater(work.id, work.isQueuedForLater)
        })
        ContextMenuItem(Icons.AutoMirrored.Outlined.List, "Add to Queue", {
            onDismiss(); actions.onAddToQueue(work.id)
        })
        ContextMenuItem(Icons.Outlined.CheckCircle, if (work.isFinished) "Mark as Still Reading" else "Mark as Finished", {
            onDismiss(); actions.onToggleFinished(work.id)
        })
        ContextMenuItem(Icons.Outlined.Folder, "Add to Collection", {
            onDismiss(); actions.onAddToCollection(work.id)
        })
        if (canRebuild) {
            ContextMenuItem(Icons.Outlined.Build, "Rebuild from Original", {
                onDismiss(); actions.onRebuildFromOriginal(work)
            })
        }
        ContextMenuItem(Icons.Outlined.Info, "Work Details", {
            onDismiss(); actions.onOpenWork(work.id)
        })
        ContextMenuItem(Icons.Outlined.Delete, "Delete", {
            onDismiss(); actions.onRemove(work.id)
        }, destructive = true)
    }
}

@Composable
private fun LibrarySectionContent(
    kind: LibrarySectionKind,
    state: LibraryUiState,
    cardActions: LibraryCardActions,
    onShowFilters: () -> Unit,
    onTogglePrivacy: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onToggleSelection: (String) -> Unit,
    onSetSelection: (Set<String>) -> Unit,
    onBulkFavorite: () -> Unit,
    onBulkUnfavorite: () -> Unit,
    onBulkSave: () -> Unit,
    onBulkUnsave: () -> Unit,
    onBulkAddToQueue: () -> Unit,
    onBulkAddToCollection: () -> Unit,
    onBulkMarkFinished: () -> Unit,
    onBulkMarkUnfinished: () -> Unit,
    onBulkRemove: () -> Unit,
    onBulkSaveForLater: () -> Unit,
    onBulkRemoveFromSaveForLater: () -> Unit,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit,
    onRefresh: suspend () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val sectionItems = kind.items(state)
    val ids = sectionItems.mapTo(linkedSetOf()) { it.item.work.id }
    val allSelected = ids.isNotEmpty() && state.selectedWorkIds.containsAll(ids)
    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(tokens.scopePalette)
    ) {
        KudosRefreshBox(onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
            LazyColumn(
                contentPadding = PaddingValues(top = 12.dp, bottom = if (state.selectionMode) 94.dp else 18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    SubjectHeaderBlock(
                        kicker = "Library",
                        title = kind.title,
                        subtitle = "${sectionItems.size} ${if (sectionItems.size == 1) "work" else "works"}",
                        palette = tokens.scopePalette
                    )
                }
                item {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (state.selectionMode) {
                            TextButton(onClick = { onSetSelection(if (allSelected) emptySet() else ids) }) {
                                Text(if (allSelected) "Deselect All" else "Select All")
                            }
                        } else {
                            FilterButton(
                                filtersActive = state.hasActiveQueryOrFilters,
                                badgeCount = state.filters.activeCount + if (state.searchQuery.isBlank()) 0 else 1,
                                onClick = onShowFilters
                            )
                            if (state.showPrivacyToggle) {
                                IconButton(onClick = onTogglePrivacy) {
                                    Icon(
                                        if (state.revealAllActive) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                                        contentDescription = if (state.revealAllActive) "Hide mature works" else "Show mature works"
                                    )
                                }
                            }
                            IconButton(onClick = onEnterSelection, enabled = sectionItems.isNotEmpty()) {
                                Icon(Icons.Outlined.Checklist, contentDescription = "Select")
                            }
                        }
                    }
                }
                when {
                    state.loading -> item { LoadingStateCard("Loading ${kind.title}", Modifier.padding(horizontal = 16.dp)) }
                    state.error != null -> item {
                        ErrorStateCard(kind.title, state.error, Modifier.padding(horizontal = 16.dp))
                    }
                    sectionItems.isEmpty() -> item {
                        EmptyStateCard("Nothing here yet", kind.emptyMessage, Modifier.padding(horizontal = 16.dp))
                    }
                    else -> items(sectionItems, key = { "${kind.id}-${it.item.work.id}" }) { display ->
                        LibrarySubjectLedgerRow(
                            display = display,
                            kind = kind,
                            actions = cardActions,
                            onRemoveFromHistory = onRemoveFromHistory,
                            onRemoveFromAllQueues = onRemoveFromAllQueues,
                            selected = display.item.work.id in state.selectedWorkIds,
                            selecting = state.selectionMode
                        )
                    }
                }
            }
        }
        if (state.selectionMode) {
            LibrarySelectionActionBar(
                hasSelection = state.hasSelection,
                onFavorite = onBulkFavorite,
                onUnfavorite = onBulkUnfavorite,
                onSave = onBulkSave,
                onUnsave = onBulkUnsave,
                onAddToQueue = onBulkAddToQueue,
                onAddToCollection = onBulkAddToCollection,
                onMarkFinished = onBulkMarkFinished,
                onMarkUnfinished = onBulkMarkUnfinished,
                onRemove = onBulkRemove,
                onSaveForLater = onBulkSaveForLater,
                onRemoveFromSaveForLater = onBulkRemoveFromSaveForLater,
                onCancel = onExitSelection,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun RecentlyDeletedRow(count: Int, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .subjectPanel()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Outlined.Delete, contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(18.dp))
        Text("Recently Deleted", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Text(count.toString(), color = tokens.secondaryInk, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = tokens.tertiaryInk)
    }
}

private fun compactWords(count: Int): String = when {
    count >= 1_000_000 -> "${count / 1_000_000}.${(count % 1_000_000) / 100_000}M words"
    count >= 1_000 -> "${count / 1_000}K words"
    else -> "$count words"
}

data class LibraryCardActions(
    val onOpenWork: (String) -> Unit,
    val onOpenReader: (String) -> Unit,
    val onToggleFavorite: (String) -> Unit,
    val onToggleFinished: (String) -> Unit,
    val onRemove: (String) -> Unit,
    val onDownloadAction: (String, WorkDownloadAction) -> Unit,
    /** Toggle Saved for Later queue membership (not isSaved / Download). */
    val onToggleSavedForLater: (String, Boolean) -> Unit = { _, _ -> },
    val onSelect: (String) -> Unit,
    val onReveal: (String) -> Unit,
    val onAddToQueue: (String) -> Unit,
    val onAddToCollection: (String) -> Unit,
    val onOpenComments: (Long) -> Unit,
    val canRebuildFromOriginal: suspend (SavedWork) -> Boolean = { false },
    val onRebuildFromOriginal: (SavedWork) -> Unit = {}
)

/** Compact trailing pill: privacy eye · select · overflow (Insights / Select). */
@Composable
private fun LibraryToolbarPill(
    state: LibraryUiState,
    onOpenReadingStatistics: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onTogglePrivacy: () -> Unit,
    onOpenRecentlyDeleted: () -> Unit,
    onBulkRemoveFromSaveForLater: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
            " · $it hidden"
        }.orEmpty()
        Text(
            text = if (state.selectionMode) {
                if (state.hasSelection) "${state.selectedCount} selected" else "Select works"
            } else {
                "${state.totalSaved} works$hidden"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .weight(1f)
                .padding(end = 8.dp)
        )

        if (state.selectionMode) {
            TextButton(onClick = onExitSelection) { Text("Done") }
        } else {
            Surface(
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                tonalElevation = 1.dp,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(horizontal = 2.dp)
                ) {
                    if (state.showPrivacyToggle) {
                        IconButton(onClick = onTogglePrivacy) {
                            Icon(
                                // Reflects the session-only reveal-all state, not the
                                // persisted "Hide mature content" setting — tapping this
                                // never touches that setting. See LibraryUiState.revealAllActive.
                                imageVector = if (state.revealAllActive) {
                                    Icons.Filled.Visibility
                                } else {
                                    Icons.Filled.VisibilityOff
                                },
                                contentDescription = if (state.revealAllActive) {
                                    "Hide mature works"
                                } else {
                                    "Show mature works"
                                },
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                    if (state.hasSavedWorks) {
                        IconButton(onClick = onEnterSelection) {
                            Icon(
                                imageVector = Icons.Outlined.Checklist,
                                contentDescription = "Select",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                        var overflowOpen by remember { mutableStateOf(false) }
                        var selectionMoreOpen by remember { mutableStateOf(false) }
                        Box {
                            IconButton(onClick = { overflowOpen = true }) {
                                Icon(
                                    imageVector = Icons.Filled.MoreVert,
                                    contentDescription = "More",
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                            DropdownMenu(
                                expanded = overflowOpen,
                                onDismissRequest = { overflowOpen = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Remove from Save for Later") },
                                    onClick = {
                                        overflowOpen = false
                                        onBulkRemoveFromSaveForLater()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Reading Insights") },
                                    leadingIcon = {
                                        Icon(Icons.Outlined.BarChart, contentDescription = null)
                                    },
                                    onClick = {
                                        overflowOpen = false
                                        onOpenReadingStatistics()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Select") },
                                    leadingIcon = {
                                        Icon(Icons.Outlined.Checklist, contentDescription = null)
                                    },
                                    onClick = {
                                        overflowOpen = false
                                        onEnterSelection()
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Recently Deleted") },
                                    leadingIcon = {
                                        Icon(Icons.Outlined.Delete, contentDescription = null)
                                    },
                                    onClick = {
                                        overflowOpen = false
                                        onOpenRecentlyDeleted()
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FandomFilterChips(
    topFandoms: List<String>,
    selectedFandom: String?,
    hasActiveFilters: Boolean,
    onSelectAll: () -> Unit,
    onSelectFandom: (String) -> Unit,
    onReset: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (topFandoms.isNotEmpty()) {
            val allSelected = selectedFandom == null
            FilterChip(
                selected = allSelected,
                onClick = onSelectAll,
                label = { Text("All") },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimary
                )
            )
            topFandoms.forEach { fandom ->
                FilterChip(
                    selected = selectedFandom == fandom,
                    onClick = {
                        if (selectedFandom == fandom) onSelectAll() else onSelectFandom(fandom)
                    },
                    label = {
                        Text(
                            fandom,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                )
            }
        }
        if (hasActiveFilters) {
            TextButton(onClick = onReset) { Text("Reset") }
        }
    }
}

@Composable
private fun CollapsibleSectionHeader(
    title: String,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: (() -> Unit)? = null,
    showSeeAll: Boolean = false,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TextButton(
            onClick = onToggleCollapsed,
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(0.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Icon(
                    imageVector = if (collapsed) {
                        Icons.Filled.KeyboardArrowDown
                    } else {
                        Icons.Filled.KeyboardArrowUp
                    },
                    contentDescription = if (collapsed) "Expand $title" else "Collapse $title",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (showSeeAll && onSeeAll != null) {
            IconButton(onClick = onSeeAll) {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = "See all $title",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun LibraryCarousel(
    sectionKey: String,
    title: String,
    items: List<LibraryDisplayItem>,
    emptyMessage: String,
    showProgress: Boolean,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    actions: LibraryCardActions,
    footerFor: ((SavedWork) -> String?)? = null,
    onSeeAll: (() -> Unit)? = null
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CollapsibleSectionHeader(
            title = title,
            collapsed = collapsed,
            onToggleCollapsed = onToggleCollapsed,
            onSeeAll = onSeeAll,
            showSeeAll = items.isNotEmpty() && onSeeAll != null
        )
        AnimatedVisibility(visible = !collapsed) {
            if (items.isEmpty()) {
                EmptyStateCard(
                    title = "Nothing here yet",
                    message = emptyMessage,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            } else {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.shelfSpacing),
                    verticalAlignment = Alignment.Top,
                    modifier = Modifier.height(WorkCoverCardMetrics.height)
                ) {
                    items(items, key = { "$sectionKey-${it.item.work.id}" }) { display ->
                        LibraryCarouselCard(
                            display = display,
                            showProgress = showProgress,
                            footerOverride = footerFor?.invoke(display.item.work),
                            actions = actions
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryCarouselCard(
    display: LibraryDisplayItem,
    showProgress: Boolean,
    footerOverride: String?,
    actions: LibraryCardActions,
    modifier: Modifier = Modifier,
    isSelecting: Boolean = false,
    isSelected: Boolean = false,
    onToggleSelection: (() -> Unit)? = null
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)

    val progress = if (showProgress && !obscured && footerOverride == null) {
        work.readingProgressFraction()?.toFloat()
    } else {
        null
    }
    val progressLabel = progress?.let { value ->
        when {
            value >= 0.999f || work.isFinished -> "Finished"
            else -> "Reading  ${(value * 100).roundToInt()}%"
        }
    }

    Box(modifier = modifier) {
        WorkCoverCard(
            workId = io.github.cidy02.kudos.works.WorkTags.ao3WorkIdFromUrl(work.sourceUrl),
            title = work.title,
            author = work.author.ifBlank { "Anonymous" },
            fandom = work.workFandoms.firstOrNull { it.isNotBlank() },
            stats = if (obscured) {
                emptyList()
            } else {
                coverCardStats(
                    rating = work.rating,
                    chapters = work.chapters,
                    isComplete = work.isComplete,
                    wordCount = work.wordCount.takeIf { it > 0 },
                    kudos = null
                )
            },
            onOpen = {
                if (obscured) {
                    actions.onReveal(work.id)
                } else if (canRead) {
                    actions.onOpenReader(work.id)
                } else {
                    actions.onOpenWork(work.id)
                }
            },
            onOpenDetails = { actions.onOpenWork(work.id) },
            progress = progress,
            progressLabel = progressLabel,
            statusChips = if (obscured) {
                emptyList()
            } else {
                listOfNotNull(
                    footerOverride,
                    if (!work.isDownloaded) "Not downloaded" else null,
                    if (work.isFavorite) "Favorite" else null
                )
            },
            obscured = obscured,
            contentDescription = if (obscured) {
                "Hidden mature work. Activate to reveal."
            } else {
                "${if (canRead) "Read" else "Open"} ${work.title}"
            },
            onLongClick = { if (!obscured) menuOpen = true },
            isSelecting = isSelecting,
            isSelected = isSelected,
            onToggleSelection = onToggleSelection
        )
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false }
        ) {
            if (canRead) {
                ContextMenuItem(
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    label = "Read",
                    onClick = {
                        menuOpen = false
                        actions.onOpenReader(work.id)
                    }
                )
            }
            if (ao3Id != null) {
                ContextMenuItem(
                    icon = Icons.Outlined.Info,
                    label = "Comments",
                    onClick = {
                        menuOpen = false
                        actions.onOpenComments(ao3Id)
                    }
                )
            }
            ContextMenuItem(
                icon = Icons.Outlined.Checklist,
                label = "Select",
                onClick = {
                    menuOpen = false
                    actions.onSelect(work.id)
                }
            )
            WorkDownloadSemantics.action(
                hasEpub = work.hasEpub,
                isDownloaded = work.isDownloaded,
                hasAo3WorkId = work.hasAo3WorkId,
                keptBy = work.keptOfflineBy
            )?.let { action ->
                ContextMenuItem(
                    icon = if (action == WorkDownloadAction.RemoveDownload) {
                        Icons.Outlined.DownloadDone
                    } else {
                        Icons.Outlined.Download
                    },
                    label = when (action) {
                        WorkDownloadAction.Download -> "Download"
                        WorkDownloadAction.RemoveDownload -> "Remove Download"
                        is WorkDownloadAction.KeptBy -> "Kept Offline by ${action.name}"
                    },
                    enabled = action !is WorkDownloadAction.KeptBy,
                    onClick = {
                        menuOpen = false
                        actions.onDownloadAction(work.id, action)
                    }
                )
            }
            ContextMenuItem(
                icon = Icons.Outlined.Schedule,
                label = if (work.isQueuedForLater) "Remove from Saved for Later" else "Save for Later",
                onClick = {
                    menuOpen = false
                    actions.onToggleSavedForLater(work.id, work.isQueuedForLater)
                }
            )
            ContextMenuItem(
                icon = if (work.isFavorite) Icons.Outlined.Star else Icons.Outlined.StarBorder,
                label = if (work.isFavorite) "Unfavorite" else "Favorite",
                onClick = {
                    menuOpen = false
                    actions.onToggleFavorite(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.AutoMirrored.Outlined.List,
                label = "Add to Queue",
                onClick = {
                    menuOpen = false
                    actions.onAddToQueue(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.Outlined.CheckCircle,
                label = if (work.isFinished) "Mark unfinished" else "Mark as Finished",
                onClick = {
                    menuOpen = false
                    actions.onToggleFinished(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.Outlined.Folder,
                label = "Add to Collection",
                onClick = {
                    menuOpen = false
                    actions.onAddToCollection(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.Outlined.Info,
                label = "Work Details",
                onClick = {
                    menuOpen = false
                    actions.onOpenWork(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.Outlined.Delete,
                label = "Remove",
                onClick = {
                    menuOpen = false
                    actions.onRemove(work.id)
                },
                destructive = true
            )
        }
    }
}

@Composable
private fun ContextMenuItem(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    destructive: Boolean = false,
    enabled: Boolean = true
) {
    DropdownMenuItem(
        text = {
            Text(
                label,
                color = if (destructive) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
        },
        leadingIcon = {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (destructive) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.primary
                }
            )
        },
        onClick = onClick,
        enabled = enabled
    )
}

@Composable
private fun ReadingQueuesShelf(
    queues: List<LibraryQueuePreview>,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: () -> Unit,
    onCreate: () -> Unit,
    onOpenQueue: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CollapsibleSectionHeader(
            title = "Reading Queues",
            collapsed = collapsed,
            onToggleCollapsed = onToggleCollapsed,
            onSeeAll = onSeeAll,
            showSeeAll = true
        )
        AnimatedVisibility(visible = !collapsed) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.shelfSpacing),
                verticalAlignment = Alignment.Top
            ) {
                item(key = "new-queue") {
                    CreateShelfTile(
                        title = "New Queue",
                        subtitle = "Tap to create",
                        onClick = onCreate
                    )
                }
                items(queues, key = { "queue-${it.id}" }) { queue ->
                    NamedShelfTile(
                        title = queue.name,
                        subtitle = when (queue.workCount) {
                            0 -> "Empty"
                            1 -> "1 work"
                            else -> "${queue.workCount} works"
                        },
                        onClick = { onOpenQueue(queue.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionsShelf(
    collections: List<WorkCollection>,
    allItems: List<LibraryDisplayItem>,
    layout: WorkSectionLayout,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: () -> Unit,
    onOpenCollection: (String) -> Unit,
    onDeleteCollection: (String) -> Unit
) {
    io.github.cidy02.kudos.ui.subject.WorkCarouselSection(
        title = "Collections",
        count = collections.size,
        collapsed = collapsed,
        onToggleCollapsed = onToggleCollapsed,
        onSeeAll = onSeeAll,
        emptyMessage = "Use + above to create a collection for works you want to group together.",
        layout = layout
    ) {
        if (layout == WorkSectionLayout.Shelves) {
            WorkCardCarousel(collections.take(ShelfLimit), key = { it.id }) { collection ->
                CollectionDashboardCard(collection, allItems, onOpenCollection, onDeleteCollection)
            }
        } else {
            Column(
                Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                collections.take(ShelfLimit).forEach { collection ->
                    CollectionDashboardCard(
                        collection,
                        allItems,
                        onOpenCollection,
                        onDeleteCollection,
                        ledger = true
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionDashboardCard(
    collection: WorkCollection,
    allItems: List<LibraryDisplayItem>,
    onOpenCollection: (String) -> Unit,
    onDeleteCollection: (String) -> Unit,
    ledger: Boolean = false
) {
    var menuOpen by remember(collection.id) { mutableStateOf(false) }
    val previews = allItems
        .filter { display -> display.item.collections.any { it.id == collection.id } }
        .sortedByDescending { it.item.work.dateAdded }
        .map { it.item.work }
    if (ledger) {
        CollectionLedgerRow(
            collection = collection,
            previewWorks = previews,
            onClick = { onOpenCollection(collection.id) },
            onLongClick = { menuOpen = true }
        )
    } else {
        CollectionCard(
            collection = collection,
            previewWorks = previews,
            onClick = { onOpenCollection(collection.id) },
            onLongClick = { menuOpen = true }
        )
    }
    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        DropdownMenuItem(
            text = { Text("Delete Collection", color = MaterialTheme.colorScheme.error) },
            leadingIcon = {
                Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            },
            onClick = { menuOpen = false; onDeleteCollection(collection.id) }
        )
    }
}

/** Dashed + create tile (Apple NewCollectionCard / New Queue). */
@Composable
private fun CreateShelfTile(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.width(WorkCoverCardMetrics.width),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Surface(
            onClick = onClick,
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(
                width = 1.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(WorkCoverCardMetrics.height - 48.dp)
                .semantics { contentDescription = title }
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(32.dp)
                )
            }
        }
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun NamedShelfTile(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.width(WorkCoverCardMetrics.width),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Surface(
            onClick = onClick,
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier
                .fillMaxWidth()
                .height(WorkCoverCardMetrics.height - 48.dp)
                .semantics { contentDescription = "$title, $subtitle" }
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Outlined.Folder,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.75f),
                    modifier = Modifier.size(36.dp)
                )
            }
        }
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun SelectableWorkRow(
    display: LibraryDisplayItem,
    selected: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val work = display.item.work
    Surface(
        onClick = onToggle,
        tonalElevation = if (selected) 2.dp else 0.dp,
        color = if (selected) {
            MaterialTheme.colorScheme.secondaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow
        },
        shape = MaterialTheme.shapes.medium,
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = if (selected) {
                    "Selected ${work.title}"
                } else {
                    "Not selected ${work.title}"
                }
            }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(checked = selected, onCheckedChange = { onToggle() })
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    work.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    work.author.ifBlank { "Anonymous" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (work.isDownloaded) {
                Icon(
                    Icons.AutoMirrored.Outlined.MenuBook,
                    contentDescription = "Downloaded",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun LibrarySelectionActionBar(
    hasSelection: Boolean,
    onFavorite: () -> Unit,
    onUnfavorite: () -> Unit,
    onSave: () -> Unit,
    onUnsave: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onMarkFinished: () -> Unit,
    onMarkUnfinished: () -> Unit,
    onRemove: () -> Unit,
    onSaveForLater: () -> Unit,
    onRemoveFromSaveForLater: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var overflowExpanded by remember { mutableStateOf(false) }
    Surface(
        tonalElevation = 6.dp,
        shadowElevation = 8.dp,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onRemove, enabled = hasSelection) {
                Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text("Delete", color = MaterialTheme.colorScheme.error)
            }
            Box {
                TextButton(onClick = { overflowExpanded = true }, enabled = hasSelection) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                    Text("Actions")
                }
                DropdownMenu(expanded = overflowExpanded, onDismissRequest = { overflowExpanded = false }) {
                    DropdownMenuItem(text = { Text("Download") }, onClick = { overflowExpanded = false; onSave() })
                    DropdownMenuItem(text = { Text("Favorite") }, onClick = { overflowExpanded = false; onFavorite() })
                    DropdownMenuItem(text = { Text("Save for Later") }, onClick = { overflowExpanded = false; onSaveForLater() })
                    DropdownMenuItem(text = { Text("Add to Queue") }, onClick = { overflowExpanded = false; onAddToQueue() })
                    DropdownMenuItem(text = { Text("Add to Collection") }, onClick = { overflowExpanded = false; onAddToCollection() })
                    DropdownMenuItem(text = { Text("Mark Finished") }, onClick = { overflowExpanded = false; onMarkFinished() })
                    HorizontalDivider()
                    DropdownMenuItem(text = { Text("Unfavorite") }, onClick = { overflowExpanded = false; onUnfavorite() })
                    DropdownMenuItem(text = { Text("Remove Download") }, onClick = { overflowExpanded = false; onUnsave() })
                    DropdownMenuItem(text = { Text("Remove from Saved for Later") }, onClick = { overflowExpanded = false; onRemoveFromSaveForLater() })
                    DropdownMenuItem(text = { Text("Mark as Still Reading") }, onClick = { overflowExpanded = false; onMarkUnfinished() })
                }
            }
            TextButton(onClick = onCancel) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                Text("Done")
            }
        }
    }
}
