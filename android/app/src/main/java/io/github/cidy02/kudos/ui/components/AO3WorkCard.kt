package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

@Composable
fun AO3WorkCard(
    work: AO3WorkSummary,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        modifier = modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
                    Text(
                        text = work.fandoms.joinToString(", "),
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            val requiredTags = (listOf(work.rating) + work.warnings + work.categories)
                .filter { it.isNotBlank() }
            if (requiredTags.isNotEmpty()) {
                Text(
                    text = requiredTags.joinToString(" - "),
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            val tagLine = (work.relationships + work.characters + work.freeforms)
                .take(8)
                .joinToString(", ")
            if (tagLine.isNotBlank()) {
                Text(
                    text = tagLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
            }

            if (work.summary.isNotBlank()) {
                Text(
                    text = work.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Row {
                Text(
                    text = work.statsLine(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = { onOpenWork(work) }) {
                    Text("Details")
                }
            }
        }
    }
}

private fun AO3WorkSummary.statsLine(): String {
    return listOfNotNull(
        wordCount?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" },
        kudos?.let { "%,d kudos".format(it) },
        comments?.let { "%,d comments".format(it) },
        hits?.let { "%,d hits".format(it) }
    ).joinToString(" - ").ifBlank {
        updatedDate.takeIf { it.isNotBlank() } ?: workUrl
    }
}
