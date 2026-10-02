package io.github.cidy02.kudos.library

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Set by Queue details → tag manager, then read once when this page resumes. */
object QueueShowOnlyTag {
    var name: String? = null
}

private data class QueueExtraFilter(
    val text: String = "",
    val rating: String? = null,
    val completeOnly: Boolean = false
) {
    val activeCount: Int
        get() = listOf(text.isNotBlank(), rating != null, completeOnly).count { it }

    fun matches(work: SavedWork): Boolean {
        if (text.isNotBlank()) {
            val query = text.trim()
            if (!work.title.contains(query, ignoreCase = true) &&
                !work.author.contains(query, ignoreCase = true)
            ) {
                return false
            }
        }
        if (rating != null && work.rating != rating) return false
        if (completeOnly && !work.isComplete) return false
        return true
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QueuePageScreen(
    repository: ReadingQueueRepository,
    queueId: String,
    epubBytes: (String) -> Long,
    metadataRefresh: WorkMetadataRefresh? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onManageQueue: (String) -> Unit,
    onBackToOrganizer: (() -> Unit)? = null
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
    var extra by remember(queueId) { mutableStateOf(QueueExtraFilter()) }
    var onlyTag by remember(queueId) { mutableStateOf<String?>(null) }
    var compact by rememberSaveable(queueId) { mutableStateOf(false) }
    var selecting by remember(queueId) { mutableStateOf(false) }
    var reordering by remember(queueId) { mutableStateOf(false) }
    var selected by remember(queueId) { mutableStateOf<Set<String>>(emptySet()) }
    var menu by remember { mutableStateOf(false) }
    var showFilters by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
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

    BackHandler(enabled = onBackToOrganizer != null && !selecting && !reordering) {
        onBackToOrganizer?.invoke()
    }

    val current = queue
    val palette = if (current == null) tokens.scopePalette else queuePalette(tokens.theme, current)
    val preservedIds = works.filter { it.hasEpub && (bytes[it.id] ?: 0L) > 0 }.map { it.id }.toSet()
    val narrowed = quick != QueueQuickFilter.All || extra.activeCount > 0 || onlyTag != null
    val filtered = works.filter { work ->
        quick.matches(work, work.id in preservedIds) &&
            extra.matches(work) &&
            (onlyTag == null || onlyTag in userTags[work.id].orEmpty())
    }
    val dragLive = ReadingQueueFacts.isDragLive(reordering, selecting, narrowed)
    val shown = if (dragLive) works else filtered
    val (upNext, inLine) = if (dragLive) null to shown else ReadingQueueFacts.upNext(filtered)
    val preservedBytes = preservedIds.sumOf { bytes[it] ?: 0L }

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
        Column(Modifier.fillMaxSize().subjectScreenWash(palette).verticalScroll(rememberScrollState())) {
            if (current != null) {
                PageToolbar(
                    palette = palette,
                    selecting = selecting,
                    selectedCount = selected.size,
                    total = shown.size,
                    filtersActive = extra.activeCount > 0,
                    badge = extra.activeCount,
                    custom = current.kindRaw == ReadingQueueKind.CUSTOM,
                    canReorder = works.size > 1 && !narrowed,
                    menuOpen = menu,
                    onAdd = { showAdd = true },
                    onFilter = { showFilters = true },
                    onClearFilters = { extra = QueueExtraFilter(); quick = QueueQuickFilter.All; onlyTag = null },
                    onMenu = { menu = true },
                    onDismissMenu = { menu = false },
                    onSelect = { if (works.isNotEmpty()) { selecting = true; reordering = false } },
                    onReorder = { reordering = true; selecting = false; selected = emptySet() },
                    onDisplay = { compact = !compact; menu = false },
                    compact = compact,
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
                    onDone = { selecting = false; reordering = false; selected = emptySet() }
                )
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
                        onAction = { extra = QueueExtraFilter(); quick = QueueQuickFilter.All; onlyTag = null }
                    )
                    dragLive -> {
                        SectionRuleHeader("Queue", count = shown.size, modifier = Modifier.padding(top = 16.dp))
                        shown.forEachIndexed { index, work ->
                            WorkRow(
                                work = work,
                                compact = false,
                                selecting = selecting,
                                selected = work.id in selected,
                                drag = true,
                                onOpen = { openWork(work, onOpenReader, onOpenWork) },
                                onToggle = { selected = toggleId(selected, work.id) },
                                onStep = { delta ->
                                    val next = moveWork(works, index, delta) ?: return@WorkRow
                                    works = next
                                    scope.launch { repository.updateSortOrder(queueId, next.map { it.id }) }
                                }
                            )
                        }
                    }
                    compact -> {
                        upNext?.let { work ->
                            SectionRuleHeader("Up Next", modifier = Modifier.padding(top = 16.dp))
                            SubjectWorkCoverCard(
                                work = work,
                                obscured = false,
                                downloading = false,
                                modifier = Modifier
                                    .padding(horizontal = 16.dp)
                                    .clickable { openWork(work, onOpenReader, onOpenWork) }
                            )
                        }
                        if (inLine.isNotEmpty()) {
                            SectionRuleHeader("In Line", count = inLine.size, modifier = Modifier.padding(top = 8.dp))
                            FlowRow(
                                Modifier.padding(horizontal = 12.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                inLine.forEach { work ->
                                    SubjectWorkCoverCard(
                                        work = work,
                                        obscured = false,
                                        downloading = false,
                                        modifier = Modifier.clickable {
                                            if (selecting) selected = toggleId(selected, work.id)
                                            else openWork(work, onOpenReader, onOpenWork)
                                        },
                                        isSelecting = selecting,
                                        isSelected = work.id in selected
                                    )
                                }
                            }
                        }
                    }
                    else -> {
                        upNext?.let { work ->
                            SectionRuleHeader("Up Next", modifier = Modifier.padding(top = 16.dp))
                            WorkRow(
                                work = work,
                                compact = false,
                                selecting = selecting,
                                selected = work.id in selected,
                                drag = false,
                                onOpen = { openWork(work, onOpenReader, onOpenWork) },
                                onToggle = { selected = toggleId(selected, work.id) },
                                onStep = {}
                            )
                        }
                        if (inLine.isNotEmpty()) {
                            SectionRuleHeader("In Line", count = inLine.size, modifier = Modifier.padding(top = 8.dp))
                            inLine.forEach { work ->
                                WorkRow(
                                    work = work,
                                    compact = false,
                                    selecting = selecting,
                                    selected = work.id in selected,
                                    drag = false,
                                    onOpen = { openWork(work, onOpenReader, onOpenWork) },
                                    onToggle = { selected = toggleId(selected, work.id) },
                                    onStep = {}
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showFilters) {
        FilterDialog(extra, onDismiss = { showFilters = false }, onChange = { extra = it })
    }
    if (showAdd && current != null) {
        AddWorksDialog(
            repository = repository,
            queueId = current.id,
            onDismiss = { showAdd = false },
            onAdded = { showAdd = false; reload += 1 }
        )
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
    if (showRemove) {
        val count = selected.size
        AlertDialog(
            onDismissRequest = { showRemove = false },
            title = { Text(if (count == 1) "Remove this work from the queue?" else "Remove $count works from this queue?") },
            text = { Text("The works stay in Kudos.") },
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
                }) { Text("Remove from Queue") }
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
private fun PageToolbar(
    palette: io.github.cidy02.kudos.ui.subject.SubjectPalette,
    selecting: Boolean,
    selectedCount: Int,
    total: Int,
    filtersActive: Boolean,
    badge: Int,
    custom: Boolean,
    canReorder: Boolean,
    menuOpen: Boolean,
    onAdd: () -> Unit,
    onFilter: () -> Unit,
    onClearFilters: () -> Unit,
    onMenu: () -> Unit,
    onDismissMenu: () -> Unit,
    onSelect: () -> Unit,
    onReorder: () -> Unit,
    onDisplay: () -> Unit,
    compact: Boolean,
    onDetails: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onSelectAll: () -> Unit,
    onRemove: () -> Unit,
    onDone: () -> Unit
) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (selecting) {
            TextButton(onClick = onSelectAll) {
                Text(if (selectedCount == total && total > 0) "Deselect All" else "Select All", color = palette.accent)
            }
            TextButton(onClick = onRemove, enabled = selectedCount > 0) { Text("Remove from Queue") }
            TextButton(onClick = onDone) { Text("Done", color = palette.accent) }
        } else {
            GlassCircleButton(onClick = onAdd, accessibilityName = "Add Works", diameter = SubjectMetrics.toolbarCircle) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = palette.accent)
            }
            FilterButton(
                filtersActive = filtersActive,
                onClick = onFilter,
                badgeCount = badge,
                onClearFilters = onClearFilters
            )
            GlassCircleButton(onClick = onMenu, accessibilityName = "More", diameter = SubjectMetrics.toolbarCircle) {
                Icon(Icons.Filled.MoreHoriz, contentDescription = null)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = onDismissMenu) {
                DropdownMenuItem(text = { Text("Select") }, onClick = { onDismissMenu(); onSelect() })
                DropdownMenuItem(
                    text = { Text(if (canReorder) "Reorder" else "Clear Filters to Reorder") },
                    enabled = canReorder,
                    onClick = { onDismissMenu(); if (canReorder) onReorder() }
                )
                DropdownMenuItem(
                    text = { Text(if (compact) "Display mode: List" else "Display mode: Compact grid") },
                    onClick = onDisplay
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
    compact: Boolean,
    selecting: Boolean,
    selected: Boolean,
    drag: Boolean,
    onOpen: () -> Unit,
    onToggle: () -> Unit,
    onStep: (Int) -> Unit
) {
    if (compact) return
    val tokens = LocalKudosTokens.current
    WorkLedgerCard(
        work = work,
        modifier = Modifier
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable { if (selecting) onToggle() else onOpen() }
    ) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (selecting) SelectionBubble(selected)
            Column(Modifier.weight(1f)) {
                Text(work.title, color = tokens.primaryInk, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(work.author, color = tokens.secondaryInk, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (drag) DragGrip(Modifier.queueDragHandle(true, onStep))
        }
    }
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

@Composable
private fun FilterDialog(
    filter: QueueExtraFilter,
    onDismiss: () -> Unit,
    onChange: (QueueExtraFilter) -> Unit
) {
    var text by remember { mutableStateOf(filter.text) }
    var rating by remember { mutableStateOf(filter.rating) }
    var complete by remember { mutableStateOf(filter.completeOnly) }
    val ratings = listOf("General Audiences", "Teen And Up Audiences", "Mature", "Explicit", "Not Rated")
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Filter") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text("Title or author") }, singleLine = true)
                ratings.forEach { name ->
                    TextButton(onClick = { rating = if (rating == name) null else name }) {
                        Text(if (rating == name) "✓ $name" else name)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Complete", modifier = Modifier.weight(1f))
                    Switch(checked = complete, onCheckedChange = { complete = it })
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onChange(QueueExtraFilter(text, rating, complete))
                onDismiss()
            }) { Text("Done") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun AddWorksDialog(
    repository: ReadingQueueRepository,
    queueId: String,
    onDismiss: () -> Unit,
    onAdded: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var available by remember { mutableStateOf<List<SavedWork>>(emptyList()) }
    LaunchedEffect(queueId) {
        available = runCatching { repository.worksAvailableToAdd(queueId) }.getOrDefault(emptyList())
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Works") },
        text = {
            Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState())) {
                if (available.isEmpty()) {
                    Text("Every work you have is already in this queue.")
                }
                available.forEach { work ->
                    Text(
                        text = work.title,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                scope.launch {
                                    repository.addWork(queueId, work.id)
                                    onAdded()
                                }
                            }
                            .padding(vertical = 10.dp),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } }
    )
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
