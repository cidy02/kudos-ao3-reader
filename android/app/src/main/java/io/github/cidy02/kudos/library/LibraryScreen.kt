package io.github.cidy02.kudos.library

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.components.CardMetaLine
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.ui.components.StatusBadge
import io.github.cidy02.kudos.ui.components.WorkDetailsIconButton
import io.github.cidy02.kudos.ui.components.WorkListStatsRow
import io.github.cidy02.kudos.ui.components.listRowStats
import java.time.Instant
import kotlin.math.roundToInt

@Composable
fun LibraryScreen(
    repository: LibraryRepository,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit = {},
    onOpenReadingQueues: () -> Unit = {},
    onOpenReadingStatistics: () -> Unit = {},
    onOpenCollections: () -> Unit = {}
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
        onOpenReader = onOpenReader,
        onOpenReadingQueues = onOpenReadingQueues,
        onOpenRecentlyDeleted = onOpenRecentlyDeleted,
        onOpenReadingStatistics = onOpenReadingStatistics,
        onOpenCollections = onOpenCollections
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
    onOpenReader: (String) -> Unit,
    onOpenRecentlyDeleted: () -> Unit = {},
    onOpenReadingQueues: () -> Unit = {},
    onOpenReadingStatistics: () -> Unit = {},
    onOpenCollections: () -> Unit = {}
) {
    // Filters stay collapsed by default so shelves + main list lead (Apple density parity).
    var filtersExpanded by rememberSaveable { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            horizontal = 20.dp,
            vertical = 18.dp
        ),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Subtitle/count + Collections/Queues/Insights/Deleted — TopAppBar already says "Library".
        item {
            LibraryToolbarRow(
                state = state,
                onOpenCollections = onOpenCollections,
                onOpenReadingQueues = onOpenReadingQueues,
                onOpenReadingStatistics = onOpenReadingStatistics,
                onOpenRecentlyDeleted = onOpenRecentlyDeleted
            )
        }

        if (state.loading) {
            item { LoadingStateCard("Loading your Library") }
            return@LazyColumn
        }

        state.error?.let { error ->
            item {
                ErrorStateCard(
                    title = "Library could not load",
                    message = error
                )
            }
            return@LazyColumn
        }

        if (!state.hasSavedWorks) {
            item { EmptyLibraryState() }
            return@LazyColumn
        }

        // 1) Search near top
        item {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = onSearch,
                label = { Text("Search Library") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        }

        // 2) Short shelf previews lead content
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

        // 3) Advanced filters tucked behind expandable header (default collapsed)
        item {
            LibraryFiltersPanel(
                state = state,
                expanded = filtersExpanded,
                onExpandedChange = { filtersExpanded = it },
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
            KudosSectionHeader(
                title = "All Saved Works",
                trailing = {
                    StatusBadge("${state.items.size}")
                }
            )
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

/**
 * Light toolbar under the scaffold TopAppBar: saved count + Collections / Queues /
 * Insights / Recently Deleted. Avoids a second full "Library" title.
 */
@Composable
private fun LibraryToolbarRow(
    state: LibraryUiState,
    onOpenCollections: () -> Unit = {},
    onOpenReadingQueues: () -> Unit,
    onOpenReadingStatistics: () -> Unit = {},
    onOpenRecentlyDeleted: () -> Unit = {}
) {
    val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
        " · $it hidden by privacy"
    }.orEmpty()
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = "${state.totalSaved} saved$hidden",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onOpenCollections) {
                Text("Collections")
            }
            TextButton(onClick = onOpenReadingQueues) {
                Text("Queues")
            }
            if (state.hasSavedWorks) {
                TextButton(onClick = onOpenReadingStatistics) {
                    Text("Insights")
                }
            }
            TextButton(onClick = onOpenRecentlyDeleted) {
                Text("Recently Deleted")
            }
        }
    }
}

@Composable
private fun EmptyLibraryState() {
    EmptyStateCard(
        title = "No saved works",
        message = "Your saved works will appear here after you save from Search, Browse, or Work Detail."
    )
}

@Composable
private fun NoResultsState(state: LibraryUiState) {
    EmptyStateCard(
        title = "No matches",
        message = if (state.hasActiveQueryOrFilters) {
            "No saved works match the current Library view."
        } else {
            "No saved works are visible."
        }
    )
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
        KudosSectionHeader(
            title = title,
            subtitle = if (items.isEmpty()) null else "${items.size} shown"
        )
        if (items.isEmpty()) {
            EmptyStateCard(
                title = "Nothing here yet",
                message = emptyMessage
            )
        } else {
            items.forEach { display ->
                CompactWorkRow(display, onOpenWork, onOpenReader)
            }
        }
    }
}

/**
 * Collapsible sort + filter controls. Default collapsed so the shelves/list lead.
 */
@Composable
private fun LibraryFiltersPanel(
    state: LibraryUiState,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSort: (LibrarySort) -> Unit,
    onToggleFavorite: () -> Unit,
    onFinishedFilter: (LibraryFinishedFilter) -> Unit,
    onDownloadFilter: (LibraryDownloadFilter) -> Unit,
    onToggleUserTag: (String) -> Unit,
    onToggleCollection: (String) -> Unit,
    onClearFilters: () -> Unit
) {
    val activeCount = state.filters.activeFilterCount()
    val headerLabel = if (activeCount > 0) "Filters ($activeCount)" else "Filters"
    val expandLabel = if (expanded) "Collapse filters" else "Expand filters"

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(
                    onClick = { onExpandedChange(!expanded) }
                )
                .semantics {
                    contentDescription = "$headerLabel. $expandLabel"
                }
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Outlined.FilterList,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = headerLabel,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )
            if (activeCount > 0) {
                StatusBadge("$activeCount")
            }
            Icon(
                imageVector = if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(text = "Sort", style = MaterialTheme.typography.titleSmall)
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    LibrarySort.entries.forEach { sort ->
                        FilterChip(
                            selected = state.sort == sort,
                            onClick = { onSort(sort) },
                            label = { Text(sort.label) }
                        )
                    }
                }

                Text(text = "Filters", style = MaterialTheme.typography.titleSmall)
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
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
            }
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
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
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
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    val onPrimaryOpen: () -> Unit = {
        if (canRead) onOpenReader(work.id) else onOpenWork(work.id)
    }
    // MD3 filled tonal list row — dense, whole-row primary action.
    Surface(
        tonalElevation = 1.dp,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onPrimaryOpen)
            .semantics {
                contentDescription = if (obscured) {
                    "Mature work hidden. ${work.rating.ifBlank { "Mature content" }}"
                } else {
                    val action = if (canRead) "Read" else "Open details for"
                    "$action ${work.title}, by ${work.author.ifBlank { "Anonymous" }}"
                }
            }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (obscured) {
                    StatusBadge("Mature work hidden")
                    MetadataChipRow(labels = listOf(work.rating.ifBlank { "Mature content" }))
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
                    MetadataChipRow(labels = work.compactStatusLabels(), maxItems = 3)
                }
            }
            WorkDetailsIconButton(onClick = { onOpenWork(work.id) })
        }
    }
}

/**
 * Full Library card — Material 3 surface card with the same list hierarchy as
 * Search (`AO3WorkCard`): title, author, fandom, summary, divider, list stats.
 * Primary open is reader-first when an EPUB is present.
 */
@Composable
private fun SavedWorkCard(
    display: LibraryDisplayItem,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    val onPrimaryOpen = if (canRead) onOpenReader else onOpenWork
    Card(
        onClick = onPrimaryOpen,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = if (obscured) {
                    "Mature work hidden. ${work.rating.ifBlank { "Mature content" }}"
                } else {
                    val action = if (canRead) "Read" else "Open details for"
                    "$action ${work.title}, by ${work.author.ifBlank { "Anonymous" }}"
                }
            }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (obscured) {
                StatusBadge("Mature work hidden")
                MetadataChipRow(labels = listOf(work.rating.ifBlank { "Mature content" }))
            } else {
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
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "by ${work.author.ifBlank { "Anonymous" }}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    WorkDetailsIconButton(onClick = onOpenWork)
                }
                work.primaryFandom()?.let { fandom ->
                    CardMetaLine(
                        text = fandom,
                        icon = Icons.AutoMirrored.Outlined.MenuBook,
                        accessibilityLabel = "Fandom: $fandom"
                    )
                }
                MetadataChipRow(labels = work.localStatusLabels(), maxItems = 4)
                if (work.summary.isNotBlank()) {
                    Text(
                        text = work.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                TagLine(display.item.userTags, display.item.collections)
                HorizontalDivider(
                    modifier = Modifier.padding(top = 2.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                WorkListStatsRow(
                    stats = listRowStats(
                        rating = work.rating,
                        wordCount = work.wordCount.takeIf { it > 0 },
                        chapters = work.chapters,
                        kudos = work.kudos.takeIf { it > 0 }
                    )
                )
            }
        }
    }
}

@Composable
private fun TagLine(tags: List<Tag>, collections: List<WorkCollection>) {
    val labels = (tags.map { "#${it.normalizedName}" } + collections.map { "Shelf: ${it.name}" }).take(4)
    MetadataChipRow(labels = labels, maxItems = 4)
}

/** Local-only status chips (download/favorite/finished/progress). */
private fun SavedWork.localStatusLabels(): List<String> {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFavorite) "Favorite" else null,
        if (isFinished) "Finished" else null,
        lastReadDate?.let { "Read ${it.shortDate()}" },
        readingProgressFraction()?.let { "${(it * 100).roundToInt()}%" }
    )
}

private fun SavedWork.compactStatusLabels(): List<String> {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFinished) "Finished" else null,
        lastReadDate?.let { "Read ${it.shortDate()}" },
        readingProgressFraction()?.let { "${(it * 100).roundToInt()}%" }
    )
}

private fun SavedWork.primaryFandom(): String? {
    return workFandoms.firstOrNull { it.isNotBlank() }
        ?: workTags.firstOrNull { it.isNotBlank() }
}

private fun Instant.shortDate(): String = toString().substringBefore('T')

/** Count discrete active facets for the Filters badge (presentation only). */
private fun LibraryFilterState.activeFilterCount(): Int {
    var count = 0
    if (favoriteOnly) count++
    if (finished != LibraryFinishedFilter.Any) count++
    if (download != LibraryDownloadFilter.Any) count++
    if (completion != LibraryCompletionFilter.Any) count++
    count += userTagIds.size
    count += collectionIds.size
    count += ratings.size
    count += warnings.size
    count += categories.size
    count += fandoms.size
    count += relationships.size
    count += characters.size
    count += freeforms.size
    return count
}
