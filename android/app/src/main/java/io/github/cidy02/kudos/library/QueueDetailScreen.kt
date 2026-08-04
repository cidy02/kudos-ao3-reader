package io.github.cidy02.kudos.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowDropUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QueueDetailScreen(
    queueId: String,
    repository: ReadingQueueRepository,
    onOpenWork: (String) -> Unit
) {
    var loading by remember(queueId) { mutableStateOf(true) }
    var working by remember(queueId) { mutableStateOf(false) }
    var error by remember(queueId) { mutableStateOf<String?>(null) }
    var queue by remember(queueId) { mutableStateOf<ReadingQueue?>(null) }
    var items by remember(queueId) { mutableStateOf<List<QueueMembershipItem>>(emptyList()) }
    var filters by remember { mutableStateOf(LibraryFilterState()) }
    var sort by remember { mutableStateOf(LibrarySort.RecentlyAdded) }
    var showFilterPanel by remember { mutableStateOf(false) }
    var overflowExpanded by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var renameDraft by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var reorderMode by remember { mutableStateOf(false) }
    val userTags by repository.observeAllUserTags().collectAsState(initial = emptyList())
    val allCollections by repository.observeAllCollections().collectAsState(initial = emptyList())
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = true
        error = null
        try {
            queue = repository.getQueue(queueId)
            items = if (queue != null) repository.listWorks(queueId) else emptyList()
            if (queue == null) {
                error = "This reading queue no longer exists."
            } else {
                renameDraft = queue!!.name
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load queue."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(queueId) { refresh() }

    val filteredItems = remember(items, filters, sort) {
        val displayItems = items.map { LibraryDisplayItem(LibraryWorkListItem(it.work!!)) }
        val results = LibraryQuery.apply(displayItems, "", filters, sort)
        results.mapNotNull { display ->
            items.find { it.membership.workID == display.item.work.id }
        }
    }

    fun onReorder(fromIndex: Int, toIndex: Int) {
        val list = filteredItems.toMutableList()
        val item = list.removeAt(fromIndex)
        list.add(toIndex, item)
        items = list // Optimistic update
        scope.launch {
            repository.updateSortOrder(queueId, list.map { it.membership.workID })
        }
    }

    fun removeWork(workId: String) {
        scope.launch {
            working = true
            error = null
            try {
                repository.removeWork(queueId, workId)
                items = repository.listWorks(queueId)
            } catch (e: Exception) {
                error = e.message ?: "Could not remove work."
            } finally {
                working = false
            }
        }
    }

    fun renameQueue() {
        val name = renameDraft.trim()
        if (name.isEmpty()) return
        scope.launch {
            working = true
            error = null
            try {
                repository.renameQueue(queueId, name)
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not rename queue."
            } finally {
                working = false
            }
        }
    }

    fun deleteQueue() {
        scope.launch {
            working = true
            error = null
            try {
                repository.deleteQueue(queueId)
                // Navigation should pop back, but for now we'll just refresh and let caller handle.
                queue = null
                items = emptyList()
            } catch (e: Exception) {
                error = e.message ?: "Could not delete queue."
            } finally {
                working = false
            }
        }
    }

    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text("Rename Queue") },
            text = {
                OutlinedTextField(
                    value = renameDraft,
                    onValueChange = { renameDraft = it },
                    label = { Text("Queue name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = renameDraft.trim().isNotEmpty() && !working,
                    onClick = {
                        showRenameDialog = false
                        renameQueue()
                    }
                ) { Text("Rename") }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) { Text("Cancel") }
            }
        )
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete Queue?") },
            text = {
                Text("This queue will be moved to Recently Deleted. Its works will remain in your Library.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        deleteQueue()
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
            }
        )
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // TopAppBar is generic ("Queue"); show queue name + count as context.
                KudosScreenHeader(
                    title = queue?.displayName?.takeIf { it.isNotBlank() && it != "Queue" },
                    subtitle = when {
                        loading -> "Loading…"
                        items.isEmpty() -> "No works in this queue."
                        items.size == 1 -> "1 work"
                        else -> "${items.size} works"
                    },
                    modifier = Modifier.weight(1f)
                )

                if (queue != null && queue!!.kindRaw != io.github.cidy02.kudos.core.model.ReadingQueueKind.SAVED_FOR_LATER) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (!reorderMode) {
                            IconButton(onClick = { showFilterPanel = true }) {
                                Icon(
                                    imageVector = Icons.Default.Sort,
                                    contentDescription = "Filter and Sort",
                                    tint = if (filters.hasActiveFilters) {
                                        MaterialTheme.colorScheme.primary
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            }
                        }
                        Box {
                            IconButton(onClick = { overflowExpanded = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "Queue actions")
                            }
                            DropdownMenu(
                                expanded = overflowExpanded,
                                onDismissRequest = { overflowExpanded = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text(if (reorderMode) "Exit Reordering" else "Reorder Works") },
                                    onClick = {
                                        overflowExpanded = false
                                        reorderMode = !reorderMode
                                        if (reorderMode) sort = LibrarySort.Manual
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Rename") },
                                    onClick = {
                                        overflowExpanded = false
                                        showRenameDialog = true
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                                    onClick = {
                                        overflowExpanded = false
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        when {
            loading -> item { LoadingStateCard("Loading queue") }
            error != null && queue == null -> item {
                ErrorStateCard(
                    title = "Queue unavailable",
                    message = error.orEmpty()
                )
            }
            else -> {
                error?.let { message ->
                    item {
                        ErrorStateCard(
                            title = "Queue action failed",
                            message = message
                        )
                    }
                }
                if (items.isEmpty()) {
                    item {
                        EmptyStateCard(
                            title = "Nothing queued",
                            message = "Add works from Work Detail with Add to Saved for Later."
                        )
                    }
                } else if (filteredItems.isEmpty()) {
                    item {
                        EmptyStateCard(
                            title = "No matches",
                            message = "No works in this queue match your filters.",
                            primaryActionLabel = "Clear filters",
                            onPrimaryAction = { filters = LibraryFilterState() }
                        )
                    }
                } else {
                    itemsIndexed(filteredItems, key = { _, item -> item.membership.id }) { index, item ->
                        QueueWorkRow(
                            item = item,
                            enabled = !working,
                            reorderMode = reorderMode,
                            onOpenWork = {
                                item.work?.id?.let(onOpenWork)
                            },
                            onRemove = { removeWork(item.membership.workID) },
                            onMoveUp = if (index > 0) { { onReorder(index, index - 1) } } else null,
                            onMoveDown = if (index < filteredItems.lastIndex) { { onReorder(index, index + 1) } } else null
                        )
                    }
                }
            }
        }
    }

    if (showFilterPanel) {
        LibraryFilterPanel(
            filters = filters,
            sort = sort,
            userTags = userTags,
            collections = allCollections,
            onFiltersChange = { filters = it },
            onSortChange = { sort = it },
            onApply = { showFilterPanel = false },
            onClear = { filters = LibraryFilterState() },
            onDismiss = { showFilterPanel = false }
        )
    }
}

@Composable
private fun QueueWorkRow(
    item: QueueMembershipItem,
    enabled: Boolean,
    reorderMode: Boolean,
    onOpenWork: () -> Unit,
    onRemove: () -> Unit,
    onMoveUp: (() -> Unit)? = null,
    onMoveDown: (() -> Unit)? = null
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (reorderMode) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    IconButton(onClick = onMoveUp ?: {}, enabled = onMoveUp != null, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Default.ArrowDropUp, "Move Up")
                    }
                    IconButton(onClick = onMoveDown ?: {}, enabled = onMoveDown != null, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Default.ArrowDropDown, "Move Down")
                    }
                }
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .then(
                        if (item.work != null && !reorderMode) {
                            Modifier.clickable(enabled = enabled, onClick = onOpenWork)
                        } else {
                            Modifier
                        }
                    ),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (item.author.isNotBlank()) {
                    Text(
                        text = "by ${item.author}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            OutlinedButton(enabled = enabled, onClick = onRemove) {
                Text("Remove")
            }
        }
    }
}
