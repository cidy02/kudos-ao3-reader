package io.github.cidy02.kudos.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/**
 * Home's select-mode bar: Delete, an Actions menu, and Done.
 * The shared [io.github.cidy02.kudos.ui.components.WorkBulkActionBar] stays as
 * Library draws it. Inverse actions stay in the menu so nothing Home could
 * already do disappears.
 */
@Composable
fun HomeBulkBar(
    selectedWorks: List<SavedWork>,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    downloadQueue: DownloadQueue?,
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var menuOpen by remember { mutableStateOf(false) }
    val enabled = selectedWorks.isNotEmpty()
    Surface(modifier = modifier.fillMaxWidth(), color = tokens.cardFill, shadowElevation = 8.dp) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(
                enabled = enabled,
                onClick = { controller.deleteTargets = selectedWorks }
            ) {
                Text("Delete", color = tokens.accent)
            }
            Box {
                TextButton(enabled = enabled, onClick = { menuOpen = true }) {
                    Text("Actions")
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    Action("Bulk Download") {
                        menuOpen = false
                        scope.launch {
                            selectedWorks.forEach { applyDownload(it, workRepository, downloadQueue, keep = true) }
                        }
                    }
                    Action("Remove Download") {
                        menuOpen = false
                        scope.launch {
                            selectedWorks.forEach { applyDownload(it, workRepository, downloadQueue, keep = false) }
                        }
                    }
                    Action("Favorite") {
                        menuOpen = false
                        scope.launch { selectedWorks.forEach { workRepository.setFavorite(it.id, true) } }
                    }
                    Action("Unfavorite") {
                        menuOpen = false
                        scope.launch { selectedWorks.forEach { workRepository.setFavorite(it.id, false) } }
                    }
                    Action("Save for Later") {
                        menuOpen = false
                        scope.launch {
                            selectedWorks.forEach { queueRepository?.addToSavedForLater(it.id) }
                            controller.onChanged()
                        }
                    }
                    Action("Remove from Saved for Later") {
                        menuOpen = false
                        scope.launch {
                            selectedWorks.forEach { queueRepository?.removeFromSavedForLater(it.id) }
                            controller.onChanged()
                        }
                    }
                    Action("Add to Queue") {
                        menuOpen = false
                        controller.queueTargets = selectedWorks
                    }
                    Action("Add to Collection") {
                        menuOpen = false
                        controller.collectionTargets = selectedWorks
                    }
                    Action("Tag") {
                        menuOpen = false
                        controller.tagTargets = selectedWorks
                    }
                    Action("Mark as Finished") {
                        menuOpen = false
                        scope.launch { selectedWorks.forEach { workRepository.setFinished(it.id, true) } }
                    }
                    Action("Mark as Still Reading") {
                        menuOpen = false
                        scope.launch { selectedWorks.forEach { workRepository.setFinished(it.id, false) } }
                    }
                }
            }
            TextButton(onClick = onDone) {
                Text("Done")
            }
        }
    }
}

@Composable
private fun Action(label: String, onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(label) }, onClick = onClick)
}
