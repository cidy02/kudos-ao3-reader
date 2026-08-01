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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
    val scope = rememberCoroutineScope()

    suspend fun refresh() {
        loading = true
        error = null
        try {
            queue = repository.getQueue(queueId)
            items = if (queue != null) repository.listWorks(queueId) else emptyList()
            if (queue == null) {
                error = "This reading queue no longer exists."
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load queue."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(queueId) { refresh() }

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

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            // TopAppBar is generic ("Queue"); show queue name + count as context.
            KudosScreenHeader(
                title = queue?.displayName?.takeIf { it.isNotBlank() && it != "Queue" },
                subtitle = when {
                    loading -> "Loading…"
                    items.isEmpty() -> "No works in this queue."
                    items.size == 1 -> "1 work"
                    else -> "${items.size} works"
                }
            )
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
                } else {
                    items(items, key = { it.membership.id }) { item ->
                        QueueWorkRow(
                            item = item,
                            enabled = !working,
                            onOpenWork = {
                                item.work?.id?.let(onOpenWork)
                            },
                            onRemove = { removeWork(item.membership.workID) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun QueueWorkRow(
    item: QueueMembershipItem,
    enabled: Boolean,
    onOpenWork: () -> Unit,
    onRemove: () -> Unit
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
            Column(
                modifier = Modifier
                    .weight(1f)
                    .then(
                        if (item.work != null) {
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
