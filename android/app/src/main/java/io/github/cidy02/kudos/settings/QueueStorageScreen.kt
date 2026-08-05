package io.github.cidy02.kudos.settings

import android.text.format.Formatter
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.outlined.ListAlt
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun SettingsGroup(
    title: String,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
        )
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
            ),
            shape = RoundedCornerShape(12.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
        ) {
            Column(
                modifier = Modifier.padding(vertical = 8.dp),
                content = content
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun QueueStorageScreen(
    workRepository: WorkRepository,
    readingQueueRepository: ReadingQueueRepository,
    settingsRepository: SettingsRepository,
    workFileStore: WorkFileStore,
    onBack: () -> Unit
) {
    val settings by settingsRepository.settings.collectAsState(initial = io.github.cidy02.kudos.core.model.KudosSettings.Defaults)
    val works by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    
    var fileSizes by remember { mutableStateOf<Map<String, Long>>(emptyMap()) }
    var pendingQueueRemoval by remember { mutableStateOf<SavedWork?>(null) }
    
    val queuedWorks = works.filter { it.isQueuedForLater }
    val preservedWorks = queuedWorks.filter { it.hasEpub && File(workFileStore.workEpubPath(it.id).toString()).exists() }
    val queueOnlyWorks = queuedWorks.filter { it.isQueueOnlyWork }
    
    LaunchedEffect(preservedWorks) {
        withContext(Dispatchers.IO) {
            val sizes = preservedWorks.associate { work ->
                work.id to File(workFileStore.workEpubPath(work.id).toString()).length()
            }
            fileSizes = sizes
        }
    }
    
    val preservedByteCount = preservedWorks.sumOf { fileSizes[it.id] ?: 0L }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Queue Storage") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        KudosRefreshBox(
            modifier = Modifier.fillMaxSize().padding(padding),
            onRefresh = { }
        ) {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                item {
                    SettingsGroup(
                        title = "Summary",
                        modifier = Modifier.padding(horizontal = 20.dp)
                    ) {
                        LabeledContent("Queued Works", "${queuedWorks.size}")
                        LabeledContent("Queue-only Works", "${queueOnlyWorks.size}")
                        LabeledContent("Preserved EPUBs", "${preservedWorks.size}")
                        LabeledContent("Preserved Storage", Formatter.formatFileSize(context, preservedByteCount))
                    }
                }
                
                item {
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Preserved EPUBs",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                }
                
                if (preservedWorks.isEmpty()) {
                    item {
                        Box(modifier = Modifier.padding(horizontal = 20.dp)) {
                            EmptyStateCard(
                                title = "No EPUBs",
                                message = "No queued EPUBs are currently stored on this device."
                            )
                        }
                    }
                } else {
                    items(preservedWorks, key = { it.id }) { work ->
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) {
                                    pendingQueueRemoval = work
                                }
                                false
                            }
                        )
                        
                        SwipeToDismissBox(
                            state = dismissState,
                            backgroundContent = {
                                val color = MaterialTheme.colorScheme.error
                                Row(
                                    modifier = Modifier.fillMaxSize().background(color).padding(horizontal = 16.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.End
                                ) {
                                    Icon(
                                        Icons.Default.RemoveCircleOutline,
                                        contentDescription = "Remove from Queues",
                                        tint = MaterialTheme.colorScheme.onError
                                    )
                                }
                            },
                            enableDismissFromStartToEnd = false
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(MaterialTheme.colorScheme.surface)
                                    .padding(horizontal = 20.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.Top
                            ) {
                                Icon(
                                    imageVector = if (work.isQueuedForLater) Icons.Default.Bookmark else Icons.Outlined.ListAlt,
                                    contentDescription = null,
                                    modifier = Modifier.size(28.dp).padding(top = 2.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                                Spacer(modifier = Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = work.title,
                                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                                        color = MaterialTheme.colorScheme.onSurface,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    if (work.author.isNotEmpty()) {
                                        Text(
                                            text = work.author,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                    Text(
                                        text = Formatter.formatFileSize(context, fileSizes[work.id] ?: 0L),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                if (work.isQueueOnlyWork) {
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = "Queue",
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier
                                            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                                            .padding(horizontal = 8.dp, vertical = 4.dp)
                                    )
                                }
                            }
                        }
                    }
                }
                
                item {
                    Text(
                        text = "Removing a work here only removes queue membership. Saved or favorited works stay in Kudos; queue-only works are removed when no queues remain.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
                    )
                }
            }
        }
        
        if (pendingQueueRemoval != null) {
            val work = pendingQueueRemoval!!
            DestructiveConfirmation(
                show = true,
                title = "Remove from reading queues?",
                text = if (work.isSaved || work.isFavorite) {
                    "This keeps the work in your Library and only removes its reading queue membership."
                } else {
                    "This queue-only work will be removed from Kudos if it has no remaining queues."
                },
                confirmText = if (work.isQueueOnlyWork) "Remove Queues & Delete" else "Remove from Queues",
                onConfirm = {
                    scope.launch {
                        readingQueueRepository.removeFromAllQueuesAndDeleteIfQueueOnly(work.id)
                    }
                    pendingQueueRemoval = null
                },
                onDismissRequest = { pendingQueueRemoval = null },
                confirmBeforeDelete = settings.app.confirmBeforeDelete
            )
        }
    }
}

@Composable
fun LabeledContent(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        Text(text = value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// QueueStorageLogic for the JUnit test
object QueueStorageLogic {
    fun queuedWorks(works: List<SavedWork>): List<SavedWork> {
        return works.filter { it.isQueuedForLater }
    }
    fun preservedWorks(queuedWorks: List<SavedWork>, fileExists: (String) -> Boolean): List<SavedWork> {
        return queuedWorks.filter { it.hasEpub && fileExists(it.id) }
    }
    fun queueOnlyWorks(queuedWorks: List<SavedWork>): List<SavedWork> {
        return queuedWorks.filter { it.isQueueOnlyWork }
    }
}
