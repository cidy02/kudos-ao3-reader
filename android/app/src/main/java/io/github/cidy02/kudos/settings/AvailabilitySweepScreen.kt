package io.github.cidy02.kudos.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Manual "which of my works has AO3 deleted?" check. States the cost **before** any
 * traffic is sent — a sweep is one AO3 request per work, and the user is the only
 * one who can decide that is worth it (see [WorkAvailabilitySweep] for why this is
 * deliberately not the only place a sweep runs — `AvailabilitySweepWorker` also
 * runs it automatically every 7 days, unlike iOS's manual-only design).
 *
 * Apple `AvailabilitySweepView` parity: this used to be a one-line status message
 * on the Settings screen itself with no list of *which* works were affected.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AvailabilitySweepScreen(
    workRepository: WorkRepository,
    sweep: WorkAvailabilitySweep,
    onOpenWork: (String) -> Unit,
    onBack: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var pendingCount by remember { mutableIntStateOf(0) }
    var unverifiableCount by remember { mutableIntStateOf(0) }
    var completed by remember { mutableIntStateOf(0) }
    var total by remember { mutableIntStateOf(0) }
    var summary by remember { mutableStateOf<WorkAvailabilitySweep.Summary?>(null) }
    var runningJob by remember { mutableStateOf<Job?>(null) }
    var unavailableWorks by remember { mutableStateOf<List<SavedWork>>(emptyList()) }
    val isRunning = runningJob != null

    suspend fun refreshCounts() {
        pendingCount = sweep.pending().size
        val works = workRepository.listLibraryWorks()
        unverifiableCount = works.count { !it.isDeleted && it.sourceUrl.isBlank() }
        unavailableWorks = works
            .filter { it.ao3Unavailable && !it.isDeleted }
            .sortedBy { it.title.lowercase() }
    }

    LaunchedEffect(Unit) { refreshCounts() }

    fun start() {
        summary = null
        completed = 0
        runningJob = scope.launch {
            val result = sweep.run { done, count ->
                completed = done
                total = count
            }
            summary = result
            runningJob = null
            refreshCounts()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Check Availability") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(onClick = { if (isRunning) runningJob?.cancel() else onBack() }) {
                        Text(if (isRunning) "Stop" else "Done")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            item {
                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "Kudos will ask AO3 about $pendingCount " +
                            (if (pendingCount == 1) "work" else "works") + ", one at a time.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        "There is no way to ask AO3 what changed, so this is one request per work. " +
                            "It runs slowly on purpose — about 1.5 seconds each — to stay well inside " +
                            "what a person browsing the site would do. You can stop it at any time and " +
                            "keep whatever it has already found.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (unverifiableCount > 0) {
                        Text(
                            "$unverifiableCount imported " +
                                (if (unverifiableCount == 1) "work has" else "works have") +
                                " no AO3 link and can't be checked.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (pendingCount > WorkAvailabilitySweep.DEFAULT_LIMIT) {
                        Text(
                            "This run will cover ${WorkAvailabilitySweep.DEFAULT_LIMIT} of them. " +
                                "Run it again later for the rest — already-checked works are skipped " +
                                "for a week.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (isRunning) {
                item {
                    Column(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        LinearProgressIndicator(
                            progress = { if (total > 0) completed.toFloat() / total else 0f },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Text(
                            "Checked $completed of $total",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                summary?.let { result ->
                    item {
                        Column(
                            modifier = Modifier.padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            val headline = when {
                                result.nowUnavailable > 0 ->
                                    "${result.nowUnavailable} " +
                                        (if (result.nowUnavailable == 1) "work is" else "works are") +
                                        " no longer on AO3"
                                result.checked > 0 -> "Everything checked is still on AO3"
                                else -> null
                            }
                            headline?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                            Text(sweepDetailLine(result), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            item {
                Button(
                    onClick = { if (!isRunning) start() },
                    enabled = !isRunning && pendingCount > 0,
                    modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth()
                ) {
                    Text(if (isRunning) "Checking…" else "Check Now")
                }
            }

            if (unavailableWorks.isNotEmpty()) {
                item {
                    Text(
                        "No longer on AO3 (${unavailableWorks.size})",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                    )
                }
                items(unavailableWorks, key = { it.id }) { work ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenWork(work.id) }
                            .padding(horizontal = 20.dp, vertical = 10.dp)
                    ) {
                        Column {
                            Text(
                                work.title,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                work.author,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Says what was *not* done as plainly as what was — a sweep that quietly covered
 * half the library would read as a clean bill of health. */
private fun sweepDetailLine(result: WorkAvailabilitySweep.Summary): String {
    val parts = mutableListOf("Checked ${result.checked}.")
    if (result.skippedRecent > 0) parts.add("Skipped ${result.skippedRecent} checked in the last week.")
    if (result.remaining > 0) parts.add("${result.remaining} still to check — run this again to continue.")
    return parts.joinToString(" ")
}
