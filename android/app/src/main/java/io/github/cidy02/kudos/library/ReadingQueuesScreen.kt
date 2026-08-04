package io.github.cidy02.kudos.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox

@Composable
fun ReadingQueuesScreen(
    repository: ReadingQueueRepository,
    onOpenQueue: (String) -> Unit
) {
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var queues by remember { mutableStateOf<List<ReadingQueueListItem>>(emptyList()) }

    suspend fun refresh() {
        loading = true
        error = null
        try {
            // Ensure default Saved for Later exists so the list is never empty for new installs.
            repository.ensureSavedForLaterQueue()
            val listed = repository.listQueues()
            queues = listed.map { queue ->
                ReadingQueueListItem(
                    queue = queue,
                    workCount = repository.listWorks(queue.id).size
                )
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load reading queues."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { refresh() }

    KudosRefreshBox(onRefresh = { refresh() }, modifier = Modifier.fillMaxSize()) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            // TopAppBar already says "Reading Queues".
            KudosScreenHeader(
                subtitle = "Local queues such as Saved for Later."
            )
        }

        when {
            loading -> item { LoadingStateCard("Loading reading queues") }
            error != null -> item {
                ErrorStateCard(
                    title = "Queues could not load",
                    message = error.orEmpty()
                )
            }
            queues.isEmpty() -> item {
                EmptyStateCard(
                    title = "No reading queues",
                    message = "Queues appear here once created or restored from backup."
                )
            }
            else -> items(queues, key = { it.queue.id }) { item ->
                QueueRow(
                    item = item,
                    onClick = { onOpenQueue(item.queue.id) }
                )
            }
        }
    }
    }
}

@Composable
private fun QueueRow(
    item: ReadingQueueListItem,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = item.queue.displayName,
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = when (item.workCount) {
                    0 -> "Empty"
                    1 -> "1 work"
                    else -> "${item.workCount} works"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private data class ReadingQueueListItem(
    val queue: ReadingQueue,
    val workCount: Int
)
