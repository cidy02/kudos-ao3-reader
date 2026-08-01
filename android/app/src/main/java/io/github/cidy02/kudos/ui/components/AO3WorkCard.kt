package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/**
 * Dense AO3 work summary card for Search / Browse / Account lists.
 *
 * Whole-card tap opens Work Detail (remote download-into-reader is deferred —
 * see ANDROID_HIG_REVIEW_SYNC report). ⓘ is an explicit secondary affordance
 * with the same destination, mirroring hig-review's info control on cards.
 */
@Composable
fun AO3WorkCard(
    work: AO3WorkSummary,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = { onOpenWork(work) },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "${work.title}, by ${work.authorText.ifBlank { "Anonymous" }}"
            }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = work.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "by ${work.authorText}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (work.fandoms.isNotEmpty()) {
                        MetadataChipRow(
                            labels = work.fandoms.take(4),
                            maxItems = 4,
                            prominent = true
                        )
                    }
                }
                TextButton(onClick = { onOpenWork(work) }) {
                    Text("ⓘ")
                }
            }

            val requiredTags = (listOf(work.rating) + work.warnings + work.categories)
                .filter { it.isNotBlank() }
            if (requiredTags.isNotEmpty()) {
                MetadataChipRow(labels = requiredTags, maxItems = 6)
            }

            val discoveryTags = (work.relationships + work.characters + work.freeforms)
                .take(8)
            if (discoveryTags.isNotEmpty()) {
                MetadataChipRow(labels = discoveryTags, maxItems = 8)
            }

            if (work.summary.isNotBlank()) {
                Text(
                    text = work.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
            }

            CoverCardStatsColumn(stats = work.coverStats())
        }
    }
}

private fun AO3WorkSummary.coverStats(): List<WorkStatItem> {
    return listOfNotNull(
        ratingDisplayName(rating)?.let { WorkStatItem(it, accessibilityLabel = rating) },
        chapters.takeIf { it.isNotBlank() }?.let {
            WorkStatItem(chapterStatText(it), accessibilityLabel = "Chapters $it")
        },
        completionStatText(isComplete)?.let { WorkStatItem(it) },
        wordCount?.takeIf { it > 0 }?.let {
            WorkStatItem(wordStatText(it), accessibilityLabel = "%,d words".format(it))
        },
        kudos?.let {
            WorkStatItem(
                text = if (it == 1) "1 kudos" else "%,d kudos".format(it),
                accessibilityLabel = "%,d kudos".format(it)
            )
        },
        comments?.let {
            WorkStatItem(
                text = if (it == 1) "1 comment" else "%,d comments".format(it)
            )
        },
        hits?.let {
            WorkStatItem(
                text = if (it == 1) "1 hit" else "%,d hits".format(it)
            )
        },
        updatedDate.takeIf { it.isNotBlank() }?.let { WorkStatItem("Updated $it") }
    )
}
