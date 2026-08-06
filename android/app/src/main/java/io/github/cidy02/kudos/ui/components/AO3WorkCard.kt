package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/**
 * Dense AO3 work summary for Search / Browse / Account lists.
 *
 * Material 3 [Card] expressing Apple `AO3WorkRow` hierarchy:
 * title → author → fandom → summary → divider → list stats.
 * Tags use progressive disclosure (expand) so the default row stays scannable.
 *
 * [expandAll] is a batch seed from the parent (Search "Expand all" / "Collapse
 * all"): every time it changes, local expand state is reset to match. Individual
 * cards can still be toggled afterward — expand-all is not a permanent lock.
 *
 * Whole-card tap opens Work Detail. [WorkDetailsIconButton] is the explicit
 * MD3 detail affordance (same destination for remote works until download-into-
 * reader lands).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AO3WorkCard(
    work: AO3WorkSummary,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    expandAll: Boolean = false,
    onTagClick: ((String) -> Unit)? = null,
    onLongClick: (() -> Unit)? = null
) {
    var expanded by remember(work.id) { mutableStateOf(expandAll) }
    // Seed/reset local expand state whenever the parent batch toggle flips
    // (Compose equivalent of iOS `onChange(of: expandAll, initial: true)`).
    LaunchedEffect(expandAll) {
        expanded = expandAll
    }
    val discoveryTags = (work.relationships + work.characters + work.freeforms)
        .filter { it.isNotBlank() }
    val expandable = work.summary.length > 120 || discoveryTags.isNotEmpty() ||
        work.warnings.any { it.isNotBlank() }

    var showMenu by remember { mutableStateOf(false) }

    Box(modifier = modifier.workCardZoomSource(work.id)) {
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            ),
            shape = MaterialTheme.shapes.medium,
            modifier = Modifier
                .fillMaxWidth()
                .semantics {
                    contentDescription = "${work.title}, by ${work.authorText.ifBlank { "Anonymous" }}"
                }
                .combinedClickable(
                    onClick = { onOpenWork(work) },
                    onLongClick = onLongClick ?: { showMenu = true }
                )
        ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = work.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "by ${work.authorText.ifBlank { "Anonymous" }}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                // The last-updated date earns the prime top-right corner: it
                // answers "is this still being written" at a glance (iOS
                // `WorkUpdatedDateBadge` parity). The published date stays with
                // the other stats below the divider.
                work.updatedDate.takeIf { it.isNotBlank() }?.let { updated ->
                    val display = displayDate(updated)
                    WorkStatLabel(
                        item = WorkStatItem(
                            text = display,
                            accessibilityLabel = "Updated $display",
                            icon = WorkStatIcons.dateUpdated
                        )
                    )
                }
                if (expandable) {
                    TextButton(onClick = { expanded = !expanded }) {
                        Text(if (expanded) "Less" else "More")
                    }
                }
                WorkDetailsIconButton(onClick = { onOpenWork(work) })
            }

            if (work.fandoms.isNotEmpty()) {
                CardMetaLine(
                    text = work.fandoms.take(3).joinToString(", "),
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    accessibilityLabel = "Fandom: ${work.fandoms.joinToString()}"
                )
            }

            // Rating, category, warnings and status all live in the top stats
            // row below as color-coded badges. The specific warning names stay
            // available as chips, but only once expanded — the badge already
            // says how many apply.
            val warningTags = realWarnings(work.warnings).filter { it.isNotBlank() }
            if (expanded && warningTags.isNotEmpty()) {
                MetadataChipRow(
                    labels = warningTags,
                    maxItems = 12,
                    onLabelClick = onTagClick
                )
            }

            if (work.summary.isNotBlank()) {
                Text(
                    text = work.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = if (expanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis
                )
            }

            if (expanded && discoveryTags.isNotEmpty()) {
                MetadataChipRow(
                    labels = discoveryTags,
                    maxItems = 16,
                    onLabelClick = onTagClick
                )
            }

            HorizontalDivider(
                modifier = Modifier.padding(top = 4.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )

            WorkTopStatsRow(
                stats = topRowStats(
                    rating = work.rating,
                    categories = work.categories,
                    warnings = work.warnings,
                    isComplete = work.isComplete
                )
            )

            WorkListStatsRow(
                stats = listRowStats(
                    language = work.language,
                    wordCount = work.wordCount,
                    chapters = work.chapters,
                    comments = work.comments,
                    kudos = work.kudos,
                    bookmarks = work.bookmarks,
                    hits = work.hits,
                    datePublished = work.publishedDate
                )
            )
        }
    }
        
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            DropdownMenuItem(
                text = { Text("Open Work") },
                onClick = {
                    showMenu = false
                    onOpenWork(work)
                }
            )
            DropdownMenuItem(
                text = { Text("Copy Link") },
                onClick = {
                    showMenu = false
                    // clipboard.setText(AnnotatedString(work.workUrl))
                }
            )
        }
    }
}
