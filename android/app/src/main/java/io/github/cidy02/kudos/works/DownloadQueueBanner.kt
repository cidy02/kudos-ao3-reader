package io.github.cidy02.kudos.works

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Compact progress banner for the active download queue (Apple `DownloadQueueBanner`).
 * Shown at the app root above bottom navigation when [DownloadQueue.isActive].
 */
@Composable
fun DownloadQueueBanner(
    queue: DownloadQueue,
    modifier: Modifier = Modifier
) {
    val items by queue.items.collectAsState()
    val pending = items.count {
        it.status == DownloadQueueStatus.Queued || it.status == DownloadQueueStatus.Downloading
    }
    val isActive = pending > 0
    val total = items.size
    val finished = total - pending
    val currentTitle = items.firstOrNull { it.status == DownloadQueueStatus.Downloading }?.title
    val progressLabel = if (total > 0) {
        "Downloading ${minOf(finished + 1, total)} of $total"
    } else {
        "Downloading"
    }

    AnimatedVisibility(
        visible = isActive,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut()
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 8.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerHigh
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = progressLabel,
                        style = MaterialTheme.typography.labelLarge
                    )
                    if (!currentTitle.isNullOrBlank()) {
                        Text(
                            text = currentTitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                TextButton(onClick = { queue.cancel() }) {
                    Text("Cancel")
                }
            }
        }
    }
}
