package io.github.cidy02.kudos.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.works.WorkMetadataRefresh

/**
 * See all (no id) opens the organizer. A queue id opens that queue's page.
 * There is no bottom switcher (T-343). Choosing a queue from the organizer
 * stays on this route; back returns to the organizer.
 */
@Composable
fun ReadingQueueBrowserScreen(
    repository: ReadingQueueRepository,
    initialQueueId: String? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit = onOpenWork,
    onManageQueue: (String) -> Unit,
    epubBytes: (String) -> Long = { 0L },
    metadataRefresh: WorkMetadataRefresh? = null
) {
    var selectedQueueId by rememberSaveable { mutableStateOf(initialQueueId) }
    val queueId = selectedQueueId
    if (queueId == null) {
        QueueOrganizerScreen(
            repository = repository,
            epubBytes = epubBytes,
            onOpenQueue = { selectedQueueId = it }
        )
    } else {
        QueuePageScreen(
            repository = repository,
            queueId = queueId,
            epubBytes = epubBytes,
            metadataRefresh = metadataRefresh,
            onOpenWork = onOpenWork,
            onOpenReader = onOpenReader,
            onManageQueue = onManageQueue,
            onBackToOrganizer = if (initialQueueId == null) {
                { selectedQueueId = null }
            } else {
                null
            }
        )
    }
}
