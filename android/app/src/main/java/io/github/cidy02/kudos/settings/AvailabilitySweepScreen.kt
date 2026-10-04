package io.github.cidy02.kudos.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import io.github.cidy02.kudos.works.WorkRepository
import java.text.NumberFormat
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * The manual "which of my works has AO3 deleted?" check (iOS `AvailabilitySweepView`).
 *
 * The screen's job is to state the cost before any request is sent. A check is one AO3 request
 * for each work, and the reader is the only one who can decide that is worth it, which is why
 * this is a button here and never a background task. Leaving the screen stops the check and
 * keeps what it found.
 */
@Composable
fun AvailabilitySweepScreen(
    workRepository: WorkRepository,
    sweep: WorkAvailabilitySweep,
    onOpenWork: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val works by workRepository.observeLibraryWorks().collectAsState(initial = emptyList())
    // Every work marked unavailable, not just the ones this run found: the mark lasts.
    val unavailableWorks = remember(works) {
        works
            .filter { it.ao3Unavailable && !it.isDeleted }
            .sortedBy { it.title.lowercase() }
    }
    var counts by remember { mutableStateOf(WorkAvailabilitySweep.Counts()) }
    var job by remember { mutableStateOf<Job?>(null) }
    var completed by remember { mutableIntStateOf(0) }
    var total by remember { mutableIntStateOf(0) }
    var summary by remember { mutableStateOf<WorkAvailabilitySweep.Summary?>(null) }
    val isRunning = job != null
    LaunchedEffect(works, isRunning) {
        if (!isRunning) counts = sweep.counts()
    }

    fun start() {
        summary = null
        completed = 0
        total = minOf(counts.pending, WorkAvailabilitySweep.DEFAULT_LIMIT)
        job = scope.launch {
            try {
                summary = sweep.sweep { done, count ->
                    completed = done
                    total = count
                }
            } finally {
                job = null
            }
        }
    }

    SettingsPage(title = "Check Availability") {
        item {
            SettingsSection(footnote = null, label = "Before you start") {
                Column(
                    Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Kudos will check ${counts.pending.formatted()} " +
                            "${if (counts.pending == 1) "work" else "works"}, one at a time.",
                        color = tokens.primaryInk,
                        fontSize = 15.sp
                    )
                    // The honest reason this is a button and not a background task.
                    Caption(
                        "AO3 can't tell Kudos what changed, so each work must be checked " +
                            "separately. Kudos waits about two seconds between works to avoid " +
                            "overloading AO3; you can stop anytime and keep the results so far."
                    )
                    if (counts.unverifiable > 0) {
                        Caption(
                            "${counts.unverifiable.formatted()} imported " +
                                "${if (counts.unverifiable == 1) "work came" else "works came"} from " +
                                "other sites, so Kudos can't check them on AO3."
                        )
                    }
                    if (counts.pending > WorkAvailabilitySweep.DEFAULT_LIMIT) {
                        Caption(
                            "This check covers up to ${WorkAvailabilitySweep.DEFAULT_LIMIT} works. " +
                                "Start it again later for the rest; works checked during the past " +
                                "week are skipped."
                        )
                    }
                }
            }
        }
        if (isRunning) {
            item {
                SettingsSection(footnote = null) {
                    Column(
                        Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        LinearProgressIndicator(
                            progress = { completed.toFloat() / maxOf(total, 1) },
                            modifier = Modifier.fillMaxWidth(),
                            color = tokens.accent,
                            trackColor = tokens.glassStroke(0.13)
                        )
                        Caption("Checked ${completed.formatted()} of ${total.formatted()}")
                    }
                }
            }
        } else {
            summary?.let { result ->
                item {
                    SettingsSection(footnote = null, label = if (result.cancelled) "Stopped" else "Finished") {
                        Column(
                            Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            if (result.nowUnavailable > 0) {
                                ResultLine(
                                    Icons.Outlined.Inventory2,
                                    "${result.nowUnavailable.formatted()} " +
                                        "${if (result.nowUnavailable == 1) "work is" else "works are"} " +
                                        "no longer on AO3"
                                )
                                Caption(
                                    "Kudos marked them as no longer on AO3. Any downloaded copies are " +
                                        "now treated as the last copies you have and will be kept " +
                                        "permanently."
                                )
                            } else if (result.checked > 0) {
                                ResultLine(Icons.Outlined.CheckCircle, "Everything checked is still on AO3")
                            }
                            Caption(detailLine(result))
                        }
                    }
                }
            }
        }
        if (unavailableWorks.isNotEmpty()) {
            item {
                SettingsSection(
                    footnote = null,
                    label = "No longer on AO3 (${unavailableWorks.size.formatted()})"
                ) {
                    unavailableWorks.forEachIndexed { index, work ->
                        if (index > 0) SubjectRowSeparator()
                        Column(
                            Modifier
                                .fillMaxWidth()
                                .clickable { onOpenWork(work.id) }
                                .padding(horizontal = 13.dp, vertical = 10.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = work.title,
                                color = tokens.primaryInk,
                                fontSize = 15.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = work.author,
                                color = tokens.secondaryInk,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }
        item {
            SettingsSection(
                footnote = if (counts.pending == 0 && !isRunning) {
                    "You checked every AO3 work in your Library within the past week."
                } else {
                    null
                }
            ) {
                SettingsActionRow(
                    label = if (isRunning) "Checking…" else "Check Now",
                    icon = Icons.Outlined.Sync,
                    enabled = !isRunning && counts.pending > 0,
                    onClick = ::start
                )
                if (isRunning) {
                    SubjectRowSeparator()
                    SettingsActionRow(label = "Stop", onClick = { job?.cancel() })
                }
            }
        }
    }
}

/**
 * Says what was not done as plainly as what was: a check that quietly covered half the library
 * would read as a clean bill of health.
 */
private fun detailLine(summary: WorkAvailabilitySweep.Summary): String = buildList {
    add("Checked ${summary.checked.formatted()}.")
    if (summary.skippedRecent > 0) {
        add("Skipped ${summary.skippedRecent.formatted()} checked in the last week.")
    }
    if (summary.remaining > 0) {
        add("${summary.remaining.formatted()} still to check. Run this again to continue.")
    }
}.joinToString(" ")

private fun Int.formatted(): String = NumberFormat.getIntegerInstance().format(this)

@Composable
private fun Caption(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.sp, lineHeight = 16.sp)
}

@Composable
private fun ResultLine(icon: ImageVector, text: String) {
    val tokens = LocalKudosTokens.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(18.dp))
        Text(text, color = tokens.primaryInk, fontSize = 15.sp)
    }
}
