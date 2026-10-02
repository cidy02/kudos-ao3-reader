package io.github.cidy02.kudos.library

import androidx.compose.runtime.Composable
import io.github.cidy02.kudos.data.preferences.SettingsRepository

/**
 * Queue details. The route stays `queue-detail/{id}`; the body is
 * `ReadingQueueSettingsView` (notes, tags, colour, keep offline).
 */
@Composable
fun QueueDetailScreen(
    queueId: String,
    repository: ReadingQueueRepository,
    settingsRepository: SettingsRepository? = null,
    epubBytes: (String) -> Long = { 0L },
    onOpenWork: (String) -> Unit,
    onShowOnlyTag: (String) -> Unit = {}
) {
    QueueSettingsScreen(
        queueId = queueId,
        repository = repository,
        settingsRepository = settingsRepository,
        epubBytes = epubBytes,
        onOpenWork = onOpenWork,
        onShowOnlyTag = onShowOnlyTag
    )
}
