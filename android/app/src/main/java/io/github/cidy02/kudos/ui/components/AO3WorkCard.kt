package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/**
 * Dense AO3 work summary for Search / Browse / Account lists.
 *
 * Material 3 [Card] expressing Apple `AO3WorkRow` hierarchy:
 * title → author → fandom → summary → status chips → list stats.
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
    val fandoms = work.fandoms.filter { it.isNotBlank() }
    // `fandoms.size > 1` matters: the collapsed card folds the rest into
    // "+N others", so without it a crossover with a short summary and no tags
    // would hide its extra fandoms behind no control at all.
    val expandable = work.summary.length > 120 || fandoms.size > 1 ||
        discoveryTags.isNotEmpty() || work.warnings.any { it.isNotBlank() }

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
                // The expand control leads the row, leaving the trailing corner to
                // the details button alone. It always occupies its slot, invisible
                // when there is nothing to expand: otherwise titles would start at
                // two different x positions down a list, which reads as broken
                // alignment rather than as an absent control.
                IconButton(
                    onClick = { expanded = !expanded },
                    enabled = expandable,
                    modifier = Modifier.alpha(if (expandable) 1f else 0f)
                ) {
                    Icon(
                        imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = if (expanded) "Show less" else "Show more"
                    )
                }
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
                WorkDetailsIconButton(onClick = { onOpenWork(work) })
            }

            // Collapsed, the card names the work's main fandom and counts the rest:
            // an AO3 crossover blurb can carry a dozen, each of them long, and
            // spelling them all out pushed the summary off the card.
            if (fandoms.isNotEmpty()) {
                val hidden = if (expanded) 0 else fandoms.size - 1
                CardMetaLine(
                    text = if (hidden > 0) {
                        "${fandoms.first()}  +$hidden other${if (hidden == 1) "" else "s"}"
                    } else {
                        fandoms.joinToString(", ")
                    },
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    accessibilityLabel = "Fandom: ${fandoms.joinToString()}"
                )
            }

            // Rating lives in stats; keep warnings/categories as chips when present.
            val safetyTags = (work.warnings + work.categories).filter { it.isNotBlank() }
            if (safetyTags.isNotEmpty()) {
                MetadataChipRow(
                    labels = safetyTags,
                    maxItems = if (expanded) 12 else 4,
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

            // The four AO3 states, as capsules — what the work *is*, separated
            // from the counts below by space rather than by a rule. The chip row
            // is already a band with its own edges; a hairline against it drew a
            // second boundary a few dp from the first.
            WorkStatusChipRow(
                stats = statusChips(
                    rating = work.rating,
                    categories = work.categories,
                    warnings = work.warnings,
                    isComplete = work.isComplete
                )
            )

            Spacer(modifier = Modifier.height(2.dp))

            WorkListStatsRow(
                stats = listRowStats(
                    rating = work.rating,
                    wordCount = work.wordCount,
                    chapters = work.chapters,
                    kudos = work.kudos
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
