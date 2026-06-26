package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork

@Composable
fun LibraryScreen(
    repository: LibraryRepository,
    onOpenWork: (String) -> Unit
) {
    val works by repository.observeSavedWorks().collectAsState(initial = emptyList())

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(text = "Library", style = MaterialTheme.typography.headlineMedium)
        if (works.isEmpty()) {
            Text(
                text = "Saved works will appear here after you save or download from Work Detail.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(works, key = { it.id }) { work ->
                    SavedWorkCard(work = work, onOpen = { onOpenWork(work.id) })
                }
            }
        }
    }
}

@Composable
private fun SavedWorkCard(
    work: SavedWork,
    onOpen: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = work.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = "by ${work.author.ifBlank { "Anonymous" }}",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = work.statusLine(),
                style = MaterialTheme.typography.labelMedium
            )
            if (work.summary.isNotBlank()) {
                Text(
                    text = work.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onOpen) {
                    Text("Details")
                }
            }
        }
    }
}

private fun SavedWork.statusLine(): String {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Metadata only",
        if (isFavorite) "Favorite" else null,
        if (isFinished) "Finished" else null,
        rating.takeIf { it.isNotBlank() },
        wordCount.takeIf { it > 0 }?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" }
    ).joinToString(" - ")
}
