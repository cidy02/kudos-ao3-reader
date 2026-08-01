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
import androidx.compose.runtime.collectAsState
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
    // A Collection had no mature-content gating at all: title, author and a live
    // Read button rendered unconditionally, unlike every other screen showing local
    // works (Library, Home). Reuses the same LibraryPrivacy computation and the
    // shared PrivacyGate those use, rather than a third parallel privacy mechanism.
    val privacy by (settingsRepository?.settings?.map { it.privacy }
        ?: kotlinx.coroutines.flow.flowOf(PrivacySettings()))
        .collectAsState(initial = PrivacySettings())
    val reveal by privacyGate.state.collectAsState()
    var loading by remember(collectionId) { mutableStateOf(true) }
    var working by remember(collectionId) { mutableStateOf(false) }
    var error by remember(collectionId) { mutableStateOf<String?>(null) }
    var collection by remember(collectionId) { mutableStateOf<WorkCollection?>(null) }
    var works by remember(collectionId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    var confirmDelete by remember(collectionId) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

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

    fun removeWork(workId: String) {
        scope.launch {
            working = true
            error = null
            try {
                workRepository.removeFromCollection(workId, collectionId)
                works = workRepository.worksForCollection(collectionId)
                collection = workRepository.getCollection(collectionId)
            } catch (e: Exception) {
                error = e.message ?: "Could not remove work."
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
                        OutlinedButton(
                            enabled = !working && !loading,
                            onClick = { confirmDelete = true }
                        ) {
                            Text("Delete")
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
                            message = "Add works from Work Detail with Add collection. " +
                                "You can delete this empty shelf with Delete."
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
                            onReveal = { privacyGate.reveal(work.id) },
                            onRemove = { removeWork(work.id) }
                        )
                    }
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
                    // Obscured: the whole title/author block reveals on tap instead of
                    // opening the work — this screen had no such gate at all before
                    // (found in review), unlike every other place a local work renders.
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
