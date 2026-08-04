package io.github.cidy02.kudos.library

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Queue
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarBorder
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
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
    settingsRepository: SettingsRepository? = null,
    queueRepository: ReadingQueueRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate(),
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit = {},
    onOpenReadingQueues: () -> Unit = {},
    onOpenReadingStatistics: () -> Unit = {},
    onOpenCollections: () -> Unit = {},
    onOpenQueue: (String) -> Unit = {},
    onOpenCollection: (String) -> Unit = {},
    onOpenComments: (Long) -> Unit = {}
) {
    val viewModel: LibraryViewModel = viewModel(
        factory = LibraryViewModel.factory(
            repository,
            workRepository,
            settingsRepository,
            queueRepository,
            privacyGate
        )
    )
    val state by viewModel.state.collectAsState()
    val activity = LocalContext.current as? androidx.fragment.app.FragmentActivity
    val scope = rememberCoroutineScope()
    var confirmBulkRemove by remember { mutableStateOf(false) }
    var confirmRemoveOne by remember { mutableStateOf<String?>(null) }
    var createQueueName by remember { mutableStateOf<String?>(null) }
    var createCollectionName by remember { mutableStateOf<String?>(null) }
    var addToQueueWorkId by remember { mutableStateOf<String?>(null) }
    var addToCollectionWorkId by remember { mutableStateOf<String?>(null) }
    var bulkAddToQueueOpen by remember { mutableStateOf(false) }
    var bulkAddToCollectionOpen by remember { mutableStateOf(false) }

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
        title = if (state.selectedCount == 1) "Remove 1 work?" else "Remove ${state.selectedCount} works?",
        text = "Selected works move to Recently Deleted for 90 days.",
        confirmText = "Remove",
        confirmBeforeDelete = state.confirmBeforeDelete,
        onConfirm = {
            confirmBulkRemove = false
            viewModel.bulkSoftDelete()
        },
        onDismissRequest = { confirmBulkRemove = false }
    )

    DestructiveConfirmation(
        show = confirmRemoveOne != null,
        title = "Remove from Library?",
        text = "This work moves to Recently Deleted for 90 days.",
        confirmText = "Remove",
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
        onCreateQueue = { createQueueName = "" },
        onCreateCollection = { createCollectionName = "" },
        onEnterSelection = { viewModel.enterSelectionMode() },
        onExitSelection = viewModel::exitSelectionMode,
        onToggleSelection = viewModel::toggleWorkSelection,
        onBulkFavorite = { viewModel.bulkSetFavorite(true) },
        onBulkUnfavorite = { viewModel.bulkSetFavorite(false) },
        onBulkSave = { viewModel.bulkSetSaved(true) },
        onBulkUnsave = { viewModel.bulkSetSaved(false) },
        onBulkAddToQueue = { bulkAddToQueueOpen = true },
        onBulkAddToCollection = { bulkAddToCollectionOpen = true },
        onBulkMarkFinished = { viewModel.bulkSetFinished(true) },
        onBulkMarkUnfinished = { viewModel.bulkSetFinished(false) },
        onBulkRemove = { confirmBulkRemove = true },
        onBulkRemoveFromSaveForLater = viewModel::bulkRemoveFromSaveForLater,
        onToggleFavoriteOne = viewModel::toggleFavoriteOne,
        onToggleFinishedOne = viewModel::toggleFinishedOne,
        onRemoveOne = { confirmRemoveOne = it },
        onSetSavedOne = viewModel::setSavedOne,
        onRevealWork = { viewModel.revealWork(it, activity) },
        onAddToQueue = { addToQueueWorkId = it },
        onAddToCollection = { addToCollectionWorkId = it },
        onOpenComments = onOpenComments,
        onTogglePrivacy = { viewModel.toggleRevealAll(activity) }
    )
}

@Composable
private fun LibraryContent(
    state: LibraryUiState,
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
    onCreateQueue: () -> Unit,
    onCreateCollection: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onToggleSelection: (String) -> Unit,
    onBulkFavorite: () -> Unit,
    onBulkUnfavorite: () -> Unit,
    onBulkSave: () -> Unit,
    onBulkUnsave: () -> Unit,
    onBulkAddToQueue: () -> Unit,
    onBulkAddToCollection: () -> Unit,
    onBulkMarkFinished: () -> Unit,
    onBulkMarkUnfinished: () -> Unit,
    onBulkRemove: () -> Unit,
    onBulkRemoveFromSaveForLater: () -> Unit,
    onToggleFavoriteOne: (String) -> Unit,
    onToggleFinishedOne: (String) -> Unit,
    onRemoveOne: (String) -> Unit,
    onSetSavedOne: (String, Boolean) -> Unit,
    onRevealWork: (String) -> Unit,
    onAddToQueue: (String) -> Unit,
    onAddToCollection: (String) -> Unit,
    onOpenComments: (Long) -> Unit,
    onTogglePrivacy: () -> Unit
) {
    val collapsed = remember { mutableStateMapOf<String, Boolean>() }
    val bottomPad = if (state.selectionMode) 88.dp else 12.dp
    val cardActions = LibraryCardActions(
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onToggleFavorite = onToggleFavoriteOne,
        onToggleFinished = onToggleFinishedOne,
        onRemove = onRemoveOne,
        onSetSaved = onSetSavedOne,
        onSelect = { id ->
            onEnterSelection()
            onToggleSelection(id)
        },
        onReveal = onRevealWork,
        onAddToQueue = onAddToQueue,
        onAddToCollection = onAddToCollection,
        onOpenComments = onOpenComments
    )

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 8.dp,
                bottom = bottomPad
            ),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            item {
                LibraryToolbarPill(
                    state = state,
                    onOpenReadingStatistics = onOpenReadingStatistics,
                    onEnterSelection = onEnterSelection,
                    onExitSelection = onExitSelection,
                    onTogglePrivacy = onTogglePrivacy,
                    onOpenRecentlyDeleted = onOpenRecentlyDeleted,
                    onBulkRemoveFromSaveForLater = onBulkRemoveFromSaveForLater,
                    modifier = Modifier.padding(horizontal = 12.dp)
                )
            }

            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = state.searchQuery,
                        onValueChange = onUpdateSearchQuery,
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Search library") },
                        singleLine = true,
                        trailingIcon = {
                            if (state.searchQuery.isNotEmpty()) {
                                IconButton(onClick = { onUpdateSearchQuery("") }) {
                                    Icon(Icons.Filled.Clear, "Clear search")
                                }
                            }
                        }
                    )

                    var sortMenuOpen by remember { mutableStateOf(false) }
                    var moreMenuOpen by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { sortMenuOpen = true }) {
                            Icon(Icons.Filled.Sort, "Sort")
                        }
                        DropdownMenu(
                            expanded = sortMenuOpen,
                            onDismissRequest = { sortMenuOpen = false }
                        ) {
                            LibrarySort.entries.forEach { sortOption ->
                                DropdownMenuItem(
                                    text = { Text(sortOption.label) },
                                    onClick = {
                                        onUpdateSort(sortOption)
                                        sortMenuOpen = false
                                    }
                                )
                            }
                        }
                    }
                    Box {
                        IconButton(onClick = { moreMenuOpen = true }) {
                            Icon(Icons.Default.MoreVert, "More")
                        }
                        DropdownMenu(
                            expanded = moreMenuOpen,
                            onDismissRequest = { moreMenuOpen = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Remove from Save for Later") },
                                onClick = {
                                    moreMenuOpen = false
                                    onBulkRemoveFromSaveForLater()
                                }
                            )
                        }
                    }
                }
            }

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

            if (!state.hasSavedWorks) {
                item {
                    EmptyStateCard(
                        title = "No saved works",
                        message = "Save or download works from Search, Browse, or Work Detail.",
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
                item {
                    Text(
                        text = if (state.hasSelection) {
                            "${state.selectedCount} selected"
                        } else {
                            "Select works"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
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
                    LibraryCarousel(
                        sectionKey = "readingNow",
                        title = "Reading Now",
                        items = state.continueReading.take(ShelfLimit),
                        emptyMessage =
                            "You're not reading anything right now. Open something below or find a new work in Browse.",
                        showProgress = true,
                        collapsed = collapsed["readingNow"] == true,
                        onToggleCollapsed = {
                            collapsed["readingNow"] = !(collapsed["readingNow"] ?: false)
                        },
                        actions = cardActions
                    )
                }
                item {
                    LibraryCarousel(
                        sectionKey = "savedForLater",
                        title = "Saved for Later",
                        items = state.savedForLater.take(ShelfLimit),
                        emptyMessage =
                            "Nothing saved for later yet. Save works here, or mark them for later on AO3.",
                        showProgress = false,
                        collapsed = collapsed["savedForLater"] == true,
                        onToggleCollapsed = {
                            collapsed["savedForLater"] =
                                !(collapsed["savedForLater"] ?: false)
                        },
                        actions = cardActions
                    )
                }
                item {
                    LibraryCarousel(
                        sectionKey = "finished",
                        title = "Finished",
                        items = state.finished.take(ShelfLimit),
                        emptyMessage = "No finished works yet. Works you complete show up here.",
                        showProgress = false,
                        footerFor = { "Finished" },
                        collapsed = collapsed["finished"] == true,
                        onToggleCollapsed = {
                            collapsed["finished"] = !(collapsed["finished"] ?: false)
                        },
                        actions = cardActions
                    )
                }
                item {
                    // Home already has a Favorites shelf; Library computed the same
                    // state (privacy-reveal mapped and all) but never rendered it.
                    LibraryCarousel(
                        sectionKey = "favorites",
                        title = "Favorites",
                        items = state.favorites.take(ShelfLimit),
                        emptyMessage = "No favorites yet. Mark works as favorites to see them here.",
                        showProgress = false,
                        collapsed = collapsed["favorites"] == true,
                        onToggleCollapsed = {
                            collapsed["favorites"] = !(collapsed["favorites"] ?: false)
                        },
                        actions = cardActions
                    )
                }
                item {
                    ReadingQueuesShelf(
                        queues = state.readingQueues,
                        collapsed = collapsed["queues"] == true,
                        onToggleCollapsed = {
                            collapsed["queues"] = !(collapsed["queues"] ?: false)
                        },
                        onSeeAll = onOpenReadingQueues,
                        onCreate = onCreateQueue,
                        onOpenQueue = onOpenQueue
                    )
                }
                item {
                    CollectionsShelf(
                        collections = state.collections,
                        collapsed = collapsed["collections"] == true,
                        onToggleCollapsed = {
                            collapsed["collections"] = !(collapsed["collections"] ?: false)
                        },
                        onSeeAll = onOpenCollections,
                        onCreate = onCreateCollection,
                        onOpenCollection = onOpenCollection
                    )
                }
                item {
                    LibraryCarousel(
                        sectionKey = "downloaded",
                        title = "Downloaded",
                        items = state.downloaded.take(ShelfLimit),
                        emptyMessage =
                            "No downloads yet. Download a work as EPUB to read it offline.",
                        showProgress = false,
                        collapsed = collapsed["downloaded"] == true,
                        onToggleCollapsed = {
                            collapsed["downloaded"] = !(collapsed["downloaded"] ?: false)
                        },
                        actions = cardActions
                    )
                }
                item {
                    LibraryCarousel(
                        sectionKey = "history",
                        title = "Reading History",
                        items = state.readingHistory.take(ShelfLimit),
                        emptyMessage =
                            "Nothing opened recently. Start reading to see your history here.",
                        showProgress = false,
                        collapsed = collapsed["history"] == true,
                        onToggleCollapsed = {
                            collapsed["history"] = !(collapsed["history"] ?: false)
                        },
                        actions = cardActions
                    )
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
                onRemoveFromSaveForLater = onBulkRemoveFromSaveForLater,
                onCancel = onExitSelection,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

data class LibraryCardActions(
    val onOpenWork: (String) -> Unit,
    val onOpenReader: (String) -> Unit,
    val onToggleFavorite: (String) -> Unit,
    val onToggleFinished: (String) -> Unit,
    val onRemove: (String) -> Unit,
    val onSetSaved: (String, Boolean) -> Unit,
    val onSelect: (String) -> Unit,
    val onReveal: (String) -> Unit,
    val onAddToQueue: (String) -> Unit,
    val onAddToCollection: (String) -> Unit,
    val onOpenComments: (Long) -> Unit
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
                "${state.totalSaved} saved$hidden"
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
    modifier: Modifier = Modifier
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
                    if (!work.hasEpub) "Not downloaded" else null,
                    if (work.isFavorite) "Favorite" else null
                )
            },
            obscured = obscured,
            contentDescription = if (obscured) {
                "Hidden mature work. Activate to reveal."
            } else {
                "${if (canRead) "Read" else "Open"} ${work.title}"
            },
            onLongClick = { if (!obscured) menuOpen = true }
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
            if (work.isSaved) {
                ContextMenuItem(
                    icon = Icons.Outlined.BookmarkBorder,
                    label = "Remove from Saved",
                    onClick = {
                        menuOpen = false
                        actions.onSetSaved(work.id, false)
                    }
                )
            }
            ContextMenuItem(
                icon = if (work.isFavorite) Icons.Outlined.Star else Icons.Outlined.StarBorder,
                label = if (work.isFavorite) "Unfavorite" else "Favorite",
                onClick = {
                    menuOpen = false
                    actions.onToggleFavorite(work.id)
                }
            )
            ContextMenuItem(
                icon = Icons.Outlined.Bookmark,
                label = if (work.isSaved) "Saved for Later" else "Save for Later",
                onClick = {
                    menuOpen = false
                    actions.onSetSaved(work.id, !work.isSaved)
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
    destructive: Boolean = false
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
        onClick = onClick
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
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: () -> Unit,
    onCreate: () -> Unit,
    onOpenCollection: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        CollapsibleSectionHeader(
            title = "Collections",
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
                item(key = "new-collection") {
                    CreateShelfTile(
                        title = "New Collection",
                        subtitle = "Tap to create",
                        onClick = onCreate
                    )
                }
                items(collections, key = { "col-${it.id}" }) { collection ->
                    NamedShelfTile(
                        title = collection.name,
                        subtitle = when (collection.workIds.size) {
                            0 -> "Empty"
                            1 -> "1 work"
                            else -> "${collection.workIds.size} works"
                        },
                        onClick = { onOpenCollection(collection.id) }
                    )
                }
            }
        }
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
            if (work.hasEpub) {
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
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onFavorite, enabled = hasSelection) {
                    Icon(Icons.Outlined.Star, "Favorite")
                }
                IconButton(onClick = onSave, enabled = hasSelection) {
                    Icon(Icons.Outlined.Bookmark, "Save")
                }
                IconButton(onClick = onAddToQueue, enabled = hasSelection) {
                    Icon(Icons.Outlined.Queue, "Add to Queue")
                }
                IconButton(onClick = onAddToCollection, enabled = hasSelection) {
                    Icon(Icons.Outlined.CollectionsBookmark, "Add to Collection")
                }
                IconButton(onClick = onMarkFinished, enabled = hasSelection) {
                    Icon(Icons.Outlined.CheckCircle, "Mark Finished")
                }
            }
            
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = { overflowExpanded = true }, enabled = hasSelection) {
                        Icon(Icons.Default.MoreVert, "More actions")
                    }
                    DropdownMenu(
                        expanded = overflowExpanded,
                        onDismissRequest = { overflowExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Unfavorite") },
                            onClick = { overflowExpanded = false; onUnfavorite() }
                        )
                        DropdownMenuItem(
                            text = { Text("Unsave") },
                            onClick = { overflowExpanded = false; onUnsave() }
                        )
                        DropdownMenuItem(
                            text = { Text("Mark Unfinished") },
                            onClick = { overflowExpanded = false; onMarkUnfinished() }
                        )
                        DropdownMenuItem(
                            text = { Text("Remove from Save for Later") },
                            onClick = { overflowExpanded = false; onRemoveFromSaveForLater() }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Remove from Library", color = MaterialTheme.colorScheme.error) },
                            onClick = { overflowExpanded = false; onRemove() }
                        )
                    }
                }
                TextButton(onClick = onCancel) {
                    Text("Cancel")
                }
            }
        }
    }
}
