package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverHue
import kotlinx.coroutines.launch

/**
 * Reading-queue browser (Apple `ReadingQueueBrowserView`).
 *
 * - [initialQueueId] null → full grid of queue stack tiles (See all), then open a queue.
 * - non-null → Safari-style switcher + active-queue work grid for that queue.
 * Overflow opens advanced list management ([QueueDetailScreen]) for filters/reorder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingQueueBrowserScreen(
    repository: ReadingQueueRepository,
    initialQueueId: String? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit = onOpenWork,
    onManageQueue: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    // See-all lands with null and must show the stack grid first — not auto-select
    // Saved for Later. Shelf tile taps pass a concrete id and skip the grid.
    var selectedQueueId by rememberSaveable {
        mutableStateOf(initialQueueId)
    }
    val showingAllQueuesGrid = selectedQueueId == null && initialQueueId == null

    if (showingAllQueuesGrid) {
        AllReadingQueuesGridScreen(
            repository = repository,
            onOpenQueue = { id ->
                selectedQueueId = id
                ReadingQueueBrowserMemory.lastSelectedId = id
            },
            onNewQueueCreated = { id ->
                selectedQueueId = id
                ReadingQueueBrowserMemory.lastSelectedId = id
            }
        )
        return
    }

    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var queues by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }
    var workCounts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var works by remember { mutableStateOf<List<SavedWork>>(emptyList()) }

    // Once a queue is chosen (from grid or deep link), keep selection across config.
    var showSwitcher by remember { mutableStateOf(false) }
    var showNewQueue by remember { mutableStateOf(false) }
    var newQueueName by remember { mutableStateOf("") }

    val orderedQueues = remember(queues) { orderQueues(queues) }
    val selectedQueue = remember(orderedQueues, selectedQueueId) {
        orderedQueues.firstOrNull { it.id == selectedQueueId } ?: orderedQueues.firstOrNull()
    }

    suspend fun refreshQueues() {
        repository.ensureSavedForLaterQueue()
        val listed = repository.listQueues()
        queues = listed
        workCounts = listed.associate { queue ->
            queue.id to repository.listWorks(queue.id).size
        }
    }

    suspend fun refreshWorks(queueId: String?) {
        if (queueId == null) {
            works = emptyList()
            return
        }
        val items = repository.listWorks(queueId)
        works = items.mapNotNull { it.work }
    }

    suspend fun refreshAll() {
        loading = true
        error = null
        try {
            refreshQueues()
            val ordered = orderQueues(queues)
            val resolvedId = resolveSelection(
                initialQueueId = initialQueueId,
                currentSelectedId = selectedQueueId,
                ordered = ordered
            )
            if (resolvedId != selectedQueueId) {
                selectedQueueId = resolvedId
            }
            if (resolvedId != null) {
                ReadingQueueBrowserMemory.lastSelectedId = resolvedId
            }
            refreshWorks(resolvedId)
        } catch (e: Exception) {
            error = e.message ?: "Could not load reading queues."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(initialQueueId) {
        refreshAll()
    }

    // Re-load after returning from Manage Queue (QueueDetail) without re-forcing the
    // deep-link selection — only refresh lists for the queue the user is already on.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        var seenResume = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (!seenResume) {
                    seenResume = true
                    return@LifecycleEventObserver
                }
                scope.launch {
                    try {
                        refreshQueues()
                        refreshWorks(selectedQueueId)
                    } catch (_: Exception) {
                        // Keep showing the last good snapshot; next explicit action will surface errors.
                    }
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    fun selectQueue(queueId: String) {
        selectedQueueId = queueId
        ReadingQueueBrowserMemory.lastSelectedId = queueId
        showSwitcher = false
        scope.launch {
            try {
                refreshWorks(queueId)
            } catch (e: Exception) {
                error = e.message ?: "Could not load queue works."
            }
        }
    }

    fun createQueue() {
        val trimmed = newQueueName.trim()
        newQueueName = ""
        showNewQueue = false
        if (trimmed.isEmpty()) return
        scope.launch {
            try {
                val created = repository.createQueue(trimmed)
                refreshQueues()
                selectQueue(created.id)
            } catch (e: Exception) {
                error = e.message ?: "Could not create queue."
            }
        }
    }

    if (showNewQueue) {
        AlertDialog(
            onDismissRequest = {
                showNewQueue = false
                newQueueName = ""
            },
            title = { Text("New Queue") },
            text = {
                OutlinedTextField(
                    value = newQueueName,
                    onValueChange = { newQueueName = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = newQueueName.trim().isNotEmpty(),
                    onClick = { createQueue() }
                ) { Text("Add") }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showNewQueue = false
                        newQueueName = ""
                    }
                ) { Text("Cancel") }
            }
        )
    }

    if (showSwitcher) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showSwitcher = false },
            sheetState = sheetState
        ) {
            QueueSwitcherList(
                queues = orderedQueues,
                workCounts = workCounts,
                selectedQueueId = selectedQueue?.id,
                onSelect = { selectQueue(it.id) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 28.dp)
            )
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val useSidebar = maxWidth >= 840.dp
        if (useSidebar) {
            ExpandedBrowserLayout(
                queues = orderedQueues,
                workCounts = workCounts,
                selectedQueue = selectedQueue,
                works = works,
                loading = loading,
                error = error,
                onSelectQueue = { selectQueue(it.id) },
                onNewQueue = {
                    newQueueName = ""
                    showNewQueue = true
                },
                onManageQueue = {
                    selectedQueue?.id?.let(onManageQueue)
                },
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        } else {
            CompactBrowserLayout(
                selectedQueue = selectedQueue,
                works = works,
                loading = loading,
                error = error,
                onOpenSwitcher = { showSwitcher = true },
                onNewQueue = {
                    newQueueName = ""
                    showNewQueue = true
                },
                onManageQueue = {
                    selectedQueue?.id?.let(onManageQueue)
                },
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
    }
}

@Composable
private fun CompactBrowserLayout(
    selectedQueue: ReadingQueue?,
    works: List<SavedWork>,
    loading: Boolean,
    error: String?,
    onOpenSwitcher: () -> Unit,
    onNewQueue: () -> Unit,
    onManageQueue: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    Scaffold(
        bottomBar = {
            QueueSwitcherBar(
                selectedQueue = selectedQueue,
                onOpenSwitcher = onOpenSwitcher,
                onNewQueue = onNewQueue
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            BrowserManageHeader(
                queueName = selectedQueue?.displayName,
                onManageQueue = onManageQueue,
                enabled = selectedQueue != null
            )
            BrowserPageContent(
                selectedQueue = selectedQueue,
                works = works,
                loading = loading,
                error = error,
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ExpandedBrowserLayout(
    queues: List<ReadingQueue>,
    workCounts: Map<String, Int>,
    selectedQueue: ReadingQueue?,
    works: List<SavedWork>,
    loading: Boolean,
    error: String?,
    onSelectQueue: (ReadingQueue) -> Unit,
    onNewQueue: () -> Unit,
    onManageQueue: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    Row(modifier = Modifier.fillMaxSize()) {
        Surface(
            modifier = Modifier
                .width(240.dp)
                .fillMaxHeight(),
            color = MaterialTheme.colorScheme.surfaceContainerLow
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                QueueSwitcherList(
                    queues = queues,
                    workCounts = workCounts,
                    selectedQueueId = selectedQueue?.id,
                    onSelect = onSelectQueue,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                )
                HorizontalDivider()
                TextButton(
                    onClick = onNewQueue,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("New Queue")
                }
            }
        }
        VerticalDivider(modifier = Modifier.fillMaxHeight())
        Column(modifier = Modifier.weight(1f)) {
            BrowserManageHeader(
                queueName = selectedQueue?.displayName,
                onManageQueue = onManageQueue,
                enabled = selectedQueue != null,
                emphasizeTitle = true
            )
            BrowserPageContent(
                selectedQueue = selectedQueue,
                works = works,
                loading = loading,
                error = error,
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun BrowserManageHeader(
    queueName: String?,
    onManageQueue: () -> Unit,
    enabled: Boolean,
    emphasizeTitle: Boolean = false
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (emphasizeTitle) {
            Text(
                text = queueName ?: "Reading Queues",
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp)
            )
        } else {
            Spacer(Modifier.weight(1f))
        }
        IconButton(onClick = onManageQueue, enabled = enabled) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = "List filters and reorder"
            )
        }
    }
}

@Composable
private fun BrowserPageContent(
    selectedQueue: ReadingQueue?,
    works: List<SavedWork>,
    loading: Boolean,
    error: String?,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    when {
        loading && works.isEmpty() -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LoadingStateCard("Loading queue")
            }
        }
        error != null && selectedQueue == null -> {
            Box(modifier = modifier.fillMaxSize().padding(20.dp)) {
                ErrorStateCard(title = "Queues unavailable", message = error)
            }
        }
        selectedQueue != null && works.isEmpty() && !loading -> {
            Box(modifier = modifier.fillMaxSize().padding(20.dp)) {
                EmptyStateCard(
                    title = selectedQueue.displayName,
                    message = "Works you add to this queue will keep a local EPUB for offline reading."
                )
            }
        }
        else -> {
            val cardActions = remember(onOpenWork, onOpenReader) {
                LibraryCardActions(
                    onOpenWork = onOpenWork,
                    onOpenReader = onOpenReader,
                    onToggleFavorite = {},
                    onToggleFinished = {},
                    onRemove = {},
                    onSetSaved = { _, _ -> },
                    onSelect = {},
                    onReveal = {},
                    onAddToQueue = {},
                    onAddToCollection = {},
                    onOpenComments = {}
                )
            }
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = WorkCoverCardMetrics.width),
                horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.compactGridSpacing),
                verticalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.compactGridSpacing),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                modifier = modifier.fillMaxSize()
            ) {
                items(works, key = { it.id }) { work ->
                    LibraryCarouselCard(
                        display = LibraryDisplayItem(
                            item = LibraryWorkListItem(work = work)
                        ),
                        showProgress = true,
                        footerOverride = null,
                        actions = cardActions
                    )
                }
            }
        }
    }
}

@Composable
private fun QueueSwitcherBar(
    selectedQueue: ReadingQueue?,
    onOpenSwitcher: () -> Unit,
    onNewQueue: () -> Unit
) {
    Surface(
        tonalElevation = 3.dp,
        shadowElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onOpenSwitcher) {
                Icon(
                    imageVector = Icons.Outlined.GridView,
                    contentDescription = "All Queues"
                )
            }

            Surface(
                onClick = onOpenSwitcher,
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                modifier = Modifier.weight(1f)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    QueueGlyph(selectedQueue)
                    Text(
                        text = selectedQueue?.displayName ?: "Reading Queues",
                        style = MaterialTheme.typography.labelLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowUp,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            IconButton(onClick = onNewQueue) {
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = "New Queue"
                )
            }
        }
    }
}

@Composable
private fun QueueSwitcherList(
    queues: List<ReadingQueue>,
    workCounts: Map<String, Int>,
    selectedQueueId: String?,
    onSelect: (ReadingQueue) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(modifier = modifier) {
        items(queues, key = { it.id }) { queue ->
            QueueSwitcherRow(
                queue = queue,
                workCount = workCounts[queue.id] ?: 0,
                selected = queue.id == selectedQueueId,
                onClick = { onSelect(queue) }
            )
        }
    }
}

@Composable
private fun QueueSwitcherRow(
    queue: ReadingQueue,
    workCount: Int,
    selected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        QueueGlyph(queue)
        Text(
            text = queue.displayName,
            style = MaterialTheme.typography.bodyLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = workCount.toString(),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (selected) {
            Icon(
                imageVector = Icons.Default.Check,
                contentDescription = "Selected",
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
        } else {
            Spacer(Modifier.size(20.dp))
        }
    }
}

@Composable
private fun QueueGlyph(queue: ReadingQueue?) {
    if (queue != null && queue.kindRaw != ReadingQueueKind.SAVED_FOR_LATER) {
        val hue = coverHue(queue.displayName)
        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(CircleShape)
                .background(Color.hsl(hue = hue, saturation = 0.55f, lightness = 0.55f))
        )
    } else {
        Icon(
            imageVector = Icons.Outlined.Schedule,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Full grid of reading-queue tiles behind the Library "See all" chevron —
 * iOS `AllReadingQueuesGridView`. Tapping a tile opens that queue in the browser.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AllReadingQueuesGridScreen(
    repository: ReadingQueueRepository,
    onOpenQueue: (String) -> Unit,
    onNewQueueCreated: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var queues by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }
    var workCounts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var showNewQueue by remember { mutableStateOf(false) }
    var newQueueName by remember { mutableStateOf("") }

    suspend fun refresh() {
        loading = true
        error = null
        try {
            repository.ensureSavedForLaterQueue()
            val listed = repository.listQueues()
            queues = orderQueues(listed)
            workCounts = listed.associate { queue ->
                queue.id to repository.listWorks(queue.id).size
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load reading queues."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { refresh() }

    if (showNewQueue) {
        AlertDialog(
            onDismissRequest = {
                showNewQueue = false
                newQueueName = ""
            },
            title = { Text("New Queue") },
            text = {
                OutlinedTextField(
                    value = newQueueName,
                    onValueChange = { newQueueName = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = newQueueName.trim().isNotEmpty(),
                    onClick = {
                        val trimmed = newQueueName.trim()
                        showNewQueue = false
                        newQueueName = ""
                        if (trimmed.isEmpty()) return@TextButton
                        scope.launch {
                            try {
                                val created = repository.createQueue(trimmed)
                                onNewQueueCreated(created.id)
                            } catch (e: Exception) {
                                error = e.message ?: "Could not create queue."
                            }
                        }
                    }
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showNewQueue = false
                    newQueueName = ""
                }) { Text("Cancel") }
            }
        )
    }

    when {
        loading && queues.isEmpty() -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LoadingStateCard("Loading queues")
            }
        }
        error != null && queues.isEmpty() -> {
            val message = error ?: "Could not load reading queues."
            Box(Modifier.fillMaxSize().padding(20.dp)) {
                ErrorStateCard(title = "Queues unavailable", message = message)
            }
        }
        else -> {
            val customQueues = queues.filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = WorkCoverCardMetrics.width),
                horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.compactGridSpacing),
                verticalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.compactGridSpacing),
                contentPadding = PaddingValues(16.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                item(key = "new-queue") {
                    QueueGridNewTile(onClick = {
                        newQueueName = ""
                        showNewQueue = true
                    })
                }
                items(customQueues, key = { it.id }) { queue ->
                    QueueGridTile(
                        title = queue.displayName,
                        workCount = workCounts[queue.id] ?: 0,
                        onClick = { onOpenQueue(queue.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun QueueGridNewTile(onClick: () -> Unit) {
    Column(
        modifier = Modifier.width(WorkCoverCardMetrics.width),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Surface(
            onClick = onClick,
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surface,
            border = androidx.compose.foundation.BorderStroke(
                1.5.dp,
                MaterialTheme.colorScheme.outlineVariant
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(WorkCoverCardMetrics.height - 48.dp)
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Default.Add,
                    contentDescription = "New Queue",
                    modifier = Modifier.size(34.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text("New Queue", style = MaterialTheme.typography.titleSmall, maxLines = 2)
        Text(
            "Tap to create",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun QueueGridTile(
    title: String,
    workCount: Int,
    onClick: () -> Unit
) {
    val hue = coverHue(title)
    Column(
        modifier = Modifier
            .width(WorkCoverCardMetrics.width)
            .clickable(onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier
                .fillMaxWidth()
                .height(WorkCoverCardMetrics.height - 48.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.hsl(hue, 0.35f, 0.55f, alpha = 0.22f))
                    .padding(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .size(28.dp)
                )
            }
        }
        Text(title, style = MaterialTheme.typography.titleSmall, maxLines = 2)
        Text(
            text = when (workCount) {
                0 -> "Empty"
                1 -> "1 work"
                else -> "$workCount works"
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/** Saved for Later first, then customs by sortOrder — matches iOS / Add-to-Queue order. */
private fun orderQueues(queues: List<ReadingQueue>): List<ReadingQueue> {
    return queues.sortedWith(
        compareBy<ReadingQueue> { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
            .thenBy { it.sortOrder }
            .thenBy { it.displayName.lowercase() }
    )
}

/**
 * Prefers a deep-linked [initialQueueId], then the in-memory last selection if still
 * present, otherwise the first ordered queue (Saved for Later).
 */
private fun resolveSelection(
    initialQueueId: String?,
    currentSelectedId: String?,
    ordered: List<ReadingQueue>
): String? {
    if (initialQueueId != null && ordered.any { it.id == initialQueueId }) {
        return initialQueueId
    }
    if (currentSelectedId != null && ordered.any { it.id == currentSelectedId }) {
        return currentSelectedId
    }
    val remembered = ReadingQueueBrowserMemory.lastSelectedId
    if (remembered != null && ordered.any { it.id == remembered }) {
        return remembered
    }
    return ordered.firstOrNull()?.id
}

/** Process-lifetime last-selected queue for the browser (not persisted to disk). */
private object ReadingQueueBrowserMemory {
    var lastSelectedId: String? = null
}
