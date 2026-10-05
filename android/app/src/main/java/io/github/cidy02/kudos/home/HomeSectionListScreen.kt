package io.github.cidy02.kudos.home

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.library.AddToCollectionDialog
import io.github.cidy02.kudos.library.AddToQueueDialog
import io.github.cidy02.kudos.library.LibraryCardActions
import io.github.cidy02.kudos.library.LibraryCompletionFilter
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryDownloadFilter
import io.github.cidy02.kudos.library.LibraryFilterPanel
import io.github.cidy02.kudos.library.LibraryFilterState
import io.github.cidy02.kudos.library.LibraryFinishedFilter
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryQuery
import io.github.cidy02.kudos.library.LibraryQueuePreview
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.LibrarySectionKind
import io.github.cidy02.kudos.library.LibrarySnapshot
import io.github.cidy02.kudos.library.LibrarySort
import io.github.cidy02.kudos.library.LibrarySubjectLedgerRow
import io.github.cidy02.kudos.library.LibrarySubjectWorkCard
import io.github.cidy02.kudos.library.LibraryWorkMenu
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.library.leadingSwipeActions
import io.github.cidy02.kudos.library.queuePreviews
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.library.trailingSwipeActions
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.library.LibraryFilterCollisionCard
import io.github.cidy02.kudos.library.LibraryPlainEmptyState
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.WorkBulkActionBar
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectWorkCardMetrics
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.defaultWorkSignals
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch

private const val HomeSectionPreferences = "home-section-list"

private enum class HomeSectionDisplayMode(val title: String) {
    Detailed("Detailed"),
    Ledger("Ledger"),
    Compact("Compact")
}

private enum class HomeUpdatePill(val title: String) {
    All("All"),
    Unread("Unread"),
    Offline("Offline");

    fun apply(items: List<LibraryDisplayItem>): List<LibraryDisplayItem> = when (this) {
        All -> items
        Unread -> items.filter { it.item.work.hasUpdate }
        Offline -> items.filter { it.item.work.hasEpub }
    }
}

/** iOS `HomeSectionListView`, using the Library section list's chrome and work cards. */
@Composable
fun HomeSectionListScreen(
    kind: HomeSectionKind,
    repository: LibraryRepository,
    workRepository: WorkRepository,
    privacyGate: PrivacyGate,
    metadataRefresh: WorkMetadataRefresh?,
    queueRepository: ReadingQueueRepository? = null,
    downloadQueue: DownloadQueue? = null,
    initialSelecting: Boolean = false,
    initialSelection: Set<String> = emptySet(),
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenComments: (Long) -> Unit = {},
    onOpenReadingQueues: () -> Unit = {}
) {
    val snapshot by repository.observeSnapshot().collectAsState(initial = null)
    val privacyState by privacyGate.state.collectAsState()
    val context = LocalContext.current
    val activity = context as? androidx.fragment.app.FragmentActivity
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val preferences = remember(context) {
        context.getSharedPreferences(HomeSectionPreferences, Context.MODE_PRIVATE)
    }

    var filters by remember(kind) { mutableStateOf(LibraryFilterState()) }
    var sort by remember(kind) { mutableStateOf(LibrarySort.Natural) }
    var addToQueueWorkId by remember { mutableStateOf<String?>(null) }
    var addToCollectionWorkId by remember { mutableStateOf<String?>(null) }
    var updatePill by remember(kind) { mutableStateOf(HomeUpdatePill.All) }
    var showFilters by remember { mutableStateOf(false) }
    var expandAll by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var showLayoutMenu by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<String?>(null) }
    var isSelecting by remember(initialSelecting) { mutableStateOf(initialSelecting) }
    var selection by remember(initialSelection) { mutableStateOf(initialSelection) }
    var displayMode by remember(kind) {
        mutableStateOf(
            runCatching {
                HomeSectionDisplayMode.valueOf(
                    preferences.getString("${kind.id}.displayMode", null)
                        ?: HomeSectionDisplayMode.Detailed.name
                )
            }.getOrDefault(HomeSectionDisplayMode.Detailed)
        )
    }

    val displayItems = remember(snapshot, privacyState) {
        val current = snapshot ?: return@remember emptyList()
        current.items.mapNotNull { item ->
            when (val visibility = LibraryPrivacy.visibility(item.work, current.privacy, privacyState)) {
                LibraryPrivacyVisibility.Hidden -> null
                else -> LibraryDisplayItem(item, visibility)
            }
        }
    }
    val displayById = remember(displayItems) { displayItems.associateBy { it.item.work.id } }
    val sectionItems = remember(displayItems, displayById, kind) {
        kind.works(displayItems.map { it.item.work }) { true }
            .mapNotNull { displayById[it.id] }
    }
    val filteredItems = remember(sectionItems, filters, sort) {
        val narrowed = if (filters.hasActiveFilters) {
            LibraryQuery.filterOnly(sectionItems, filters = filters)
        } else {
            sectionItems
        }
        // iOS keeps the section's own order until a sort is picked (`HomeSectionListView`).
        if (sort == LibrarySort.Natural) narrowed else LibraryQuery.sortDisplayItems(narrowed, sort)
    }
    val visibleItems = remember(filteredItems, kind, updatePill) {
        if (kind == HomeSectionKind.RecentlyUpdated) updatePill.apply(filteredItems) else filteredItems
    }
    val selectedWorks = remember(visibleItems, selection) {
        visibleItems.filter { it.item.work.id in selection }.map { it.item.work }
    }
    val visibleIds = remember(visibleItems) { visibleItems.mapTo(linkedSetOf()) { it.item.work.id } }
    val allSelected = visibleIds.isNotEmpty() && selection.containsAll(visibleIds)
    val hideMature = snapshot?.privacy?.hideMatureContent == true
    val showsWorkControls = sectionItems.isNotEmpty()

    fun toggleSelection(id: String) {
        selection = if (id in selection) selection - id else selection + id
    }

    fun exitSelection() {
        isSelecting = false
        selection = emptySet()
    }

    val removeFromAllQueues: (String) -> Unit = { id ->
        scope.launch { queueRepository?.removeFromAllQueuesAndDeleteIfQueueOnly(id) }
    }

    val cardActions = LibraryCardActions(
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onToggleFavorite = { id -> scope.launch { workRepository.toggleFavorite(id) } },
        onToggleFinished = { id -> scope.launch { workRepository.toggleFinished(id) } },
        onRemove = { pendingDelete = it },
        onDownloadAction = { id, action ->
            scope.launch {
                when (action) {
                    WorkDownloadAction.Download -> {
                        val work = workRepository.getWork(id) ?: return@launch
                        workRepository.setSaved(id, true)
                        if (!work.hasEpub) {
                            val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return@launch
                            downloadQueue?.enqueueLocal(ao3Id, work.title, work.sourceUrl, force = true)
                        }
                    }
                    WorkDownloadAction.RemoveDownload -> workRepository.setSaved(id, false)
                    is WorkDownloadAction.KeptBy -> Unit
                }
            }
        },
        onToggleSavedForLater = { id, isQueued ->
            scope.launch {
                if (isQueued) {
                    queueRepository?.removeFromSavedForLater(id)
                } else {
                    queueRepository?.addToSavedForLater(id)
                }
            }
        },
        onSelect = { id ->
            if (!isSelecting) isSelecting = true
            toggleSelection(id)
        },
        onReveal = { id -> privacyGate.reveal(id, activity) },
        onAddToQueue = { addToQueueWorkId = it },
        onAddToCollection = { addToCollectionWorkId = it },
        onOpenComments = onOpenComments
    )

    BackHandler(enabled = isSelecting) { exitSelection() }
    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = isSelecting,
        customTitle = if (isSelecting) {
            if (selectedWorks.isEmpty()) "Select Works" else "${selectedWorks.size} Selected"
        } else {
            null
        },
        onBack = if (isSelecting) ({ exitSelection() }) else null,
        trailingContent = {
            if (isSelecting) {
                TextButton(
                    onClick = {
                        selection = if (allSelected) emptySet() else visibleIds
                    }
                ) {
                    Text(if (allSelected) "Deselect All" else "Select All", color = tokens.accent)
                }
            } else if (showsWorkControls || hideMature) {
                if (showsWorkControls) {
                    FilterButton(
                        filtersActive = filters.hasActiveFilters,
                        badgeCount = filters.activeCount,
                        onClick = { showFilters = true },
                        onClearFilters = { filters = LibraryFilterState() }
                    )
                }
                Box {
                    ToolbarCircleButton(
                        onClick = { showMenu = true },
                        accessibilityName = "More"
                    ) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        if (hideMature) {
                            DropdownMenuItem(
                                text = { Text(if (privacyState.revealAll) "Hide mature" else "Show mature") },
                                onClick = {
                                    showMenu = false
                                    privacyGate.toggleRevealAll(activity)
                                }
                            )
                        }
                        if (showsWorkControls) {
                            DropdownMenuItem(
                                text = { Text("Select") },
                                onClick = {
                                    showMenu = false
                                    isSelecting = true
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Layout") },
                                onClick = {
                                    showMenu = false
                                    showLayoutMenu = true
                                }
                            )
                            if (displayMode == HomeSectionDisplayMode.Detailed) {
                                DropdownMenuItem(
                                    text = { Text(if (expandAll) "Collapse All Cards" else "Expand All Cards") },
                                    onClick = {
                                        showMenu = false
                                        expandAll = !expandAll
                                    }
                                )
                            }
                        }
                    }
                    DropdownMenu(
                        expanded = showLayoutMenu,
                        onDismissRequest = { showLayoutMenu = false }
                    ) {
                        HomeSectionDisplayMode.entries.forEach { mode ->
                            DropdownMenuItem(
                                text = { Text(mode.title) },
                                trailingIcon = {
                                    if (mode == displayMode) Text("✓", color = tokens.accent)
                                },
                                onClick = {
                                    displayMode = mode
                                    preferences.edit()
                                        .putString("${kind.id}.displayMode", mode.name)
                                        .apply()
                                    showLayoutMenu = false
                                }
                            )
                        }
                    }
                }
            }
        }
    )

    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(tokens.scopePalette)
    ) {
        if (sectionItems.isEmpty()) {
            val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = topInset + 72.dp, start = 16.dp, end = 16.dp)
            ) {
                item { LibraryPlainEmptyState(title = "Nothing here yet", icon = HomeEmptyIcons.collections) }
            }
        } else if (displayMode == HomeSectionDisplayMode.Compact) {
            KudosRefreshBox(
                onRefresh = {
                    val refresher = metadataRefresh ?: return@KudosRefreshBox
                    visibleItems.forEach { refresher.refresh(it.item.work) }
                },
                modifier = Modifier.fillMaxSize()
            ) {
                HomeSectionCompactGrid(
                    kind = kind,
                    sectionItems = sectionItems,
                    filteredItems = filteredItems,
                    visibleItems = visibleItems,
                    filters = filters,
                    sort = sort,
                    updatePill = updatePill,
                    snapshot = snapshot,
                    cardActions = cardActions,
                    isSelecting = isSelecting,
                    selection = selection,
                    onFiltersChange = { filters = it },
                    onUpdatePillChange = { updatePill = it },
                    onEditFilters = { showFilters = true },
                    onClearFilters = { filters = LibraryFilterState(); sort = LibrarySort.Natural },
                    bottomPadding = if (isSelecting) 100.dp else 18.dp
                )
            }
        } else {
            KudosRefreshBox(
                onRefresh = {
                    val refresher = metadataRefresh ?: return@KudosRefreshBox
                    visibleItems.forEach { refresher.refresh(it.item.work) }
                },
                modifier = Modifier.fillMaxSize()
            ) {
                val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        top = topInset + 56.dp,
                        bottom = if (isSelecting) 100.dp else 18.dp
                    ),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        HomeSectionSubjectHeader(kind, sectionItems, visibleItems, filters, updatePill)
                    }
                    if (kind.hasQuickPills || filters.hasActiveFilters) {
                        item {
                            HomeSectionFilterRail(
                                kind = kind,
                                sectionItems = sectionItems,
                                filteredItems = filteredItems,
                                filters = filters,
                                updatePill = updatePill,
                                snapshot = snapshot,
                                onFiltersChange = { filters = it },
                                onUpdatePillChange = { updatePill = it }
                            )
                        }
                    }
                    item {
                        SectionRuleHeader(
                            title = kind.groupTitle,
                            count = visibleItems.size,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                    when {
                        visibleItems.isNotEmpty() -> items(
                            visibleItems,
                            key = { "${kind.id}-${it.item.work.id}" }
                        ) { display ->
                            if (displayMode == HomeSectionDisplayMode.Detailed) {
                                LibrarySubjectLedgerRow(
                                    display = display,
                                    kind = LibrarySectionKind.Downloaded,
                                    actions = cardActions,
                                    onRemoveFromHistory = cardActions.onRemove,
                                    onRemoveFromAllQueues = removeFromAllQueues,
                                    selected = display.item.work.id in selection,
                                    selecting = isSelecting,
                                    showsZeroStats = snapshot?.showsZeroStats ?: true,
                                    expandAll = expandAll
                                )
                            } else {
                                HomeSectionLedgerRow(
                                    display = display,
                                    actions = cardActions,
                                    selected = display.item.work.id in selection,
                                    selecting = isSelecting,
                                    onRemoveFromAllQueues = removeFromAllQueues
                                )
                            }
                        }
                        updatePill != HomeUpdatePill.All && filteredItems.isNotEmpty() -> item {
                            HomeUpdatePillEmptyState(updatePill) { updatePill = HomeUpdatePill.All }
                        }
                        filters.hasActiveFilters || sort != LibrarySort.Natural -> item {
                            HomeFilterCollisionCard(
                                kind = kind,
                                works = sectionItems,
                                filters = filters,
                                snapshot = snapshot,
                                onFiltersChange = { filters = it },
                                onClear = { filters = LibraryFilterState(); sort = LibrarySort.Natural },
                                onEdit = { showFilters = true }
                            )
                        }
                    }
                }
            }
        }

        if (isSelecting) {
            WorkBulkActionBar(
                selectedWorks = selectedWorks,
                workRepository = workRepository,
                queueRepository = queueRepository,
                downloadQueue = downloadQueue,
                onDeleted = ::exitSelection,
                onDone = ::exitSelection,
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }

    // The Library's own two dialogs; these menu entries used to do nothing here.
    addToQueueWorkId?.let { workId ->
        var queues by remember(workId) { mutableStateOf<List<LibraryQueuePreview>>(emptyList()) }
        LaunchedEffect(workId) {
            queues = runCatching { queueRepository?.queuePreviews() }.getOrNull().orEmpty()
        }
        AddToQueueDialog(
            queues = queues,
            onAdd = { queueId ->
                addToQueueWorkId = null
                scope.launch { runCatching { queueRepository?.addWork(queueId, workId) } }
            },
            onManageQueues = {
                addToQueueWorkId = null
                onOpenReadingQueues()
            },
            onDismiss = { addToQueueWorkId = null }
        )
    }
    addToCollectionWorkId?.let { workId ->
        AddToCollectionDialog(
            workId = workId,
            collections = snapshot?.collections.orEmpty(),
            workRepository = workRepository,
            scope = scope,
            onSetMembership = { collectionId, member ->
                scope.launch {
                    runCatching {
                        if (member) {
                            workRepository.addWorkToCollection(workId, collectionId)
                        } else {
                            workRepository.removeFromCollection(workId, collectionId)
                        }
                    }
                }
            },
            onDismiss = { addToCollectionWorkId = null }
        )
    }

    if (showFilters) {
        LibraryFilterPanel(
            filters = filters,
            sort = sort,
            userTags = snapshot?.userTags.orEmpty(),
            collections = snapshot?.collections.orEmpty(),
            works = sectionItems.map { it.item.work },
            onFiltersChange = { filters = it },
            onSortChange = { sort = it },
            onApply = { showFilters = false },
            onClear = {
                filters = LibraryFilterState()
                sort = LibrarySort.Natural
            },
            onDismiss = { showFilters = false }
        )
    }

    DestructiveConfirmation(
        show = pendingDelete != null,
        title = "Delete this work?",
        text = "Kudos will move this work to Recently Deleted. You can restore it for the next 90 days.",
        confirmText = "Delete",
        confirmBeforeDelete = snapshot?.confirmBeforeDelete ?: true,
        onConfirm = {
            val id = pendingDelete
            pendingDelete = null
            if (id != null) scope.launch { workRepository.softDelete(id) }
        },
        onDismissRequest = { pendingDelete = null }
    )
}

@Composable
private fun HomeSectionCompactGrid(
    kind: HomeSectionKind,
    sectionItems: List<LibraryDisplayItem>,
    filteredItems: List<LibraryDisplayItem>,
    visibleItems: List<LibraryDisplayItem>,
    filters: LibraryFilterState,
    sort: LibrarySort,
    updatePill: HomeUpdatePill,
    snapshot: LibrarySnapshot?,
    cardActions: LibraryCardActions,
    isSelecting: Boolean,
    selection: Set<String>,
    onFiltersChange: (LibraryFilterState) -> Unit,
    onUpdatePillChange: (HomeUpdatePill) -> Unit,
    onEditFilters: () -> Unit,
    onClearFilters: () -> Unit,
    bottomPadding: Dp
) {
    val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
    LazyVerticalGrid(
        columns = GridCells.Adaptive(SubjectWorkCardMetrics.width),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = 16.dp,
            top = topInset + 56.dp,
            end = 16.dp,
            bottom = bottomPadding
        ),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            HomeSectionSubjectHeader(kind, sectionItems, visibleItems, filters, updatePill)
        }
        if (kind.hasQuickPills || filters.hasActiveFilters) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                HomeSectionFilterRail(
                    kind = kind,
                    sectionItems = sectionItems,
                    filteredItems = filteredItems,
                    filters = filters,
                    updatePill = updatePill,
                    snapshot = snapshot,
                    onFiltersChange = onFiltersChange,
                    onUpdatePillChange = onUpdatePillChange
                )
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            SectionRuleHeader(
                title = kind.groupTitle,
                count = visibleItems.size,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        when {
            visibleItems.isNotEmpty() -> gridItems(
                visibleItems,
                key = { "${kind.id}-${it.item.work.id}" }
            ) { display ->
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                    LibrarySubjectWorkCard(
                        display = display,
                        kind = if (kind == HomeSectionKind.ReadingNow) {
                            LibrarySectionKind.ReadingNow
                        } else {
                            LibrarySectionKind.Downloaded
                        },
                        actions = cardActions,
                        selected = display.item.work.id in selection,
                        selecting = isSelecting,
                        footerOverride = kind.updateFooter(display.item.work)
                    )
                }
            }
            filters.hasActiveFilters || sort != LibrarySort.Natural -> item(span = { GridItemSpan(maxLineSpan) }) {
                HomeFilterCollisionCard(
                    kind = kind,
                    works = sectionItems,
                    filters = filters,
                    snapshot = snapshot,
                    onFiltersChange = onFiltersChange,
                    onClear = onClearFilters,
                    onEdit = onEditFilters
                )
            }
        }
    }
}

@Composable
private fun HomeSectionSubjectHeader(
    kind: HomeSectionKind,
    sectionItems: List<LibraryDisplayItem>,
    visibleItems: List<LibraryDisplayItem>,
    filters: LibraryFilterState,
    updatePill: HomeUpdatePill
) {
    val narrowed = filters.hasActiveFilters ||
        (kind == HomeSectionKind.RecentlyUpdated && updatePill != HomeUpdatePill.All)
    val subtitle = if (narrowed && visibleItems.isEmpty() && sectionItems.isNotEmpty()) {
        val count = sectionItems.size
        "$count ${if (count == 1) "work" else "works"} · none match the current filters"
    } else {
        val count = visibleItems.size
        "$count ${if (count == 1) "work" else "works"} · ${kind.orderDescription}"
    }
    SubjectHeaderBlock(
        kicker = "Home",
        title = kind.title,
        subtitle = subtitle,
        palette = LocalKudosTokens.current.scopePalette
    )
}

@Composable
private fun HomeSectionFilterRail(
    kind: HomeSectionKind,
    sectionItems: List<LibraryDisplayItem>,
    filteredItems: List<LibraryDisplayItem>,
    filters: LibraryFilterState,
    updatePill: HomeUpdatePill,
    snapshot: LibrarySnapshot?,
    onFiltersChange: (LibraryFilterState) -> Unit,
    onUpdatePillChange: (HomeUpdatePill) -> Unit
) {
    val palette = LocalKudosTokens.current.scopePalette
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (kind == HomeSectionKind.ReadingNow) {
            val countBase = LibraryQuery.filterOnly(
                sectionItems,
                filters = filters.copy(completion = LibraryCompletionFilter.Any)
            )
            val pills = listOf(
                LibraryCompletionFilter.Any to "All ${countBase.size}",
                LibraryCompletionFilter.InProgress to "WIP ${countBase.count { !it.item.work.isComplete }}"
            )
            items(pills, key = { it.first.name }) { (completion, label) ->
                SubjectChip(
                    text = label,
                    style = SubjectChipStyle.Pill(filters.completion == completion),
                    palette = palette,
                    modifier = Modifier.clickable {
                        onFiltersChange(filters.copy(completion = completion))
                    }
                )
            }
        } else if (kind == HomeSectionKind.RecentlyUpdated) {
            items(HomeUpdatePill.entries, key = { it.name }) { pill ->
                SubjectChip(
                    text = "${pill.title} ${pill.apply(filteredItems).size}",
                    style = SubjectChipStyle.Pill(updatePill == pill),
                    palette = palette,
                    modifier = Modifier.clickable { onUpdatePillChange(pill) }
                )
            }
        }
        items(
            homeFilterSummaryLabels(
                filters,
                snapshot,
                includeCompletion = kind != HomeSectionKind.ReadingNow
            ),
            key = { it }
        ) { label ->
            SubjectChip(text = label, style = SubjectChipStyle.Tinted, palette = palette)
        }
    }
}

@Composable
private fun HomeSectionLedgerRow(
    display: LibraryDisplayItem,
    actions: LibraryCardActions,
    selected: Boolean,
    selecting: Boolean,
    onRemoveFromAllQueues: (String) -> Unit
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    val row: @Composable () -> Unit = {
        WorkLedgerRow(
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
            signals = defaultWorkSignals(
                work.rating,
                work.workCategories,
                work.workWarnings,
                work.isComplete
            ),
            obscured = obscured,
            favorite = work.isFavorite,
            selected = selecting && selected,
            onClick = {
                when {
                    selecting -> actions.onSelect(work.id)
                    obscured -> actions.onReveal(work.id)
                    work.hasEpub -> actions.onOpenReader(work.id)
                    else -> actions.onOpenWork(work.id)
                }
            },
            onLongClick = { if (!obscured && !selecting) menuOpen = true },
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
        )
    }
    Box {
        if (selecting || obscured) {
            row()
        } else {
            SwipeActionRow(
                leading = leadingSwipeActions(work, LibrarySectionKind.Downloaded, actions),
                trailing = trailingSwipeActions(
                    work,
                    LibrarySectionKind.Downloaded,
                    actions,
                    actions.onRemove,
                    onRemoveFromAllQueues
                ),
                content = row
            )
        }
        LibraryWorkMenu(menuOpen, { menuOpen = false }, work, actions)
    }
}

@Composable
private fun HomeFilterCollisionCard(
    kind: HomeSectionKind,
    works: List<LibraryDisplayItem>,
    filters: LibraryFilterState,
    snapshot: LibrarySnapshot?,
    onFiltersChange: (LibraryFilterState) -> Unit,
    onClear: () -> Unit,
    onEdit: () -> Unit
) {
    LibraryFilterCollisionCard(
        sectionTitle = kind.title,
        works = works,
        filters = filters,
        userTagNames = snapshot?.userTags.orEmpty().associate { it.id to it.name },
        collectionNames = snapshot?.collections.orEmpty().associate { it.id to it.name },
        onFiltersChange = onFiltersChange,
        onClear = onClear,
        onEdit = onEdit,
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

@Composable
private fun HomeUpdatePillEmptyState(pill: HomeUpdatePill, onShowAll: () -> Unit) {
    LibraryPlainEmptyState(
        title = "No ${pill.title.lowercase()} works",
        icon = if (pill == HomeUpdatePill.Unread) Icons.Outlined.AutoAwesome else Icons.Outlined.Download,
        actionLabel = "Show All",
        onAction = onShowAll,
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

private val HomeSectionKind.hasQuickPills: Boolean
    get() = this == HomeSectionKind.ReadingNow || this == HomeSectionKind.RecentlyUpdated

private val HomeSectionKind.groupTitle: String
    get() = when (this) {
        HomeSectionKind.ReadingNow -> "In progress"
        HomeSectionKind.RecentlyUpdated -> "New chapters"
        HomeSectionKind.Favorites -> "Favorites"
        HomeSectionKind.RecentlyOpened -> "Recently opened"
    }

private val HomeSectionKind.orderDescription: String
    get() = when (this) {
        HomeSectionKind.RecentlyUpdated -> "newest check first"
        HomeSectionKind.ReadingNow,
        HomeSectionKind.Favorites,
        HomeSectionKind.RecentlyOpened -> "most recently read first"
    }

private fun HomeSectionKind.updateFooter(work: SavedWork): String? {
    if (this != HomeSectionKind.RecentlyUpdated) return null
    val known = work.knownChapterCount ?: (work.postedChapterCount - 1)
    return "+${(work.postedChapterCount - known).coerceAtLeast(1)} CH"
}

private fun homeFilterSummaryLabels(
    filters: LibraryFilterState,
    snapshot: LibrarySnapshot?,
    includeCompletion: Boolean
): List<String> = buildList {
    if (filters.favoriteOnly) add("Favorites")
    when (filters.finished) {
        LibraryFinishedFilter.Any -> Unit
        LibraryFinishedFilter.Finished -> add("Finished")
        LibraryFinishedFilter.Unfinished -> add("Unfinished")
    }
    when (filters.download) {
        LibraryDownloadFilter.Any -> Unit
        LibraryDownloadFilter.Downloaded -> add("Downloaded")
        LibraryDownloadFilter.NotDownloaded -> add("Not Downloaded")
    }
    if (includeCompletion) {
        when (filters.completion) {
            LibraryCompletionFilter.Any -> Unit
            LibraryCompletionFilter.Complete -> add("Complete")
            LibraryCompletionFilter.InProgress -> add("In Progress")
        }
    }
    val tagNames = snapshot?.userTags.orEmpty().associate { it.id to it.normalizedName }
    val collectionNames = snapshot?.collections.orEmpty().associate { it.id to it.name }
    filters.userTagIds.mapTo(this) { tagNames[it] ?: it }
    filters.collectionIds.mapTo(this) { collectionNames[it] ?: it }
    addAll(filters.ratings.sorted())
    if (filters.rating != AO3Rating.ANY) add(filters.rating.title)
    addAll(filters.warnings.sorted())
    addAll(filters.categories.sorted())
    addAll(filters.fandoms.sorted())
    addAll(filters.relationships.sorted())
    addAll(filters.characters.sorted())
    addAll(filters.freeforms.sorted())
    filters.excludeTags.sorted().forEach { add("−$it") }
    if (filters.language.isNotEmpty()) add(filters.language)
    val lower = filters.wordsFrom.trim()
    val upper = filters.wordsTo.trim()
    when {
        lower.isNotEmpty() && upper.isNotEmpty() -> add("Words $lower–$upper")
        lower.isNotEmpty() -> add(lower.toIntOrNull()?.let { "${it.compactCount()}+ words" } ?: "Words ≥ $lower")
        upper.isNotEmpty() -> add("Words ≤ $upper")
    }
}
