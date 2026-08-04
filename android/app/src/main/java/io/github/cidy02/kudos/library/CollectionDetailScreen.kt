package io.github.cidy02.kudos.library

import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CollectionDetailScreen(
    collectionId: String,
    workRepository: WorkRepository,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate(),
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onCollectionDeleted: () -> Unit
) {
    val privacy by (settingsRepository?.settings?.map { it.privacy }
        ?: kotlinx.coroutines.flow.flowOf(PrivacySettings()))
        .collectAsState(initial = PrivacySettings())
    val reveal by privacyGate.state.collectAsState()
    val confirmBeforeDelete by (settingsRepository?.settings?.map { it.app.confirmBeforeDelete }
        ?: kotlinx.coroutines.flow.flowOf(true))
        .collectAsState(initial = true)
    
    var loading by remember(collectionId) { mutableStateOf(true) }
    var working by remember(collectionId) { mutableStateOf(false) }
    var error by remember(collectionId) { mutableStateOf<String?>(null) }
    var collection by remember(collectionId) { mutableStateOf<WorkCollection?>(null) }
    var works by remember(collectionId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    var confirmDelete by remember(collectionId) { mutableStateOf(false) }
    var showRename by remember(collectionId) { mutableStateOf(false) }
    var renameText by remember(collectionId) { mutableStateOf("") }
    var pendingRemoveWork by remember(collectionId) { mutableStateOf<SavedWork?>(null) }
    var showAddPicker by remember(collectionId) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val activity = androidx.compose.ui.platform.LocalContext.current
        as? androidx.fragment.app.FragmentActivity

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

    fun addWorks(workIds: Set<String>) {
        scope.launch {
            working = true
            error = null
            try {
                workIds.forEach { workRepository.addWorkToCollection(it, collectionId) }
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
                confirmDelete = false
                onCollectionDeleted()
            } catch (e: Exception) {
                error = e.message ?: "Could not delete collection."
                working = false
            }
        }
    }

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

    if (confirmDelete) {
        val name = collection?.name.orEmpty()
        AlertDialog(
            onDismissRequest = { if (!working) confirmDelete = false },
            title = { Text(if (name.isBlank()) "Delete collection?" else "Delete “$name”?") },
            text = {
                Text(
                    "The collection moves to Recently Deleted for 90 days. Works stay in " +
                        "your Library."
                )
            },
            confirmButton = {
                TextButton(
                    enabled = !working,
                    onClick = { deleteCollection() }
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !working,
                    onClick = { confirmDelete = false }
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    pendingRemoveWork?.let { work ->
        AlertDialog(
            onDismissRequest = { if (!working) pendingRemoveWork = null },
            title = { Text("Remove “${work.title}”?") },
            text = { Text("This only removes it from this collection — the work stays in your Library.") },
            confirmButton = {
                TextButton(
                    enabled = !working,
                    onClick = {
                        pendingRemoveWork = null
                        removeWork(work.id)
                    }
                ) {
                    Text("Remove")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !working,
                    onClick = { pendingRemoveWork = null }
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            KudosScreenHeader(
                title = collection?.name ?: "Collection",
                subtitle = when {
                    loading -> "Loading…"
                    works.isEmpty() -> "No works in this collection."
                    works.size == 1 -> "1 work"
                    else -> "${works.size} works"
                },
                trailing = {
                    if (collection != null) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(
                                enabled = !working && !loading,
                                onClick = { showAddPicker = true }
                            ) {
                                Icon(Icons.Default.Add, contentDescription = null)
                                Spacer(Modifier.padding(end = 4.dp))
                                Text("Add Works")
                            }
                            OutlinedButton(
                                enabled = !working && !loading,
                                onClick = {
                                    renameText = collection?.name.orEmpty()
                                    showRename = true
                                }
                            ) {
                                Text("Rename")
                            }
                            OutlinedButton(
                                enabled = !working && !loading,
                                onClick = { confirmDelete = true }
                            ) {
                                Text("Delete")
                            }
                        }
                    }
                }
            )
        }

        when {
            loading -> item { LoadingStateCard("Loading collection") }
            error != null && collection == null -> item {
                ErrorStateCard(
                    title = "Collection unavailable",
                    message = error.orEmpty()
                )
            }
            else -> {
                error?.let { message ->
                    item {
                        ErrorStateCard(
                            title = "Collection action failed",
                            message = message
                        )
                    }
                }
                if (works.isEmpty()) {
                    item {
                        EmptyStateCard(
                            title = "Nothing here yet",
                            message = "Add works with the Add button above. " +
                                "You can delete this empty shelf with Delete.",
                            primaryActionLabel = "Add works",
                            onPrimaryAction = { showAddPicker = true }
                        )
                    }
                } else {
                    items(works, key = { it.id }) { work ->
                        val obscured = LibraryPrivacy.visibility(work, privacy) ==
                            LibraryPrivacyVisibility.Obscured && !reveal.isRevealed(work.id)
                        CollectionWorkRow(
                            work = work,
                            enabled = !working,
                            obscured = obscured,
                            onOpenWork = { onOpenWork(work.id) },
                            onOpenReader = {
                                if (work.hasEpub) onOpenReader(work.id)
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

    if (showAddPicker) {
        val allSavedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
        val currentWorkIds = works.map { it.id }.toSet()
        val availableToAdd = allSavedWorks.filter { it.id !in currentWorkIds }

        AddWorksToCollectionDialog(
            availableWorks = availableToAdd,
            onDismiss = { showAddPicker = false },
            onAdd = { selected ->
                showAddPicker = false
                addWorks(selected)
            }
        )
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun AddWorksToCollectionDialog(
    availableWorks: List<SavedWork>,
    onDismiss: () -> Unit,
    onAdd: (Set<String>) -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val selectedIds = remember { mutableStateMapOf<String, Boolean>() }
    val filteredWorks = remember(availableWorks, searchQuery) {
        if (searchQuery.isBlank()) availableWorks
        else availableWorks.filter { 
            it.title.contains(searchQuery, ignoreCase = true) || 
            it.author.contains(searchQuery, ignoreCase = true) 
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Add Works to Collection", style = MaterialTheme.typography.titleLarge)
            
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                label = { Text("Search your Library") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 400.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (filteredWorks.isEmpty()) {
                    item {
                        Text(
                            if (availableWorks.isEmpty()) "No other works in Library to add." 
                            else "No matches in Library.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 16.dp)
                        )
                    }
                } else {
                    items(filteredWorks, key = { it.id }) { work ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val current = selectedIds[work.id] ?: false
                                    selectedIds[work.id] = !current
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Checkbox(
                                checked = selectedIds[work.id] ?: false,
                                onCheckedChange = { selectedIds[work.id] = it }
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(work.title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(work.author, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Cancel")
                }
                Button(
                    onClick = { onAdd(selectedIds.filterValues { it }.keys) },
                    modifier = Modifier.weight(1f),
                    enabled = selectedIds.any { it.value }
                ) {
                    val count = selectedIds.count { it.value }
                    Text(if (count > 0) "Add $count work${if (count > 1) "s" else ""}" else "Add")
                }
            }
        }
    }
}

@Composable
private fun CollectionWorkRow(
    work: SavedWork,
    enabled: Boolean,
    obscured: Boolean,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit,
    onReveal: () -> Unit,
    onRemove: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        enabled = enabled,
                        onClick = if (obscured) onReveal else onOpenWork
                    ),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = if (obscured) "Hidden mature work" else work.title.ifBlank { "Untitled work" },
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (obscured) {
                    Text(
                        text = "Tap to reveal",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else if (work.author.isNotBlank()) {
                    Text(
                        text = "by ${work.author}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (work.hasEpub && !obscured) {
                    OutlinedButton(enabled = enabled, onClick = onOpenReader) {
                        Text("Read")
                    }
                }
                OutlinedButton(enabled = enabled, onClick = onRemove) {
                    Text("Remove")
                }
            }
        }
    }
}
