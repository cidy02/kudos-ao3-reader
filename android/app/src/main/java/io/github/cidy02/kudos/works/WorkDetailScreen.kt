package io.github.cidy02.kudos.works

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun WorkDetailScreen(
    work: AO3WorkSummary? = null,
    onOpenReader: () -> Unit
) {
    if (work != null) {
        RemoteWorkDetailPlaceholder(work = work)
        return
    }

    PlaceholderScreen(
        title = "Placeholder Work",
        subtitle = "Representative work detail route for Phase 1 navigation.",
        sections = listOf(
            "Rating: Mature",
            "Warnings: Creator chose not to use archive warnings",
            "Words: 42,000",
            "Chapters: 12/12",
            "Summary: This screen reserves space for AO3 metadata, actions, and reader entry."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = onOpenReader) {
                Text("Open Reader Placeholder")
            }
            OutlinedButton(
                enabled = false,
                onClick = {}
            ) {
                Text("Download unavailable")
            }
        }
    }
}

@Composable
private fun RemoteWorkDetailPlaceholder(work: AO3WorkSummary) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = work.title,
            style = MaterialTheme.typography.headlineSmall,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = "by ${work.authorText}",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        MetadataLine(work.fandoms.joinToString(", "))
        MetadataLine((listOf(work.rating) + work.warnings + work.categories).filter { it.isNotBlank() }.joinToString(" - "))
        MetadataLine("Updated: ${work.updatedDate.ifBlank { "Unknown" }}")
        MetadataLine(work.statsLine())
        MetadataLine(work.workUrl)

        if (work.relationships.isNotEmpty()) MetadataLine("Relationships: ${work.relationships.joinToString(", ")}")
        if (work.characters.isNotEmpty()) MetadataLine("Characters: ${work.characters.joinToString(", ")}")
        if (work.freeforms.isNotEmpty()) MetadataLine("Tags: ${work.freeforms.joinToString(", ")}")

        if (work.summary.isNotBlank()) {
            Text(
                text = work.summary,
                style = MaterialTheme.typography.bodyMedium
            )
        }

        PlaceholderActions()
    }
}

@Composable
private fun PlaceholderActions() {
    val rows = listOf(
        listOf("Read", "Download"),
        listOf("Favorite", "User Tags"),
        listOf("Collections", "Open on AO3"),
        listOf("Kudos", "Comment")
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { labels ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                labels.forEach { label ->
                    PlaceholderAction(label, Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun MetadataLine(text: String) {
    if (text.isBlank()) return
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun PlaceholderAction(
    label: String,
    modifier: Modifier = Modifier
) {
    OutlinedButton(
        enabled = false,
        onClick = {},
        modifier = modifier
    ) {
        Text(label)
    }
}

private fun AO3WorkSummary.statsLine(): String {
    return listOfNotNull(
        wordCount?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" },
        kudos?.let { "%,d kudos".format(it) },
        comments?.let { "%,d comments".format(it) },
        hits?.let { "%,d hits".format(it) }
    ).joinToString(" - ")
}
