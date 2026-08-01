package io.github.cidy02.kudos.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/**
 * Local user-named shelves (WorkCollection). AO3 remote collections are out of scope.
 */
@Composable
fun CollectionsScreen(
    workRepository: WorkRepository,
    onOpenCollection: (String) -> Unit
) {
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var collections by remember { mutableStateOf<List<WorkCollection>>(emptyList()) }
    var showCreate by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = true
        error = null
        try {
            collections = workRepository.allCollections()
                .sortedWith(
                    compareByDescending<WorkCollection> { it.workIds.size }
                        .thenBy { it.name.lowercase() }
                )
        } catch (e: Exception) {
            error = e.message ?: "Could not load collections."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { refresh() }

    fun createCollection() {
        val name = newName.trim()
        if (name.isEmpty() || working) return
        scope.launch {
            working = true
            error = null
            try {
                val created = workRepository.createCollection(name)
                newName = ""
                showCreate = false
                collections = workRepository.allCollections()
                    .sortedWith(
                        compareByDescending<WorkCollection> { it.workIds.size }
                            .thenBy { it.name.lowercase() }
                    )
                // Open the new (or matched) shelf so create feels complete.
                onOpenCollection(created.id)
            } catch (e: Exception) {
                error = e.message ?: "Could not create collection."
            } finally {
                working = false
            }
        }
    }

    if (showCreate) {
        AlertDialog(
            onDismissRequest = {
                if (!working) {
                    showCreate = false
                    newName = ""
                }
            },
            title = { Text("New Collection") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "Name a shelf for grouping saved works. " +
                            "Add works later from Work Detail.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("Collection name") },
                        singleLine = true,
                        enabled = !working,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !working && newName.trim().isNotEmpty(),
                    onClick = { createCollection() }
                ) {
                    Text("Create")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !working,
                    onClick = {
                        showCreate = false
                        newName = ""
                    }
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
                title = "Collections",
                subtitle = "Local shelves for organizing your Library.",
                trailing = {
                    OutlinedButton(
                        enabled = !working && !loading,
                        onClick = { showCreate = true }
                    ) {
                        Text("New")
                    }
                }
            )
        }

        when {
            loading -> item { LoadingStateCard("Loading collections") }
            error != null && collections.isEmpty() -> item {
                ErrorStateCard(
                    title = "Collections could not load",
                    message = error.orEmpty()
                )
            }
            collections.isEmpty() -> item {
                EmptyStateCard(
                    title = "No collections yet",
                    message = "Create collections to organize your reading. " +
                        "You can also add a work to a new collection from Work Detail."
                )
            }
            else -> {
                error?.let { message ->
                    item {
                        ErrorStateCard(
                            title = "Collections action failed",
                            message = message
                        )
                    }
                }
                items(collections, key = { it.id }) { collection ->
                    CollectionRow(
                        collection = collection,
                        onClick = { onOpenCollection(collection.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionRow(
    collection: WorkCollection,
    onClick: () -> Unit
) {
    val count = collection.workIds.size
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = collection.name,
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = when (count) {
                        0 -> "Empty"
                        1 -> "1 work"
                        else -> "$count works"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                collection.description?.takeIf { it.isNotBlank() }?.let { description ->
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}
