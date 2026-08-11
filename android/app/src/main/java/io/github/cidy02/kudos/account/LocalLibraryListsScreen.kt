package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard

enum class LocalLibraryListKind {
    History,
    Favorites
}

/** Device-local history / favorites lists (Apple Account → Local section). */
@Composable
fun LocalLibraryListsScreen(
    kind: LocalLibraryListKind,
    repository: LibraryRepository,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val works by repository.observeSavedWorks().collectAsState(initial = null)
    if (works == null) {
        LoadingStateCard("Loading…")
        return
    }

    val filtered = remember(works, kind) {
        when (kind) {
            LocalLibraryListKind.History -> works!!
                .filter { it.lastReadDate != null }
                .sortedByDescending { it.lastReadDate }
            LocalLibraryListKind.Favorites -> works!!
                .filter { it.isFavorite }
                .sortedByDescending { it.lastReadDate ?: it.dateAdded }
        }
    }

    if (filtered.isEmpty()) {
        EmptyStateCard(
            title = when (kind) {
                LocalLibraryListKind.History -> "No local reading history"
                LocalLibraryListKind.Favorites -> "No favorites yet"
            },
            message = when (kind) {
                LocalLibraryListKind.History ->
                    "Works you open in Kudos appear here. This is separate from AO3 History."
                LocalLibraryListKind.Favorites ->
                    "Mark works as favorites to see them here."
            }
        )
        return
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        items(filtered, key = { it.id }) { work ->
            LocalWorkRow(
                work = work,
                onOpenWork = { onOpenWork(work.id) },
                onOpenReader = { onOpenReader(work.id) }
            )
        }
    }
}

@Composable
private fun LocalWorkRow(
    work: SavedWork,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    Card(
        onClick = {
            if (work.hasEpub) onOpenReader() else onOpenWork()
        },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = work.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            if (work.author.isNotBlank()) {
                Text(
                    text = "by ${work.author}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onOpenWork) { Text("Details") }
                if (work.hasEpub) {
                    TextButton(onClick = onOpenReader) { Text("Read") }
                }
            }
        }
    }
}
