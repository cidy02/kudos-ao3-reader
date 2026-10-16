package io.github.cidy02.kudos.library

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.rememberWorkDownloading
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Set by Queue details → tag manager, then read once when this page resumes. */
object QueueShowOnlyTag {
    var name: String? = null
}

private enum class QueueDisplayMode { Compact, Ledger, Detailed }

@Composable
fun QueuePageScreen(
    repository: ReadingQueueRepository,
    queueId: String,
    epubBytes: (String) -> Long,
    metadataRefresh: WorkMetadataRefresh? = null,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate? = null,
    downloadQueue: DownloadQueue? = null,
    /** With it, Select mode has iOS's bar (brief 3ck); without it, only Remove, as before. */
    workRepository: io.github.cidy02.kudos.works.WorkRepository? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onManageQueue: (String) -> Unit,
    onBackToOrganizer: (() -> Unit)? = null,
    workImporter: io.github.cidy02.kudos.works.WorkImporter? = null,
    onOpenComments: (Long) -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var queue by remember(queueId) { mutableStateOf<ReadingQueue?>(null) }
    var works by remember(queueId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    var tags by remember(queueId) { mutableStateOf<List<String>>(emptyList()) }
    var bytes by remember(queueId) { mutableStateOf<Map<String, Long>>(emptyMap()) }
    var userTags by remember(queueId) { mutableStateOf<Map<String, Set<String>>>(emptyMap()) }
    var reload by remember(queueId) { mutableIntStateOf(0) }
    var quick by rememberSaveable(queueId) { mutableStateOf(QueueQuickFilter.All) }
    var filters by remember(queueId) { mutableStateOf(LibraryFilterState()) }
    var sort by remember(queueId) { mutableStateOf(LibrarySort.Natural) }
    var filterText by remember(queueId) { mutableStateOf("") }
    val index by remember(workRepository) { workRepository?.observeLibraryIndex()
        ?: flowOf(io.github.cidy02.kudos.works.WorkLibraryIndex()) }
        .collectAsState(initial = io.github.cidy02.kudos.works.WorkLibraryIndex())
    val filtersActive = filters.hasActiveFilters || filterText.isNotBlank() || sort != LibrarySort.Natural
    val filterBadge = filters.activeCount + (if (filterText.isNotBlank()) 1 else 0)
    var onlyTag by remember(queueId) { mutableStateOf<String?>(null) }
    var displayMode by rememberSaveable { mutableStateOf(QueueDisplayMode.Compact) }
    var expandAll by rememberSaveable { mutableStateOf(false) }
    var selecting by remember(queueId) { mutableStateOf(false) }
    var reordering by remember(queueId) { mutableStateOf(false) }
    var selected by remember(queueId) { mutableStateOf<Set<String>>(emptySet()) }
    var menu by remember { mutableStateOf(false) }
    var showFilters by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var removeOne by remember(queueId) { mutableStateOf<SavedWork?>(null) }
    var showRemove by remember { mutableStateOf(false) }
    var showTag by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(queueId, reload) {
        QueueShowOnlyTag.name?.let {
            onlyTag = it
            QueueShowOnlyTag.name = null
        }
        val loaded = runCatching { loadPage(repository, queueId, epubBytes) }.getOrElse {
            error = it.message ?: "Could not load this queue."
            return@LaunchedEffect
        }
        queue = loaded.queue
        works = loaded.works
        tags = loaded.tags
        bytes = loaded.bytes
        userTags = loaded.userTags
        error = if (loaded.queue == null) "This reading queue no longer exists." else null
    }

    BackHandler(enabled = selecting || reordering) {
        selecting = false
        reordering = false
        selected = emptySet()
    }

    BackHandler(enabled = onBackToOrganizer != null && !selecting && !reordering) {
        onBackToOrganizer?.invoke()
    }

    val activity = LocalContext.current as? FragmentActivity
    val shownSettings by remember(settingsRepository) {
        settingsRepository?.settings ?: flowOf(
            KudosSettings(privacy = PrivacySettings(hideMatureContent = false))
        )
    }.collectAsState(
        initial = if (settingsRepository == null) {
            KudosSettings(privacy = PrivacySettings(hideMatureContent = false))
        } else {
            KudosSettings.Defaults
        }
    )
    val reveal by remember(privacyGate) {
        privacyGate?.state ?: MutableStateFlow(PrivacyRevealState())
    }.collectAsState()
    val current = queue
    val palette = if (current == null) tokens.scopePalette else queuePalette(tokens.theme, current)
    val preservedIds = works.filter { it.hasEpub && (bytes[it.id] ?: 0L) > 0 }.map { it.id }.toSet()
    val narrowed = quick != QueueQuickFilter.All || filtersActive || onlyTag != null
    val hidesMature = works.any { isHiddenMature(it, shownSettings, reveal) }
    val filtered = LibraryQuery.applyScoped(works, index, filterText, filters, sort).filter { work ->
        !isHiddenMature(work, shownSettings, reveal) &&
            quick.matches(work, work.id in preservedIds) &&
            (onlyTag == null || onlyTag in userTags[work.id].orEmpty())
    }
    val dragLive = ReadingQueueFacts.isDragLive(reordering && !hidesMature, selecting, narrowed)
    val shown = if (reordering && !hidesMature) works else filtered
    // A selection acts on what is on screen (iOS `selectedWorks`, L3 B2 #1): a work the quick
    // filter hides leaves it, so Remove never takes a work unseen (audit A5-6).
    val shownIds = shown.mapTo(linkedSetOf()) { it.id }
    LaunchedEffect(shownIds, selected) {
        val seen = LibrarySelection.visible(selected, shownIds)
        if (seen.size != selected.size) selected = seen
    }
    val (upNext, inLine) = if (dragLive) null to shown else ReadingQueueFacts.upNext(filtered)
    val preservedBytes = preservedIds.sumOf { bytes[it] ?: 0L }
    val reorderLabel = when {
        narrowed -> "Clear Filters to Reorder"
        hidesMature -> "Show Mature to Reorder"
        else -> "Reorder"
    }

    val workActions = workRepository?.let {
        scopedWorkActions(
            it, repository, downloadQueue, workImporter, shownSettings.app.confirmBeforeDelete,
            onOpenWork, onOpenReader, onOpenComments,
            onSelect = { id -> selecting = true; selected = setOf(id) },
            onReveal = { id -> privacyGate?.reveal(id, activity) },
            onChanged = { reload += 1 }
        )
    }

    fun activate(work: SavedWork) {
        when {
            selecting -> selected = toggleId(selected, work.id)
            isObscuredMature(work, shownSettings, reveal) -> privacyGate?.reveal(work.id, activity)
            else -> openWork(work, onOpenReader, onOpenWork)
        }
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = selecting,
        onBack = when {
            selecting || reordering -> {
                {
                    selecting = false
                    reordering = false
                    selected = emptySet()
                }
            }
            onBackToOrganizer != null -> {
                { onBackToOrganizer.invoke() }
            }
            else -> null
        },
        trailingContent = if (current != null) {
            {
                PageToolbarActions(
                    palette = palette,
                    selecting = selecting,
                    selectedCount = selected.size,
                    total = shown.size,
                    filtersActive = filtersActive,
                    badge = filterBadge,
                    custom = current.kindRaw == ReadingQueueKind.CUSTOM,
                    canReorder = works.size > 1 && !narrowed && !hidesMature,
                    reorderLabel = reorderLabel,
                    showMatureToggle = shownSettings.privacy.hideMatureContent,
                    matureRevealed = reveal.revealAll,
                    menuOpen = menu,
                    onAdd = { showAdd = true },
                    onFilter = { showFilters = true },
                    onClearFilters = { filters = LibraryFilterState(); sort = LibrarySort.Natural; filterText = ""; quick = QueueQuickFilter.All; onlyTag = null },
                    onMenu = { menu = true },
                    onDismissMenu = { menu = false },
                    onToggleMature = { privacyGate?.toggleRevealAll(activity) },
                    onSelect = { if (works.isNotEmpty()) { selecting = true; reordering = false } },
                    onReorder = { reordering = true; selecting = false; selected = emptySet() },
                    onDisplay = { displayMode = it; menu = false },
                    displayMode = displayMode,
                    expandAll = expandAll, onExpandAll = { expandAll = !expandAll; menu = false },
                    onDetails = { onManageQueue(current.id) },
                    onEdit = { showEdit = true },
                    onDelete = { showDelete = true },
                    onSelectAll = {
                        selected = if (shown.all { it.id in selected } && shown.isNotEmpty()) {
                            emptySet()
                        } else {
                            shown.map { it.id }.toSet()
                        }
                    },
                    onRemove = { showRemove = true },
                    onDone = { selecting = false; reordering = false; selected = emptySet() },
                    showsRemove = workRepository == null
                )
            }
        } else null
    )

    KudosRefreshBox(
        onRefresh = {
            reload += 1
            val refresh = metadataRefresh
            if (refresh != null) {
                works.forEach { work -> runCatching { refresh.refresh(work) } }
                reload += 1
            }
        },
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            Modifier.fillMaxSize().subjectScreenWash(palette).verticalScroll(rememberScrollState())
                // Room for the selection bar under the last row.
                .padding(bottom = if (selecting && workRepository != null) 88.dp else 0.dp)
        ) {
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
            if (current != null) {
                SubjectHeaderBlock(
                    kicker = ReadingQueueFacts.kicker("Home"),
                    title = if (selecting) "${selected.size} selected" else current.displayName,
                    subtitle = if (selecting) null else ReadingQueueFacts.subtitle(
                        works.size,
                        preservedIds.size,
                        preservedBytes
                    ),
                    palette = palette,
                    modifier = Modifier.padding(top = 4.dp)
                )
                if (!reordering) {
                    QueueHeaderDetails(
                        works = works,
                        preservedIds = preservedIds,
                        tags = tags,
                        palette = palette,
                        quickFilter = quick,
                        onQuickFilter = { quick = it },
                        onAddTag = { showTag = true },
                        modifier = Modifier.padding(top = 12.dp)
                    )
                }
                when {
                    works.isEmpty() -> EmptyCopy(
                        title = "Add works",
                        message = "Works you add show up here, in the order you choose.",
                        action = null,
                        onAction = {}
                    )
                    shown.isEmpty() -> EmptyCopy(
                        title = "No matching works",
                        message = "Your filters don't match any works in this queue.",
                        action = "Clear Filters",
                        onAction = { filters = LibraryFilterState(); sort = LibrarySort.Natural; filterText = ""; quick = QueueQuickFilter.All; onlyTag = null }
                    )
                    dragLive -> {
                        SectionRuleHeader("Queue", count = shown.size, modifier = Modifier.padding(top = 16.dp))
                        shown.forEach { work ->
                            key(work.id) {
                                WorkRow(
                                    work = work,
                                    downloadQueue = downloadQueue,
                                    actions = workActions,
                                    detailed = displayMode == QueueDisplayMode.Detailed, expandAll = expandAll,
                                    onRemove = { removeOne = work },
                                    obscured = isObscuredMature(work, shownSettings, reveal),
                                    selecting = selecting,
                                    selected = work.id in selected,
                                    drag = true,
                                    onClick = { activate(work) },
                                    onStep = { delta ->
                                        val index = works.indexOfFirst { it.id == work.id }
                                        val next = moveWork(works, index, delta) ?: return@WorkRow
                                        works = next
                                        scope.launch { repository.updateSortOrder(queueId, next.map { it.id }) }
                                    }
                                )
                            }
                        }
                    }
                    else -> {
                        upNext?.let { work ->
                            SectionRuleHeader("Up Next", modifier = Modifier.padding(top = 16.dp))
                            key(work.id) {
                                WorkRow(
                                    work = work,
                                    downloadQueue = downloadQueue,
                                    actions = workActions,
                                    detailed = displayMode == QueueDisplayMode.Detailed, expandAll = expandAll,
                                    onRemove = { removeOne = work },
                                    obscured = isObscuredMature(work, shownSettings, reveal),
                                    selecting = selecting,
                                    selected = work.id in selected,
                                    drag = false,
                                    onClick = { activate(work) },
                                    onStep = {}
                                )
                            }
                        }
                        if (inLine.isNotEmpty()) {
                            SectionRuleHeader("In Line", count = inLine.size, modifier = Modifier.padding(top = 8.dp))
                            if (displayMode == QueueDisplayMode.Compact) {
                                Column(Modifier.padding(horizontal = 12.dp)) {
                                    inLine.chunked(2).forEach { row ->
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            row.forEach { work ->
                                                key(work.id) {
                                                    val downloading = rememberWorkDownloading(work, downloadQueue)
                                                    QueueWorkItem(
                                                        work, workActions, selecting || reordering,
                                                        isObscuredMature(work, shownSettings, reveal),
                                                        onClick = { activate(work) }, onRemove = { removeOne = work }
                                                    ) { _ ->
                                                        SubjectWorkCoverCard(
                                                            work = work,
                                                            obscured = isObscuredMature(work, shownSettings, reveal),
                                                            downloading = downloading,
                                                            isSelecting = selecting,
                                                            isSelected = work.id in selected
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                inLine.forEach { work ->
                                    key(work.id) {
                                        WorkRow(
                                            work = work,
                                            downloadQueue = downloadQueue,
                                            actions = workActions,
                                            detailed = displayMode == QueueDisplayMode.Detailed, expandAll = expandAll,
                                            onRemove = { removeOne = work },
                                            obscured = isObscuredMature(work, shownSettings, reveal),
                                            selecting = selecting,
                                            selected = work.id in selected,
                                            drag = false,
                                            onClick = { activate(work) },
                                            onStep = {}
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (selecting && workRepository != null) {
        // iOS 1bg: "the four things a queue can do to a selection", and the rest under More.
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            ScopedSelectionBar(
                selectedWorks = works.filter { it.id in selected },
                removeLabel = "Remove from Queue",
                scopeName = "queue",
                workRepository = workRepository,
                workImporter = workImporter,
                queueRepository = repository,
                downloadQueue = downloadQueue,
                palette = palette,
                currentQueueId = queueId,
                onRemove = { selected.forEach { repository.removeWork(queueId, it) } },
                onChanged = { reload += 1 },
                onDone = { selecting = false; selected = emptySet(); reload += 1 }
            )
        }
    }

    if (showFilters) {
        LibraryFilterPanel(
            filters = filters, sort = sort, userTags = index.userTags, collections = index.collections,
            works = works, searchQuery = filterText, onSearchQueryChange = { filterText = it },
            onFiltersChange = { filters = it }, onSortChange = { sort = it },
            onClear = { filters = LibraryFilterState(); sort = LibrarySort.Natural; filterText = "";
                quick = QueueQuickFilter.All; onlyTag = null },
            onApply = { showFilters = false }, onDismiss = { showFilters = false }
        )
    }
    if (showAdd && current != null) {
        var candidates by remember(current.id) { mutableStateOf<List<SavedWork>?>(null) }
        LaunchedEffect(current.id) {
            candidates = runCatching { repository.worksAvailableToAdd(current.id) }.getOrDefault(emptyList())
        }
        candidates?.let { available ->
            AddLibraryWorksSheet(
                destinationName = current.displayName,
                scopeName = "queue",
                candidates = available,
                privacy = shownSettings.privacy,
                reveal = reveal,
                onToggleMature = { privacyGate?.toggleRevealAll(activity) },
                onDismiss = { showAdd = false },
                onAdd = { chosen ->
                    showAdd = false
                    // On the end of the queue, in the order the picker showed them (iOS `append`).
                    scope.launch {
                        chosen.forEach { repository.addWork(current.id, it.id) }
                        reload += 1
                    }
                }
            )
        }
    }
    if (showEdit && current != null && current.kindRaw == ReadingQueueKind.CUSTOM) {
        QueueEditorSheet(
            repository = repository,
            existing = current,
            onDismiss = { showEdit = false },
            onSaved = { showEdit = false; reload += 1 }
        )
    }
    if (showTag && current != null) {
        QueueTagSheet(
            repository = repository,
            queues = listOf(current),
            palette = palette,
            onDismiss = { showTag = false; reload += 1 }
        )
    }
    if (showDelete && current != null) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text(ReadingQueueFacts.deleteTitle(listOf(current))) },
            text = { Text(ReadingQueueFacts.deleteMessage(1)) },
            confirmButton = {
                TextButton(onClick = {
                    showDelete = false
                    scope.launch {
                        repository.deleteQueue(current.id)
                        onBackToOrganizer?.invoke()
                    }
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text("Cancel") } }
        )
    }
    removeOne?.let { work ->
        AlertDialog(
            onDismissRequest = { removeOne = null }, title = { Text("Remove this work?") },
            text = { Text("This work will leave this queue. It will stay in your Library.") },
            confirmButton = { TextButton(onClick = {
                removeOne = null
                scope.launch { repository.removeWork(queueId, work.id); reload += 1 }
            }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { removeOne = null }) { Text("Cancel") } }
        )
    }
    if (showRemove) {
        val count = selected.size
        AlertDialog(
            onDismissRequest = { showRemove = false },
            title = { Text(SelectionActions.removeTitle(count)) },
            text = { Text(SelectionActions.removeMessage("queue")) },
            confirmButton = {
                TextButton(onClick = {
                    val ids = selected
                    showRemove = false
                    scope.launch {
                        ids.forEach { repository.removeWork(queueId, it) }
                        selected = emptySet()
                        selecting = false
                        reload += 1
                    }
                }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { showRemove = false }) { Text("Cancel") } }
        )
    }
    error?.let { message ->
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text("Reading queue") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }
        )
    }
}

@Composable
private fun PageToolbarActions(
    palette: io.github.cidy02.kudos.ui.subject.SubjectPalette,
    selecting: Boolean,
    selectedCount: Int,
    total: Int,
    filtersActive: Boolean,
    badge: Int,
    custom: Boolean,
    canReorder: Boolean,
    reorderLabel: String,
    showMatureToggle: Boolean,
    matureRevealed: Boolean,
    menuOpen: Boolean,
    onAdd: () -> Unit,
    onFilter: () -> Unit,
    onClearFilters: () -> Unit,
    onMenu: () -> Unit,
    onDismissMenu: () -> Unit,
    onToggleMature: () -> Unit,
    onSelect: () -> Unit,
    onReorder: () -> Unit,
    onDisplay: (QueueDisplayMode) -> Unit,
    displayMode: QueueDisplayMode,
    expandAll: Boolean,
    onExpandAll: () -> Unit,
    onDetails: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onSelectAll: () -> Unit,
    onRemove: () -> Unit,
    onDone: () -> Unit,
    showsRemove: Boolean = true
) {
    if (selecting) {
        TextButton(onClick = onSelectAll) {
            Text(if (selectedCount == total && total > 0) "Deselect All" else "Select All", color = palette.accent)
        }
        if (showsRemove) TextButton(onClick = onRemove, enabled = selectedCount > 0) { Text("Remove") }
        TextButton(onClick = onDone) { Text("Done", color = palette.accent) }
    } else {
        // iOS 1h: "an accent-filled + for adding works" (.glassProminent).
        ToolbarAddButton(onClick = onAdd, accessibilityName = "Add Works", palette = palette, prominent = true)
        FilterButton(
            filtersActive = filtersActive,
            onClick = onFilter,
            badgeCount = badge,
            onClearFilters = onClearFilters
        )
        Box {
            ToolbarCircleButton(onClick = onMenu, accessibilityName = "More") {
                Icon(Icons.Filled.MoreVert, contentDescription = null)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = onDismissMenu) {
                if (showMatureToggle) {
                    DropdownMenuItem(
                        text = { Text(if (matureRevealed) "Hide mature" else "Show mature") },
                        leadingIcon = {
                            Icon(
                                if (matureRevealed) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                contentDescription = null
                            )
                        },
                        onClick = { onDismissMenu(); onToggleMature() }
                    )
                }
                DropdownMenuItem(text = { Text("Select") }, onClick = { onDismissMenu(); onSelect() })
                DropdownMenuItem(
                    text = { Text(reorderLabel) },
                    enabled = canReorder,
                    onClick = { onDismissMenu(); if (canReorder) onReorder() }
                )
                QueueDisplayMode.entries.forEach { mode ->
                    DropdownMenuItem(text = { Text("${if (mode == displayMode) "✓ " else ""}Display · ${mode.name}") },
                        onClick = { onDisplay(mode) })
                }
                if (displayMode == QueueDisplayMode.Detailed) DropdownMenuItem(
                    text = { Text(if (expandAll) "Collapse All" else "Expand All") }, onClick = onExpandAll
                )
                DropdownMenuItem(text = { Text("Queue details") }, onClick = { onDismissMenu(); onDetails() })
                if (custom) {
                    DropdownMenuItem(text = { Text("Edit Queue") }, onClick = { onDismissMenu(); onEdit() })
                    DropdownMenuItem(text = { Text("Delete Queue") }, onClick = { onDismissMenu(); onDelete() })
                }
            }
        }
    }
}

@Composable
private fun WorkRow(
    work: SavedWork,
    downloadQueue: DownloadQueue?,
    actions: LibraryCardActions?,
    detailed: Boolean,
    expandAll: Boolean,
    onRemove: () -> Unit,
    obscured: Boolean,
    selecting: Boolean,
    selected: Boolean,
    drag: Boolean,
    onClick: () -> Unit,
    onStep: (Int) -> Unit
) {
    QueueWorkItem(work, actions, selecting || drag, obscured, onClick, onRemove) { openMenu ->
        if (detailed && !drag) io.github.cidy02.kudos.ui.components.SensitiveWorkRow(
            work = work, onOpenWork = { onClick() }, onLongClick = openMenu,
            expandAll = expandAll, selecting = selecting, selected = selected, obscured = obscured,
            onSelect = onClick, onReveal = onClick, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
        ) else QueueLedgerCard(
            work = work,
            downloading = rememberWorkDownloading(work, downloadQueue),
            obscured = obscured,
            selecting = selecting,
            selected = selected,
            drag = drag,
            onStep = onStep,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp)
        )
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun QueueWorkItem(
    work: SavedWork,
    actions: LibraryCardActions?,
    editing: Boolean,
    obscured: Boolean,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    content: @Composable (() -> Unit) -> Unit
) {
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    val row = @Composable {
        Box(Modifier.combinedClickable(onClick = onClick,
            onLongClick = { if (!editing && !obscured) menuOpen = true })) {
            content { if (!editing && !obscured) menuOpen = true }
            if (actions != null) LibraryWorkMenu(
                menuOpen, { menuOpen = false }, work, actions,
                scopedRemovalLabel = "Remove from Queue", onScopedRemove = onRemove
            )
        }
    }
    if (editing || obscured || actions == null) row()
    else SwipeActionRow(
        leading = leadingSwipeActions(work, LibrarySectionKind.ReadingNow, actions),
        trailing = listOf(SwipeAction("Remove", Icons.Outlined.RemoveCircleOutline,
            androidx.compose.material3.MaterialTheme.colorScheme.error, onRemove)),
        content = row
    )
}

@Composable
private fun EmptyCopy(title: String, message: String, action: String?, onAction: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.padding(horizontal = 24.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = tokens.primaryInk, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        Text(message, color = tokens.secondaryInk, fontSize = 15.sp)
        if (action != null) TextButton(onClick = onAction) { Text(action) }
    }
}

private fun isHiddenMature(
    work: SavedWork,
    settings: KudosSettings,
    reveal: PrivacyRevealState
): Boolean {
    return LibraryPrivacy.visibility(work, settings.privacy, reveal) == LibraryPrivacyVisibility.Hidden
}

private fun isObscuredMature(
    work: SavedWork,
    settings: KudosSettings,
    reveal: PrivacyRevealState
): Boolean {
    return LibraryPrivacy.visibility(work, settings.privacy, reveal) == LibraryPrivacyVisibility.Obscured
}

private fun openWork(work: SavedWork, onOpenReader: (String) -> Unit, onOpenWork: (String) -> Unit) {
    if (work.hasEpub) onOpenReader(work.id) else onOpenWork(work.id)
}

private fun toggleId(selected: Set<String>, id: String): Set<String> {
    return if (id in selected) selected - id else selected + id
}

private fun moveWork(works: List<SavedWork>, index: Int, delta: Int): List<SavedWork>? {
    val target = index + delta
    if (target !in works.indices) return null
    val next = works.toMutableList()
    val item = next.removeAt(index)
    next.add(target, item)
    return next
}

private data class PageLoad(
    val queue: ReadingQueue?,
    val works: List<SavedWork>,
    val tags: List<String>,
    val bytes: Map<String, Long>,
    val userTags: Map<String, Set<String>>
)

private suspend fun loadPage(
    repository: ReadingQueueRepository,
    queueId: String,
    epubBytes: (String) -> Long
): PageLoad {
    val queue = repository.getQueue(queueId)
    val items = if (queue == null) emptyList() else repository.listWorks(queueId)
    val works = items.mapNotNull { item -> item.work?.let { item to it } }
        .sortedWith(
            compareBy<Pair<QueueMembershipItem, SavedWork>> { it.first.membership.sortOrderInQueue }
                .thenByDescending { it.first.membership.queuedAt }
        )
        .map { it.second }
    val sizes = withContext(Dispatchers.IO) {
        works.associate { work -> work.id to runCatching { epubBytes(work.id) }.getOrDefault(0L) }
    }
    return PageLoad(
        queue = queue,
        works = works,
        tags = if (queue == null) emptyList() else repository.tagsForQueue(queueId).map { it.name },
        bytes = sizes,
        userTags = repository.userTagNamesByWork(works.map { it.id })
    )
}
