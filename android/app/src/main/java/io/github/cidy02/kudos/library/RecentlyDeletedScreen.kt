package io.github.cidy02.kudos.library

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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.works.WorkRepository
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class RecentlyDeletedUiState(
    val loading: Boolean = true,
    val items: List<SavedWork> = emptyList(),
    val error: String? = null
)

class RecentlyDeletedViewModel(
    private val workRepository: WorkRepository
) : ViewModel() {
    val state: StateFlow<RecentlyDeletedUiState> = workRepository
        .observeRecentlyDeleted()
        .map { works ->
            RecentlyDeletedUiState(loading = false, items = works)
        }
        .catch { throwable ->
            emit(
                RecentlyDeletedUiState(
                    loading = false,
                    error = throwable.message ?: "Recently Deleted could not be loaded."
                )
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = RecentlyDeletedUiState(loading = true)
        )

    fun restore(workId: String) {
        viewModelScope.launch {
            // Dependency: deferred 1a fleshes out soft-delete / tombstone retract.
            workRepository.restoreFromRecentlyDeleted(workId)
        }
    }

    fun deleteForever(workId: String) {
        viewModelScope.launch {
            // Permanent remove; same path as removeFromLibrary.
            workRepository.hardDelete(workId)
        }
    }

    companion object {
        fun factory(workRepository: WorkRepository): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { RecentlyDeletedViewModel(workRepository) }
            }
    }
}

@Composable
fun RecentlyDeletedScreen(
    workRepository: WorkRepository
) {
    val viewModel: RecentlyDeletedViewModel = viewModel(
        factory = RecentlyDeletedViewModel.factory(workRepository)
    )
    val state by viewModel.state.collectAsState()
    var pendingHardDelete by remember { mutableStateOf<SavedWork?>(null) }

    if (pendingHardDelete != null) {
        val work = pendingHardDelete
        AlertDialog(
            onDismissRequest = { pendingHardDelete = null },
            title = { Text("Delete forever?") },
            text = {
                Text(
                    "This work is gone for good — it can't be restored afterward." +
                        if (work != null) "\n\n“${work.title}”" else ""
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val id = pendingHardDelete?.id
                        pendingHardDelete = null
                        if (id != null) viewModel.deleteForever(id)
                    }
                ) {
                    Text("Delete forever")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingHardDelete = null }) { Text("Cancel") }
            }
        )
    }

    RecentlyDeletedContent(
        state = state,
        onRestore = viewModel::restore,
        onDeleteForever = { work -> pendingHardDelete = work }
    )
}

@Composable
private fun RecentlyDeletedContent(
    state: RecentlyDeletedUiState,
    onRestore: (String) -> Unit,
    onDeleteForever: (SavedWork) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            // TopAppBar already says "Recently Deleted".
            KudosScreenHeader(
                subtitle = "Deleted works stay here for 90 days before permanent removal."
            )
        }

        if (state.loading) {
            item { LoadingStateCard("Loading Recently Deleted") }
            return@LazyColumn
        }

        state.error?.let { error ->
            item {
                ErrorStateCard(
                    title = "Recently Deleted could not load",
                    message = error
                )
            }
            return@LazyColumn
        }

        if (state.items.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "Nothing here",
                    message = "Deleted works, collections, and reading queues stay here for " +
                        "90 days before they're permanently removed."
                )
            }
            return@LazyColumn
        }

        items(state.items, key = { it.id }) { work ->
            RecentlyDeletedRow(
                work = work,
                onRestore = { onRestore(work.id) },
                onDeleteForever = { onDeleteForever(work) }
            )
        }
    }
}

@Composable
private fun RecentlyDeletedRow(
    work: SavedWork,
    onRestore: () -> Unit,
    onDeleteForever: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = work.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = "by ${work.author.ifBlank { "Anonymous" }}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            expiryCaption(work)?.let { caption ->
                Text(
                    text = caption,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onRestore) { Text("Restore") }
                OutlinedButton(onClick = onDeleteForever) { Text("Delete forever") }
            }
        }
    }
}

private fun expiryCaption(work: SavedWork): String? {
    val scheduled = work.permanentDeletionScheduledAt
    if (scheduled != null) {
        val days = ChronoUnit.DAYS.between(Instant.now(), scheduled).coerceAtLeast(0)
        val dateLabel = EXPIRY_DATE_FORMAT.format(scheduled.atZone(ZoneId.systemDefault()))
        return if (days == 0L) {
            "Expires today ($dateLabel)"
        } else {
            "Expires in $days day${if (days == 1L) "" else "s"} ($dateLabel)"
        }
    }
    val deletedAt = work.deletedAt ?: return null
    val dateLabel = EXPIRY_DATE_FORMAT.format(deletedAt.atZone(ZoneId.systemDefault()))
    return "Deleted $dateLabel"
}

private val EXPIRY_DATE_FORMAT: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd")
