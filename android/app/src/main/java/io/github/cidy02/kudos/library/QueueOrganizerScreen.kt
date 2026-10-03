package io.github.cidy02.kudos.library

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class QueueRowModel(
    val queue: ReadingQueue,
    val works: List<SavedWork>,
    val tags: List<String>,
    val preservedCount: Int,
    val bytes: Long
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QueueOrganizerScreen(
    repository: ReadingQueueRepository,
    epubBytes: (String) -> Long,
    onOpenQueue: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<QueueRowModel>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    var search by remember { mutableStateOf("") }
    var tagFilter by remember { mutableStateOf("") }
    var selecting by remember { mutableStateOf(false) }
    var reordering by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var menu by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<ReadingQueue?>(null) }
    var tagging by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }

    LaunchedEffect(reload) {
        rows = runCatching { loadOrganizer(repository, epubBytes) }.getOrDefault(emptyList())
        loaded = true
    }

    val narrowed = search.isNotBlank() || tagFilter.isNotEmpty()
    val visible = rows.filter { row ->
        ReadingQueueFacts.matchesSearch(row.queue, row.tags, row.works, search) &&
            ReadingQueueFacts.matchesTagFilter(row.tags, tagFilter)
    }
    val ordered = orderRows(visible)
    val pinned = ordered.filter { it.queue.isPinned }
    val usedTags = rows.flatMap { it.tags }.distinct().sortedBy { it.lowercase() }
    val customCount = rows.count { it.queue.kindRaw == ReadingQueueKind.CUSTOM }
    val chosen = rows.map { it.queue }.filter { it.id in selected }
    val palette = tokens.scopePalette

    BackHandler(enabled = selecting || reordering) {
        selecting = false
        reordering = false
        selected = emptySet()
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = selecting,
        onBack = if (selecting || reordering) {
            {
                selecting = false
                reordering = false
                selected = emptySet()
            }
        } else null,
        trailingContent = {
            OrganizerToolbarActions(
                palette = palette,
                selecting = selecting,
                selectedCount = selected.size,
                canPin = chosen.isNotEmpty(),
                pinLabel = if (ReadingQueueFacts.pinTarget(chosen)) "Pin" else "Unpin",
                canDelete = ReadingQueueFacts.deletable(chosen).isNotEmpty(),
                onNew = { creating = true },
                onMenu = { menu = true },
                menuOpen = menu,
                onDismissMenu = { menu = false },
                canReorder = ReadingQueueFacts.canReorder(tagFilter.isNotEmpty(), search.isNotBlank()) && customCount > 1,
                onSelect = { selecting = true; reordering = false },
                onReorder = { reordering = true; selecting = false; selected = emptySet() },
                onPin = {
                    val pin = ReadingQueueFacts.pinTarget(chosen)
                    scope.launch {
                        repository.setQueuesPinned(chosen.map { it.id }, pin)
                        reload += 1
                    }
                },
                onTag = { tagging = true },
                onDelete = { pendingDelete = ReadingQueueFacts.deletable(chosen) },
                onDone = { selecting = false; selected = emptySet() }
            )
        }
    )

    Column(modifier.fillMaxSize().subjectScreenWash(palette).verticalScroll(rememberScrollState())) {
        Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
        SubjectHeaderBlock(
            kicker = "Home",
            title = if (selecting) "${selected.size} selected" else "Queues",
            palette = palette,
            modifier = Modifier.padding(top = 8.dp),
            gutter = SubjectMetrics.accountGutter
        )
        if (!selecting && !reordering) {
            OutlinedTextField(
                value = search,
                onValueChange = { search = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                placeholder = { Text("Search queues, tags and works") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true
            )
        }
        SubjectStatStrip(
            cells = listOf(
                SubjectStatCell(rows.size.toString(), "Queues"),
                SubjectStatCell(rows.sumOf { it.works.size }.toString(), "Works"),
                SubjectStatCell(rows.sumOf { it.preservedCount }.toString(), "Offline"),
                SubjectStatCell(ReadingQueueFacts.byteCountString(rows.sumOf { it.bytes }), "Storage")
            ),
            palette = palette,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        if (!reordering) {
            Row(
                Modifier
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                FilterChip("All ${rows.size}", tagFilter.isEmpty(), palette) { tagFilter = "" }
                usedTags.forEach { tag ->
                    val count = rows.count { tag in it.tags }
                    FilterChip("$tag $count", tagFilter == tag, palette) { tagFilter = tag }
                }
                val untagged = rows.count { it.tags.isEmpty() }
                if (untagged > 0 || tagFilter == ReadingQueueFacts.UNTAGGED) {
                    FilterChip("Untagged $untagged", tagFilter == ReadingQueueFacts.UNTAGGED, palette) {
                        tagFilter = ReadingQueueFacts.UNTAGGED
                    }
                }
            }
        }
        if (loaded && ordered.isEmpty()) {
            Column(Modifier.padding(horizontal = 24.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("No matching queues", color = tokens.primaryInk, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    "Your search and tag filter don't match any queues.",
                    color = tokens.secondaryInk,
                    fontSize = 15.sp
                )
                TextButton(onClick = { search = ""; tagFilter = "" }) { Text("Clear Search and Filters") }
            }
        } else {
            if (pinned.isNotEmpty() && !reordering) {
                SectionRuleHeader("Pinned", count = pinned.size, modifier = Modifier.padding(top = 8.dp))
                pinned.forEach { row ->
                    OrganizerRow(
                        row = row,
                        selecting = selecting,
                        selected = row.queue.id in selected,
                        reordering = false,
                        onOpen = { onOpenQueue(row.queue.id) },
                        onToggle = { selected = toggle(selected, row.queue.id) },
                        onEdit = { editing = row.queue },
                        onPin = {
                            scope.launch {
                                repository.setQueuesPinned(listOf(row.queue.id), !row.queue.isPinned)
                                reload += 1
                            }
                        },
                        onDelete = { pendingDelete = listOf(row.queue) },
                        onStep = { }
                    )
                }
            }
            SectionRuleHeader("All queues", count = ordered.size, modifier = Modifier.padding(top = 8.dp))
            ordered.forEach { row ->
                OrganizerRow(
                    row = row,
                    selecting = selecting,
                    selected = row.queue.id in selected,
                    reordering = reordering && row.queue.kindRaw == ReadingQueueKind.CUSTOM,
                    onOpen = { onOpenQueue(row.queue.id) },
                    onToggle = { selected = toggle(selected, row.queue.id) },
                    onEdit = { editing = row.queue },
                    onPin = {
                        scope.launch {
                            repository.setQueuesPinned(listOf(row.queue.id), !row.queue.isPinned)
                            reload += 1
                        }
                    },
                    onDelete = { pendingDelete = listOf(row.queue) },
                    onStep = { delta ->
                        scope.launch {
                            stepCustom(repository, rows, row.queue.id, delta)
                            reload += 1
                        }
                    }
                )
            }
        }
    }

    if (creating || editing != null) {
        QueueEditorSheet(
            repository = repository,
            existing = editing,
            onDismiss = { creating = false; editing = null },
            onSaved = {
                creating = false
                editing = null
                reload += 1
            }
        )
    }
    if (tagging) {
        QueueTagSheet(
            repository = repository,
            queues = chosen,
            palette = palette,
            onDismiss = { tagging = false; reload += 1 }
        )
    }
    if (pendingDelete.isNotEmpty()) {
        val doomed = pendingDelete
        AlertDialog(
            onDismissRequest = { pendingDelete = emptyList() },
            title = { Text(ReadingQueueFacts.deleteTitle(doomed)) },
            text = { Text(ReadingQueueFacts.deleteMessage(doomed.size)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = emptyList()
                    scope.launch {
                        doomed.forEach { repository.deleteQueue(it.id) }
                        selected = selected - doomed.map { it.id }.toSet()
                        reload += 1
                    }
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = emptyList() }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun OrganizerToolbarActions(
    palette: SubjectPalette,
    selecting: Boolean,
    selectedCount: Int,
    canPin: Boolean,
    pinLabel: String,
    canDelete: Boolean,
    onNew: () -> Unit,
    onMenu: () -> Unit,
    menuOpen: Boolean,
    onDismissMenu: () -> Unit,
    canReorder: Boolean,
    onSelect: () -> Unit,
    onReorder: () -> Unit,
    onPin: () -> Unit,
    onTag: () -> Unit,
    onDelete: () -> Unit,
    onDone: () -> Unit
) {
    if (selecting) {
        TextButton(onClick = onPin, enabled = canPin) { Text(pinLabel, color = palette.accent) }
        TextButton(onClick = onTag, enabled = selectedCount > 0) { Text("Tag", color = palette.accent) }
        TextButton(onClick = onDelete, enabled = canDelete) { Text("Delete") }
        TextButton(onClick = onDone) { Text("Done", color = palette.accent) }
    } else {
        ToolbarCircleButton(
            onClick = onNew,
            accessibilityName = "New Queue"
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = palette.accent)
        }
        Box {
            ToolbarCircleButton(
                onClick = onMenu,
                accessibilityName = "More"
            ) {
                Icon(Icons.Filled.MoreHoriz, contentDescription = null)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = onDismissMenu) {
                DropdownMenuItem(text = { Text("Select") }, onClick = { onDismissMenu(); onSelect() })
                DropdownMenuItem(
                    text = { Text(if (canReorder) "Reorder" else "Clear Filters to Reorder") },
                    onClick = { onDismissMenu(); if (canReorder) onReorder() },
                    enabled = canReorder
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OrganizerRow(
    row: QueueRowModel,
    selecting: Boolean,
    selected: Boolean,
    reordering: Boolean,
    onOpen: () -> Unit,
    onToggle: () -> Unit,
    onEdit: () -> Unit,
    onPin: () -> Unit,
    onDelete: () -> Unit,
    onStep: (Int) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val custom = row.queue.kindRaw == ReadingQueueKind.CUSTOM
    val palette = if (custom) queuePalette(tokens.theme, row.queue) else tokens.scopePalette
    val body: @Composable () -> Unit = {
        QueueOrganizerCard(custom = custom, palette = palette) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                QueuePeekTile(row.works)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        if (custom) {
                            androidx.compose.foundation.Canvas(Modifier.size(10.dp)) {
                                drawCircle(palette.accent)
                            }
                        }
                        Text(
                            text = row.queue.displayName,
                            color = tokens.primaryInk,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false)
                        )
                        Text(
                            text = row.works.size.toString(),
                            color = tokens.secondaryInk,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                    if (row.works.isNotEmpty()) {
                        QueueProgressStrip(ReadingQueueFacts.progress(row.works), palette)
                    }
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        row.tags.forEach { QueueRowTagLabel(it) }
                        Text(
                            text = ReadingQueueFacts.storageLine(row.preservedCount, row.bytes),
                            color = tokens.secondaryInk,
                            fontSize = 12.sp
                        )
                    }
                }
                if (selecting) {
                    SelectionBubble(selected, Modifier.clickable(onClick = onToggle))
                }
                if (reordering) {
                    DragGrip(Modifier.queueDragHandle(true, onStep))
                }
            }
        }
    }
    if (selecting) {
        Column(Modifier.clickable(onClick = onToggle)) { body() }
    } else if (reordering) {
        body()
    } else {
        QueueSwipeRow(enabled = custom, onEdit = onEdit, onDelete = onDelete) {
            QueueCardPress(
                queue = row.queue,
                enabled = true,
                onClick = onOpen,
                onEdit = onEdit,
                onPin = onPin,
                onDelete = onDelete
            ) { body() }
        }
    }
}

@Composable
private fun QueueOrganizerCard(
    custom: Boolean,
    palette: SubjectPalette,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(16.dp)
    val border = if (custom) palette.rowBorder else tokens.separator
    Column(
        Modifier
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(tokens.theme.cardSurface)
            .then(if (custom) Modifier.background(palette.rowWash) else Modifier)
            .border(0.5.dp, border, shape)
            .padding(horizontal = 12.dp, vertical = 11.dp)
    ) { content() }
}

@Composable
private fun FilterChip(text: String, selected: Boolean, palette: SubjectPalette, onClick: () -> Unit) {
    SubjectChip(
        text = text,
        style = SubjectChipStyle.Pill(selected),
        palette = palette,
        modifier = Modifier.clickable(onClick = onClick)
    )
}

private fun toggle(selected: Set<String>, id: String): Set<String> {
    return if (id in selected) selected - id else selected + id
}

private fun orderRows(rows: List<QueueRowModel>): List<QueueRowModel> {
    val saved = rows.filter { it.queue.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
    val custom = rows.filter { it.queue.kindRaw == ReadingQueueKind.CUSTOM }.sortedBy { it.queue.sortOrder }
    return saved + custom
}

private suspend fun stepCustom(
    repository: ReadingQueueRepository,
    rows: List<QueueRowModel>,
    id: String,
    delta: Int
) {
    val ids = rows
        .filter { it.queue.kindRaw == ReadingQueueKind.CUSTOM }
        .sortedBy { it.queue.sortOrder }
        .map { it.queue.id }
        .toMutableList()
    val index = ids.indexOf(id)
    val target = index + delta
    if (index < 0 || target !in ids.indices) return
    val moved = ids.removeAt(index)
    ids.add(target, moved)
    repository.reorderQueues(ids)
}

private suspend fun loadOrganizer(
    repository: ReadingQueueRepository,
    epubBytes: (String) -> Long
): List<QueueRowModel> {
    repository.ensureSavedForLaterQueue()
    val tags = repository.tagsByQueue()
    return repository.listQueues().filter { !it.isDeleted }.map { queue ->
        val works = repository.listWorks(queue.id).mapNotNull { it.work }
        val sizes = withContext(Dispatchers.IO) {
            works.associate { work -> work.id to runCatching { epubBytes(work.id) }.getOrDefault(0L) }
        }
        val preserved = works.filter { it.hasEpub && (sizes[it.id] ?: 0L) > 0 }
        QueueRowModel(
            queue = queue,
            works = works,
            tags = tags[queue.id].orEmpty().map { it.name },
            preservedCount = preserved.size,
            bytes = preserved.sumOf { sizes[it.id] ?: 0L }
        )
    }
}
