package io.github.cidy02.kudos.library

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection

/**
 * Filter and sort panel for Library and Reading Queues.
 * Material 3 [ModalBottomSheet] expressing Apple `LibraryFilterPanel`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryFilterPanel(
    filters: LibraryFilterState,
    sort: LibrarySort,
    userTags: List<Tag>,
    collections: List<WorkCollection>,
    onFiltersChange: (LibraryFilterState) -> Unit,
    onSortChange: (LibrarySort) -> Unit,
    onApply: () -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Filter and Sort",
                style = MaterialTheme.typography.titleLarge
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 520.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                FilterSection(title = "Sort by") {
                    ChipRow {
                        LibrarySort.entries.forEach { option ->
                            FilterChip(
                                selected = sort == option,
                                onClick = { onSortChange(option) },
                                label = { Text(option.label) }
                            )
                        }
                    }
                }

                FilterSection(title = "Status") {
                    ChipRow {
                        FilterChip(
                            selected = filters.favoriteOnly,
                            onClick = { onFiltersChange(filters.copy(favoriteOnly = !filters.favoriteOnly)) },
                            label = { Text("Favorites") }
                        )
                        LibraryFinishedFilter.entries.forEach { option ->
                            if (option == LibraryFinishedFilter.Any) return@forEach
                            FilterChip(
                                selected = filters.finished == option,
                                onClick = { onFiltersChange(filters.copy(finished = option)) },
                                label = { Text(option.name) }
                            )
                        }
                    }
                }

                FilterSection(title = "Download") {
                    ChipRow {
                        LibraryDownloadFilter.entries.forEach { option ->
                            if (option == LibraryDownloadFilter.Any) return@forEach
                            FilterChip(
                                selected = filters.download == option,
                                onClick = { onFiltersChange(filters.copy(download = option)) },
                                label = { Text(option.name.replace("NotDownloaded", "Not Downloaded")) }
                            )
                        }
                    }
                }

                FilterSection(title = "Completion") {
                    ChipRow {
                        LibraryCompletionFilter.entries.forEach { option ->
                            if (option == LibraryCompletionFilter.Any) return@forEach
                            FilterChip(
                                selected = filters.completion == option,
                                onClick = { onFiltersChange(filters.copy(completion = option)) },
                                label = { Text(option.name) }
                            )
                        }
                    }
                }

                if (userTags.isNotEmpty()) {
                    FilterSection(title = "My Tags") {
                        ChipRow {
                            userTags.forEach { tag ->
                                val selected = tag.id in filters.userTagIds
                                FilterChip(
                                    selected = selected,
                                    onClick = {
                                        onFiltersChange(
                                            filters.copy(
                                                userTagIds = if (selected) {
                                                    filters.userTagIds - tag.id
                                                } else {
                                                    filters.userTagIds + tag.id
                                                }
                                            )
                                        )
                                    },
                                    label = { Text(tag.normalizedName) }
                                )
                            }
                        }
                    }
                }

                if (collections.isNotEmpty()) {
                    FilterSection(title = "Collections") {
                        ChipRow {
                            collections.forEach { collection ->
                                val selected = collection.id in filters.collectionIds
                                FilterChip(
                                    selected = selected,
                                    onClick = {
                                        onFiltersChange(
                                            filters.copy(
                                                collectionIds = if (selected) {
                                                    filters.collectionIds - collection.id
                                                } else {
                                                    filters.collectionIds + collection.id
                                                }
                                            )
                                        )
                                    },
                                    label = { Text(collection.name) }
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))
            }

            HorizontalDivider()

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                if (filters.hasActiveFilters) {
                    TextButton(onClick = onClear) {
                        Text("Clear")
                    }
                }
                Spacer(modifier = Modifier.weight(1f))
                OutlinedButton(onClick = onDismiss) {
                    Text("Close")
                }
                Button(onClick = onApply) {
                    Text("Apply")
                }
            }
        }
    }
}

@Composable
private fun FilterSection(
    title: String,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        content()
    }
}

@Composable
private fun ChipRow(content: @Composable () -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
    ) {
        content()
    }
}
