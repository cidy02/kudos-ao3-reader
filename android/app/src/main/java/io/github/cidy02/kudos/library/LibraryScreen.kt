package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import java.time.Instant
import kotlin.math.roundToInt

@Composable
fun LibraryScreen(
    repository: LibraryRepository,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    val viewModel: LibraryViewModel = viewModel(factory = LibraryViewModel.factory(repository))
    val state by viewModel.state.collectAsState()

    LibraryContent(
        state = state,
        onSearch = viewModel::updateSearchQuery,
        onSort = viewModel::updateSort,
        onToggleFavorite = viewModel::toggleFavoriteOnly,
        onFinishedFilter = viewModel::setFinishedFilter,
        onDownloadFilter = viewModel::setDownloadFilter,
        onToggleUserTag = viewModel::toggleUserTag,
        onToggleCollection = viewModel::toggleCollection,
        onClearFilters = viewModel::clearFilters,
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader
    )
}

@Composable
private fun LibraryContent(
    state: LibraryUiState,
    onSearch: (String) -> Unit,
    onSort: (LibrarySort) -> Unit,
    onToggleFavorite: () -> Unit,
    onFinishedFilter: (LibraryFinishedFilter) -> Unit,
    onDownloadFilter: (LibraryDownloadFilter) -> Unit,
    onToggleUserTag: (String) -> Unit,
    onToggleCollection: (String) -> Unit,
    onClearFilters: () -> Unit,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            horizontal = 20.dp,
            vertical = 18.dp
        ),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { LibraryHeader(state) }

        if (state.loading) {
            item { CircularProgressIndicator() }
            return@LazyColumn
        }

        state.error?.let { error ->
            item { Text(text = error, color = MaterialTheme.colorScheme.error) }
            return@LazyColumn
        }

        if (!state.hasSavedWorks) {
            item { EmptyLibraryState() }
            return@LazyColumn
        }

        item {
            LibrarySectionPreview(
                title = "Continue Reading",
                items = state.continueReading.take(4),
                emptyMessage = "No in-progress works.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            LibrarySectionPreview(
                title = "Reading History",
                items = state.readingHistory.take(4),
                emptyMessage = "No reading history.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            LibrarySectionPreview(
                title = "Recently Added",
                items = state.recentlyAdded.take(4),
                emptyMessage = "No saved works.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        if (state.favorites.isNotEmpty()) {
            item {
                LibrarySectionPreview(
                    title = "Favorites",
                    items = state.favorites.take(4),
                    emptyMessage = "No favorites.",
                    onOpenWork = onOpenWork,
                    onOpenReader = onOpenReader
                )
            }
        }

        item {
            LibraryControls(
                state = state,
                onSearch = onSearch,
                onSort = onSort,
                onToggleFavorite = onToggleFavorite,
                onFinishedFilter = onFinishedFilter,
                onDownloadFilter = onDownloadFilter,
                onToggleUserTag = onToggleUserTag,
                onToggleCollection = onToggleCollection,
                onClearFilters = onClearFilters
            )
        }

        item {
            Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Text(text = "All Saved Works", style = MaterialTheme.typography.titleLarge)
                Text(
                    text = "${state.items.size}",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (state.items.isEmpty()) {
            item { NoResultsState(state) }
        } else {
            items(state.items, key = { it.item.work.id }) { display ->
                SavedWorkCard(
                    display = display,
                    onOpenWork = { onOpenWork(display.item.work.id) },
                    onOpenReader = { onOpenReader(display.item.work.id) }
                )
            }
        }
    }
}

@Composable
private fun LibraryHeader(state: LibraryUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = "Library", style = MaterialTheme.typography.headlineMedium)
        val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
            " - $it hidden by privacy"
        }.orEmpty()
        Text(
            text = "${state.totalSaved} saved${hidden}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun EmptyLibraryState() {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text = "No saved works", style = MaterialTheme.typography.titleMedium)
            Text(
                text = "Your saved works will appear here.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun NoResultsState(state: LibraryUiState) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text = "No matches", style = MaterialTheme.typography.titleMedium)
            Text(
                text = if (state.hasActiveQueryOrFilters) {
                    "No saved works match the current Library view."
                } else {
                    "No saved works are visible."
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun LibrarySectionPreview(
    title: String,
    items: List<LibraryDisplayItem>,
    emptyMessage: String,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleLarge)
        if (items.isEmpty()) {
            Text(
                text = emptyMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            items.forEach { display ->
                CompactWorkRow(display, onOpenWork, onOpenReader)
            }
        }
    }
}

@Composable
private fun LibraryControls(
    state: LibraryUiState,
    onSearch: (String) -> Unit,
    onSort: (LibrarySort) -> Unit,
    onToggleFavorite: () -> Unit,
    onFinishedFilter: (LibraryFinishedFilter) -> Unit,
    onDownloadFilter: (LibraryDownloadFilter) -> Unit,
    onToggleUserTag: (String) -> Unit,
    onToggleCollection: (String) -> Unit,
    onClearFilters: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = state.searchQuery,
            onValueChange = onSearch,
            label = { Text("Search Library") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Text(text = "Sort", style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            LibrarySort.entries.forEach { sort ->
                FilterChip(
                    selected = state.sort == sort,
                    onClick = { onSort(sort) },
                    label = { Text(sort.label) }
                )
            }
        }

        Text(text = "Filters", style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = state.filters.favoriteOnly,
                onClick = onToggleFavorite,
                label = { Text("Favorites") }
            )
            FilterChip(
                selected = state.filters.download == LibraryDownloadFilter.Downloaded,
                onClick = {
                    onDownloadFilter(
                        if (state.filters.download == LibraryDownloadFilter.Downloaded) {
                            LibraryDownloadFilter.Any
                        } else {
                            LibraryDownloadFilter.Downloaded
                        }
                    )
                },
                label = { Text("Downloaded") }
            )
            FilterChip(
                selected = state.filters.download == LibraryDownloadFilter.NotDownloaded,
                onClick = {
                    onDownloadFilter(
                        if (state.filters.download == LibraryDownloadFilter.NotDownloaded) {
                            LibraryDownloadFilter.Any
                        } else {
                            LibraryDownloadFilter.NotDownloaded
                        }
                    )
                },
                label = { Text("Not downloaded") }
            )
            FilterChip(
                selected = state.filters.finished == LibraryFinishedFilter.Finished,
                onClick = {
                    onFinishedFilter(
                        if (state.filters.finished == LibraryFinishedFilter.Finished) {
                            LibraryFinishedFilter.Any
                        } else {
                            LibraryFinishedFilter.Finished
                        }
                    )
                },
                label = { Text("Finished") }
            )
            FilterChip(
                selected = state.filters.finished == LibraryFinishedFilter.Unfinished,
                onClick = {
                    onFinishedFilter(
                        if (state.filters.finished == LibraryFinishedFilter.Unfinished) {
                            LibraryFinishedFilter.Any
                        } else {
                            LibraryFinishedFilter.Unfinished
                        }
                    )
                },
                label = { Text("Unfinished") }
            )
        }

        LibraryFacetChips(
            title = "User Tags",
            empty = "No user tags.",
            values = state.userTags,
            selectedIds = state.filters.userTagIds,
            label = { it.normalizedName },
            id = { it.id },
            onToggle = onToggleUserTag
        )
        LibraryFacetChips(
            title = "Collections",
            empty = "No collections.",
            values = state.collections,
            selectedIds = state.filters.collectionIds,
            label = { it.name },
            id = { it.id },
            onToggle = onToggleCollection
        )

        if (state.filters.hasActiveFilters) {
            TextButton(onClick = onClearFilters) { Text("Clear filters") }
        }
        HorizontalDivider()
    }
}

@Composable
private fun <T> LibraryFacetChips(
    title: String,
    empty: String,
    values: List<T>,
    selectedIds: Set<String>,
    label: (T) -> String,
    id: (T) -> String,
    onToggle: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleSmall)
        if (values.isEmpty()) {
            Text(
                text = empty,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                values.forEach { value ->
                    val valueId = id(value)
                    FilterChip(
                        selected = valueId in selectedIds,
                        onClick = { onToggle(valueId) },
                        label = { Text(label(value), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    )
                }
            }
        }
    }
}

@Composable
private fun CompactWorkRow(
    display: LibraryDisplayItem,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    val work = display.item.work
    Surface(
        tonalElevation = 1.dp,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) {
                    Text(text = "Mature work hidden", style = MaterialTheme.typography.titleSmall)
                    Text(
                        text = work.rating.ifBlank { "Mature content" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        text = work.title,
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "by ${work.author.ifBlank { "Anonymous" }}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = work.compactStatusLine(),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            if (work.hasEpub && display.privacyVisibility == LibraryPrivacyVisibility.Visible) {
                TextButton(onClick = { onOpenReader(work.id) }) { Text("Read") }
            }
            TextButton(onClick = { onOpenWork(work.id) }) { Text("Details") }
        }
    }
}

@Composable
private fun SavedWorkCard(
    display: LibraryDisplayItem,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    val work = display.item.work
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
            if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) {
                Text(text = "Mature work hidden", style = MaterialTheme.typography.titleMedium)
                Text(
                    text = work.rating.ifBlank { "Mature content" },
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = work.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "by ${work.author.ifBlank { "Anonymous" }}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                work.fandomLine()?.let { MetadataLine(it) }
                MetadataLine(work.fullStatusLine())
                if (work.summary.isNotBlank()) {
                    Text(
                        text = work.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                TagLine(display.item.userTags, display.item.collections)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onOpenWork) { Text("Details") }
                if (work.hasEpub && display.privacyVisibility == LibraryPrivacyVisibility.Visible) {
                    Button(onClick = onOpenReader) { Text("Read") }
                }
            }
        }
    }
}

@Composable
private fun MetadataLine(value: String) {
    if (value.isNotBlank()) {
        Text(
            text = value,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun TagLine(tags: List<Tag>, collections: List<WorkCollection>) {
    val labels = (tags.map { "#${it.normalizedName}" } + collections.map { "Shelf: ${it.name}" }).take(4)
    if (labels.isEmpty()) return
    Text(
        text = labels.joinToString("  "),
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis
    )
}

private fun SavedWork.fullStatusLine(): String {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFavorite) "Favorite" else null,
        if (isFinished) "Finished" else null,
        if (isComplete) "Complete" else "In progress",
        rating.takeIf { it.isNotBlank() },
        wordCount.takeIf { it > 0 }?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" },
        kudos.takeIf { it > 0 }?.let { "$it kudos" },
        comments?.takeIf { it > 0 }?.let { "$it comments" },
        hits?.takeIf { it > 0 }?.let { "$it hits" },
        lastReadDate?.let { "Read ${it.shortDate()}" },
        readingProgressFraction()?.let { "${(it * 100).roundToInt()}%" }
    ).joinToString(" - ")
}

private fun SavedWork.compactStatusLine(): String {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFinished) "Finished" else null,
        lastReadDate?.let { "Read ${it.shortDate()}" },
        readingProgressFraction()?.let { "${(it * 100).roundToInt()}%" }
    ).joinToString(" - ")
}

private fun SavedWork.fandomLine(): String? {
    val fandoms = workFandoms.ifEmpty { workTags }
        .filter { it.isNotBlank() }
        .take(3)
    return fandoms.takeIf { it.isNotEmpty() }?.joinToString(", ")
}

private fun Instant.shortDate(): String = toString().substringBefore('T')
