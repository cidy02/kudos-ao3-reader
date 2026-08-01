package io.github.cidy02.kudos.library

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
import io.github.cidy02.kudos.works.WorkRepository
import kotlin.math.roundToInt

private const val ShelfLimit = 12

/**
 * Library dashboard — Material expression of Apple [LibraryView]:
 * horizontal cover-card carousels (Reading Now → Saved for Later → Finished →
 * Collections → Downloaded), icon toolbar (privacy / insights / select / filter),
 * and long-press context menus on cards.
 */
@Composable
fun LibraryScreen(
    repository: LibraryRepository,
    workRepository: WorkRepository,
    settingsRepository: SettingsRepository? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit = {},
    onOpenReadingQueues: () -> Unit = {},
    onOpenReadingStatistics: () -> Unit = {},
    onOpenCollections: () -> Unit = {}
) {
    val viewModel: LibraryViewModel = viewModel(
        factory = LibraryViewModel.factory(repository, workRepository, settingsRepository)
    )
    val state by viewModel.state.collectAsState()
    var confirmBulkRemove by remember { mutableStateOf(false) }
    var confirmRemoveOne by remember { mutableStateOf<String?>(null) }

    if (confirmBulkRemove) {
        val count = state.selectedCount
        AlertDialog(
            onDismissRequest = { confirmBulkRemove = false },
            title = {
                Text(if (count == 1) "Remove 1 work?" else "Remove $count works?")
            },
            text = {
                Text(
                    "Selected works move to Recently Deleted for 90 days."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmBulkRemove = false
                        viewModel.bulkSoftDelete()
                    }
                ) { Text("Remove") }
            },
            dismissButton = {
                TextButton(onClick = { confirmBulkRemove = false }) { Text("Cancel") }
            }
        )
    }

    confirmRemoveOne?.let { workId ->
        AlertDialog(
            onDismissRequest = { confirmRemoveOne = null },
            title = { Text("Remove from Library?") },
            text = {
                Text("This work moves to Recently Deleted for 90 days.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmRemoveOne = null
                        viewModel.softDeleteOne(workId)
                    }
                ) { Text("Remove") }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemoveOne = null }) { Text("Cancel") }
            }
        )
    }

    LibraryContent(
        state = state,
        onToggleFavoriteFilter = viewModel::toggleFavoriteOnly,
        onFinishedFilter = viewModel::setFinishedFilter,
        onDownloadFilter = viewModel::setDownloadFilter,
        onClearFilters = viewModel::clearFilters,
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onOpenReadingQueues = onOpenReadingQueues,
        onOpenRecentlyDeleted = onOpenRecentlyDeleted,
        onOpenReadingStatistics = onOpenReadingStatistics,
        onOpenCollections = onOpenCollections,
        onEnterSelection = { viewModel.enterSelectionMode() },
        onExitSelection = viewModel::exitSelectionMode,
        onToggleSelection = viewModel::toggleWorkSelection,
        onBulkFavorite = { viewModel.bulkSetFavorite(true) },
        onBulkUnfavorite = { viewModel.bulkSetFavorite(false) },
        onBulkMarkFinished = { viewModel.bulkSetFinished(true) },
        onBulkMarkUnfinished = { viewModel.bulkSetFinished(false) },
        onBulkRemove = { confirmBulkRemove = true },
        onToggleFavoriteOne = viewModel::toggleFavoriteOne,
        onToggleFinishedOne = viewModel::toggleFinishedOne,
        onRemoveOne = { confirmRemoveOne = it },
        onTogglePrivacy = viewModel::toggleHideMature
    )
}

@Composable
private fun LibraryContent(
    state: LibraryUiState,
    onToggleFavoriteFilter: () -> Unit,
    onFinishedFilter: (LibraryFinishedFilter) -> Unit,
    onDownloadFilter: (LibraryDownloadFilter) -> Unit,
    onClearFilters: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit,
    onOpenReadingQueues: () -> Unit,
    onOpenReadingStatistics: () -> Unit,
    onOpenCollections: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onToggleSelection: (String) -> Unit,
    onBulkFavorite: () -> Unit,
    onBulkUnfavorite: () -> Unit,
    onBulkMarkFinished: () -> Unit,
    onBulkMarkUnfinished: () -> Unit,
    onBulkRemove: () -> Unit,
    onToggleFavoriteOne: (String) -> Unit,
    onToggleFinishedOne: (String) -> Unit,
    onRemoveOne: (String) -> Unit,
    onTogglePrivacy: () -> Unit
) {
    var filtersExpanded by rememberSaveable { mutableStateOf(false) }
    val bottomPad = if (state.selectionMode) 88.dp else 12.dp

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 8.dp,
                bottom = bottomPad
            ),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Icon toolbar — Apple primaryAction cluster (privacy / insights / select / filter)
            item {
                LibraryIconToolbar(
                    state = state,
                    filtersExpanded = filtersExpanded,
                    onToggleFilters = { filtersExpanded = !filtersExpanded },
                    onOpenReadingStatistics = onOpenReadingStatistics,
                    onEnterSelection = onEnterSelection,
                    onExitSelection = onExitSelection,
                    onTogglePrivacy = onTogglePrivacy,
                    onOpenRecentlyDeleted = onOpenRecentlyDeleted,
                    onOpenReadingQueues = onOpenReadingQueues,
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
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

            // Filters panel (collapsed by default) — Apple inspector substitute
            item {
                AnimatedVisibility(visible = filtersExpanded && !state.selectionMode) {
                    LibraryFilterChips(
                        state = state,
                        onToggleFavorite = onToggleFavoriteFilter,
                        onFinishedFilter = onFinishedFilter,
                        onDownloadFilter = onDownloadFilter,
                        onClear = onClearFilters,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            }

            if (state.selectionMode) {
                // Select mode: vertical checklist (Apple selectList)
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
                // Dashboard carousels — Apple section order
                item {
                    LibraryCarousel(
                        title = "Reading Now",
                        items = state.continueReading.take(ShelfLimit),
                        emptyMessage = "You're not reading anything right now. Open something below or find a new work in Browse.",
                        showProgress = true,
                        onOpenWork = onOpenWork,
                        onOpenReader = onOpenReader,
                        onToggleFavorite = onToggleFavoriteOne,
                        onToggleFinished = onToggleFinishedOne,
                        onRemove = onRemoveOne,
                        onSelect = { id ->
                            onEnterSelection()
                            onToggleSelection(id)
                        }
                    )
                }
                item {
                    LibraryCarousel(
                        title = "Saved for Later",
                        items = state.savedForLater.take(ShelfLimit),
                        emptyMessage = "Nothing saved for later yet. Save works here, or mark them for later on AO3.",
                        showProgress = false,
                        onOpenWork = onOpenWork,
                        onOpenReader = onOpenReader,
                        onToggleFavorite = onToggleFavoriteOne,
                        onToggleFinished = onToggleFinishedOne,
                        onRemove = onRemoveOne,
                        onSelect = { id ->
                            onEnterSelection()
                            onToggleSelection(id)
                        }
                    )
                }
                item {
                    LibraryCarousel(
                        title = "Finished",
                        items = state.finished.take(ShelfLimit),
                        emptyMessage = "No finished works yet. Works you complete show up here.",
                        showProgress = false,
                        footerFor = { "Finished" },
                        onOpenWork = onOpenWork,
                        onOpenReader = onOpenReader,
                        onToggleFavorite = onToggleFavoriteOne,
                        onToggleFinished = onToggleFinishedOne,
                        onRemove = onRemoveOne,
                        onSelect = { id ->
                            onEnterSelection()
                            onToggleSelection(id)
                        }
                    )
                }
                item {
                    CollectionsShelfPreview(
                        collections = state.collections,
                        onOpenCollections = onOpenCollections
                    )
                }
                item {
                    LibraryCarousel(
                        title = "Downloaded",
                        items = state.downloaded.take(ShelfLimit),
                        emptyMessage = "No downloads yet. Download a work as EPUB to read it offline.",
                        showProgress = false,
                        onOpenWork = onOpenWork,
                        onOpenReader = onOpenReader,
                        onToggleFavorite = onToggleFavoriteOne,
                        onToggleFinished = onToggleFinishedOne,
                        onRemove = onRemoveOne,
                        onSelect = { id ->
                            onEnterSelection()
                            onToggleSelection(id)
                        }
                    )
                }

                // When filters are active, also show the matching vertical list.
                if (state.hasActiveQueryOrFilters) {
                    item {
                        KudosSectionHeader(
                            title = "Matches",
                            subtitle = "${state.items.size}",
                            modifier = Modifier.padding(horizontal = 16.dp)
                        )
                    }
                    if (state.items.isEmpty()) {
                        item {
                            EmptyStateCard(
                                title = "No matches",
                                message = "No saved works match the current filters.",
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }
                    } else {
                        items(state.items, key = { "match-${it.item.work.id}" }) { display ->
                            LibraryCarouselCard(
                                display = display,
                                showProgress = false,
                                footerOverride = null,
                                onOpenWork = { onOpenWork(display.item.work.id) },
                                onOpenReader = { onOpenReader(display.item.work.id) },
                                onToggleFavorite = { onToggleFavoriteOne(display.item.work.id) },
                                onToggleFinished = { onToggleFinishedOne(display.item.work.id) },
                                onRemove = { onRemoveOne(display.item.work.id) },
                                onSelect = {
                                    onEnterSelection()
                                    onToggleSelection(display.item.work.id)
                                },
                                modifier = Modifier.padding(horizontal = 16.dp)
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
                onMarkFinished = onBulkMarkFinished,
                onMarkUnfinished = onBulkMarkUnfinished,
                onRemove = onBulkRemove,
                onCancel = onExitSelection,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun LibraryIconToolbar(
    state: LibraryUiState,
    filtersExpanded: Boolean,
    onToggleFilters: () -> Unit,
    onOpenReadingStatistics: () -> Unit,
    onEnterSelection: () -> Unit,
    onExitSelection: () -> Unit,
    onTogglePrivacy: () -> Unit,
    onOpenRecentlyDeleted: () -> Unit,
    onOpenReadingQueues: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
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
                    .padding(start = 8.dp)
            )
            // Compact icon cluster — Apple toolbar primaryAction
            Row(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                if (state.selectionMode) {
                    TextButton(onClick = onExitSelection) { Text("Done") }
                } else {
                    if (state.showPrivacyToggle) {
                        IconButton(onClick = onTogglePrivacy) {
                            Icon(
                                imageVector = if (state.hideMatureContent) {
                                    Icons.Filled.VisibilityOff
                                } else {
                                    Icons.Filled.Visibility
                                },
                                contentDescription = if (state.hideMatureContent) {
                                    "Show mature works"
                                } else {
                                    "Hide mature works"
                                }
                            )
                        }
                    }
                    if (state.hasSavedWorks) {
                        IconButton(onClick = onOpenReadingStatistics) {
                            Icon(
                                imageVector = Icons.Outlined.BarChart,
                                contentDescription = "Reading Insights"
                            )
                        }
                        IconButton(onClick = onEnterSelection) {
                            Icon(
                                imageVector = Icons.Outlined.Checklist,
                                contentDescription = "Select"
                            )
                        }
                        IconButton(onClick = onToggleFilters) {
                            Icon(
                                imageVector = Icons.Outlined.FilterList,
                                contentDescription = if (filtersExpanded) {
                                    "Hide filters"
                                } else {
                                    "Filters"
                                },
                                tint = if (state.filters.hasActiveFilters || filtersExpanded) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                }
                            )
                        }
                    }
                }
            }
        }
        // Secondary links (queues / recently deleted) as compact text
        if (!state.selectionMode) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                TextButton(onClick = onOpenReadingQueues) { Text("Queues") }
                TextButton(onClick = onOpenRecentlyDeleted) { Text("Recently Deleted") }
            }
        }
    }
}

@Composable
private fun LibraryFilterChips(
    state: LibraryUiState,
    onToggleFavorite: () -> Unit,
    onFinishedFilter: (LibraryFinishedFilter) -> Unit,
    onDownloadFilter: (LibraryDownloadFilter) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.horizontalScroll(rememberScrollState())
        ) {
            FilterChip(
                selected = state.filters.favoriteOnly,
                onClick = onToggleFavorite,
                label = { Text("Favorites") }
            )
            FilterChip(
                selected = state.filters.finished == LibraryFinishedFilter.Finished,
                onClick = {
                    onFinishedFilter(
                        if (state.filters.finished == LibraryFinishedFilter.Finished) {
                            LibraryFinishedFilter.Any
                        } else {
                            LibraryFinishedFilter.Finished
                        }
                    )
                },
                label = { Text("Finished") }
            )
            FilterChip(
                selected = state.filters.finished == LibraryFinishedFilter.Unfinished,
                onClick = {
                    onFinishedFilter(
                        if (state.filters.finished == LibraryFinishedFilter.Unfinished) {
                            LibraryFinishedFilter.Any
                        } else {
                            LibraryFinishedFilter.Unfinished
                        }
                    )
                },
                label = { Text("Unfinished") }
            )
            FilterChip(
                selected = state.filters.download == LibraryDownloadFilter.Downloaded,
                onClick = {
                    onDownloadFilter(
                        if (state.filters.download == LibraryDownloadFilter.Downloaded) {
                            LibraryDownloadFilter.Any
                        } else {
                            LibraryDownloadFilter.Downloaded
                        }
                    )
                },
                label = { Text("Downloaded") }
            )
            if (state.filters.hasActiveFilters) {
                TextButton(onClick = onClear) { Text("Clear") }
            }
        }
    }
}

@Composable
private fun LibraryCarousel(
    title: String,
    items: List<LibraryDisplayItem>,
    emptyMessage: String,
    showProgress: Boolean,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onToggleFavorite: (String) -> Unit,
    onToggleFinished: (String) -> Unit,
    onRemove: (String) -> Unit,
    onSelect: (String) -> Unit,
    footerFor: ((SavedWork) -> String?)? = null
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        KudosSectionHeader(
            title = title,
            subtitle = if (items.isEmpty()) null else "${items.size}",
            modifier = Modifier.padding(horizontal = 16.dp)
        )
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
                items(items, key = { "$title-${it.item.work.id}" }) { display ->
                    LibraryCarouselCard(
                        display = display,
                        showProgress = showProgress,
                        footerOverride = footerFor?.invoke(display.item.work),
                        onOpenWork = { onOpenWork(display.item.work.id) },
                        onOpenReader = { onOpenReader(display.item.work.id) },
                        onToggleFavorite = { onToggleFavorite(display.item.work.id) },
                        onToggleFinished = { onToggleFinished(display.item.work.id) },
                        onRemove = { onRemove(display.item.work.id) },
                        onSelect = { onSelect(display.item.work.id) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LibraryCarouselCard(
    display: LibraryDisplayItem,
    showProgress: Boolean,
    footerOverride: String?,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleFinished: () -> Unit,
    onRemove: () -> Unit,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    var menuOpen by remember(work.id) { mutableStateOf(false) }

    val progress = if (showProgress && !obscured && footerOverride == null) {
        work.readingProgressFraction()?.toFloat()
    } else {
        null
    }
    val progressLabel = progress?.let { value ->
        when {
            value >= 0.999f || work.isFinished -> "Finished"
            else -> "${(value * 100).roundToInt()}% · Reading"
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
                    kudos = work.kudos.takeIf { it > 0 }
                )
            },
            onOpen = {
                if (canRead) onOpenReader() else onOpenWork()
            },
            onOpenDetails = onOpenWork,
            progress = progress,
            progressLabel = progressLabel,
            statusChips = if (obscured) {
                listOf(work.rating.ifBlank { "Mature content" })
            } else {
                listOfNotNull(
                    footerOverride,
                    if (!work.hasEpub) "Not downloaded" else null,
                    if (work.isFavorite) "Favorite" else null
                )
            },
            obscured = obscured,
            contentDescription = if (obscured) {
                "Mature work hidden"
            } else {
                "${if (canRead) "Read" else "Open"} ${work.title}"
            },
            onLongClick = { menuOpen = true }
        )
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false }
        ) {
            if (canRead) {
                DropdownMenuItem(
                    text = { Text("Read") },
                    onClick = {
                        menuOpen = false
                        onOpenReader()
                    }
                )
            }
            DropdownMenuItem(
                text = { Text("Details") },
                onClick = {
                    menuOpen = false
                    onOpenWork()
                }
            )
            DropdownMenuItem(
                text = { Text(if (work.isFavorite) "Unfavorite" else "Favorite") },
                onClick = {
                    menuOpen = false
                    onToggleFavorite()
                }
            )
            DropdownMenuItem(
                text = { Text(if (work.isFinished) "Mark unfinished" else "Mark finished") },
                onClick = {
                    menuOpen = false
                    onToggleFinished()
                }
            )
            DropdownMenuItem(
                text = { Text("Select…") },
                onClick = {
                    menuOpen = false
                    onSelect()
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        "Remove",
                        color = MaterialTheme.colorScheme.error
                    )
                },
                onClick = {
                    menuOpen = false
                    onRemove()
                }
            )
        }
    }
}

@Composable
private fun CollectionsShelfPreview(
    collections: List<io.github.cidy02.kudos.core.model.WorkCollection>,
    onOpenCollections: () -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.padding(horizontal = 16.dp)
    ) {
        KudosSectionHeader(
            title = "Collections",
            subtitle = if (collections.isEmpty()) null else "${collections.size}",
            trailing = {
                TextButton(onClick = onOpenCollections) { Text("See all") }
            }
        )
        if (collections.isEmpty()) {
            EmptyStateCard(
                title = "No collections yet",
                message = "Group works into named shelves from Work Detail or Collections."
            )
        } else {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.horizontalScroll(rememberScrollState())
            ) {
                collections.take(8).forEach { collection ->
                    FilterChip(
                        selected = false,
                        onClick = onOpenCollections,
                        label = {
                            Text(
                                "${collection.name} (${collection.workIds.size})",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
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
    onMarkFinished: () -> Unit,
    onMarkUnfinished: () -> Unit,
    onRemove: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        tonalElevation = 6.dp,
        shadowElevation = 8.dp,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(0.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onFavorite, enabled = hasSelection) { Text("Favorite") }
            TextButton(onClick = onUnfavorite, enabled = hasSelection) { Text("Unfavorite") }
            TextButton(onClick = onMarkFinished, enabled = hasSelection) { Text("Finished") }
            TextButton(onClick = onMarkUnfinished, enabled = hasSelection) { Text("Unfinished") }
            TextButton(onClick = onRemove, enabled = hasSelection) {
                Text("Remove", color = if (hasSelection) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                })
            }
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
    }
}
