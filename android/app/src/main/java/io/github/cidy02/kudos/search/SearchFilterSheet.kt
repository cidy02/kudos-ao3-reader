package io.github.cidy02.kudos.search

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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search

/**
 * Full advanced-search filter sheet over [AO3SearchFilters].
 *
 * Mirrors Apple `AO3FilterPanel`: sort, rating (+ match / Not Rated),
 * cycling warnings & categories, crossover, completion, word count,
 * updated, language, and comma-separated include/exclude tag fields.
 * Tag fields suggest from [localTagSuggestions] (library-only; no network).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchFilterSheet(
    filters: AO3SearchFilters,
    onFiltersChange: (AO3SearchFilters) -> Unit,
    onApply: () -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit,
    onSave: (() -> Unit)? = null,
    /**
     * Whether "Best Match" is offered. AO3's tag listing — Browse's endpoint — has no
     * relevance ordering at all: its sort menu runs Creator … Bookmarks and defaults
     * to Date Updated. Offering Best Match there sends no sort_column, AO3 orders by
     * revised_at anyway, and the sheet claims a sort that isn't happening.
     */
    allowsRelevanceSort: Boolean = true,
    localTagSuggestions: LocalTagSuggestions = LocalTagSuggestions(),
    autocompleteRepository: io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository? = null
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
            // Reset left, Apply right, with `ModalBottomSheet`'s own drag handle
            // between them as the dismiss affordance. Both actions used to sit at the
            // *bottom*, which meant scrolling past every facet to run the search you
            // had just configured.
            //
            // Reset is disabled rather than hidden: a control that appears and
            // disappears as filters change shifts Apply sideways under the thumb.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Icon buttons at the two ends, matching the app's sheet chrome
                // elsewhere — they read as chrome rather than as another form
                // control competing with the facets below.
                FilledTonalIconButton(onClick = onClear, enabled = filters.hasActiveFilters) {
                    Icon(Icons.Outlined.Refresh, contentDescription = "Reset filters")
                }
                Spacer(modifier = Modifier.weight(1f))
                FilledIconButton(onClick = onApply, enabled = filters.isSearchable) {
                    Icon(Icons.Outlined.Search, contentDescription = "Apply filters")
                }
            }
            Text(
                text = "Search filters",
                style = MaterialTheme.typography.titleLarge
            )
            Text(
                text = "Narrow AO3 works. Apply runs the search; Reset keeps your query.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
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
                        AO3SearchSort.entries
                            .filter { allowsRelevanceSort || it != AO3SearchSort.RELEVANCE }
                            .forEach { sort ->
                            FilterChip(
                                selected = filters.sort == sort,
                                onClick = { onFiltersChange(filters.copy(sort = sort)) },
                                label = { Text(sort.title) }
                            )
                        }
                    }
                }

                FilterSection(title = "Rating") {
                    ChipRow {
                        AO3Rating.searchCases.forEach { rating ->
                            FilterChip(
                                selected = filters.rating == rating,
                                onClick = {
                                    onFiltersChange(withRatingSelected(filters, rating))
                                },
                                label = { Text(rating.title) }
                            )
                        }
                    }
                    if (filters.rating != AO3Rating.ANY) {
                        Text(
                            text = "Match",
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                        ChipRow {
                            AO3RatingMatch.entries.forEach { match ->
                                FilterChip(
                                    selected = filters.ratingMatch == match,
                                    onClick = {
                                        onFiltersChange(filters.copy(ratingMatch = match))
                                    },
                                    label = { Text(match.title) }
                                )
                            }
                        }
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = "Include Not Rated",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f)
                        )
                        Switch(
                            checked = filters.includeNotRated,
                            onCheckedChange = {
                                onFiltersChange(filters.copy(includeNotRated = it))
                            }
                        )
                    }
                }

                FilterSection(
                    title = "Warnings",
                    footer = "Tap once to include, twice to exclude, third to clear."
                ) {
                    ChipRow {
                        AO3Warning.entries.forEach { warning ->
                            TriStateFilterChip(
                                label = warning.title,
                                state = warningSelection(filters, warning),
                                onClick = {
                                    onFiltersChange(cycleWarning(filters, warning))
                                }
                            )
                        }
                    }
                }

                FilterSection(
                    title = "Categories",
                    footer = "Tap once to include, twice to exclude, third to clear."
                ) {
                    ChipRow {
                        AO3Category.entries.forEach { category ->
                            TriStateFilterChip(
                                label = category.title,
                                state = categorySelection(filters, category),
                                onClick = {
                                    onFiltersChange(cycleCategory(filters, category))
                                }
                            )
                        }
                    }
                }

                FilterSection(title = "Crossovers") {
                    ChipRow {
                        AO3Crossover.entries.forEach { crossover ->
                            FilterChip(
                                selected = filters.crossover == crossover,
                                onClick = {
                                    onFiltersChange(filters.copy(crossover = crossover))
                                },
                                label = { Text(crossover.title) }
                            )
                        }
                    }
                }

                FilterSection(title = "Completion") {
                    ChipRow {
                        AO3Completion.entries.forEach { completion ->
                            FilterChip(
                                selected = filters.completion == completion,
                                onClick = {
                                    onFiltersChange(filters.copy(completion = completion))
                                },
                                label = { Text(completion.title) }
                            )
                        }
                    }
                }

                FilterSection(title = "Word count") {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        OutlinedTextField(
                            value = filters.wordsFrom,
                            onValueChange = {
                                onFiltersChange(filters.copy(wordsFrom = it))
                            },
                            label = { Text("From") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = filters.wordsTo,
                            onValueChange = {
                                onFiltersChange(filters.copy(wordsTo = it))
                            },
                            label = { Text("To") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                FilterSection(title = "Updated") {
                    ChipRow {
                        AO3Updated.entries.forEach { updated ->
                            FilterChip(
                                selected = filters.updated == updated,
                                onClick = {
                                    onFiltersChange(filters.copy(updated = updated))
                                },
                                label = { Text(updated.title) }
                            )
                        }
                    }
                }

                FilterSection(title = "Language") {
                    ChipRow {
                        AO3Language.entries.forEach { language ->
                            FilterChip(
                                selected = filters.language == language,
                                onClick = {
                                    onFiltersChange(filters.copy(language = language))
                                },
                                label = { Text(language.title) }
                            )
                        }
                    }
                }

                FilterSection(
                    title = "Tags",
                    footer = "Comma-separated. Suggestions come from your library and AO3. " +
                        "Use Exclude fields for −\"tag\" query clauses."
                ) {
                    TagPairFields(
                        includeLabel = "Fandoms",
                        includeValue = filters.fandom,
                        excludeLabel = "Exclude fandoms",
                        excludeValue = filters.excludedFandoms,
                        candidates = localTagSuggestions.fandoms,
                        ao3Kind = "fandom",
                        autocompleteRepository = autocompleteRepository,
                        onIncludeChange = { onFiltersChange(filters.copy(fandom = it)) },
                        onExcludeChange = {
                            onFiltersChange(filters.copy(excludedFandoms = it))
                        }
                    )
                    TagPairFields(
                        includeLabel = "Characters",
                        includeValue = filters.characters,
                        excludeLabel = "Exclude characters",
                        excludeValue = filters.excludedCharacters,
                        candidates = localTagSuggestions.characters,
                        ao3Kind = "character",
                        autocompleteRepository = autocompleteRepository,
                        onIncludeChange = { onFiltersChange(filters.copy(characters = it)) },
                        onExcludeChange = {
                            onFiltersChange(filters.copy(excludedCharacters = it))
                        }
                    )
                    TagPairFields(
                        includeLabel = "Relationships",
                        includeValue = filters.relationships,
                        excludeLabel = "Exclude relationships",
                        excludeValue = filters.excludedRelationships,
                        candidates = localTagSuggestions.relationships,
                        ao3Kind = "relationship",
                        autocompleteRepository = autocompleteRepository,
                        onIncludeChange = {
                            onFiltersChange(filters.copy(relationships = it))
                        },
                        onExcludeChange = {
                            onFiltersChange(filters.copy(excludedRelationships = it))
                        }
                    )
                    TagPairFields(
                        includeLabel = "Additional tags",
                        includeValue = filters.additionalTags,
                        excludeLabel = "Exclude additional tags",
                        excludeValue = filters.excludedAdditionalTags,
                        candidates = localTagSuggestions.freeforms,
                        ao3Kind = "freeform",
                        autocompleteRepository = autocompleteRepository,
                        onIncludeChange = {
                            onFiltersChange(filters.copy(additionalTags = it))
                        },
                        onExcludeChange = {
                            onFiltersChange(filters.copy(excludedAdditionalTags = it))
                        }
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))
            }

            HorizontalDivider()

            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                // Apply and Reset live in the header now; Close and Save stay here,
                // because both are rarer and more deliberate than either.
                Spacer(modifier = Modifier.weight(1f))
                OutlinedButton(onClick = onDismiss) {
                    Text("Close")
                }
                if (onSave != null) {
                    OutlinedButton(onClick = onSave) {
                        Text("Save")
                    }
                }
            }
        }
    }
}

@Composable
private fun FilterSection(
    title: String,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        content()
        if (!footer.isNullOrBlank()) {
            Text(
                text = footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ChipRow(content: @Composable () -> Unit) {
    // Horizontal scroll keeps dense enum rows usable without wrapping into a tall sheet.
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
    ) {
        content()
    }
}

@Composable
private fun TriStateFilterChip(
    label: String,
    state: FilterSelectionState,
    onClick: () -> Unit
) {
    val colors = when (state) {
        FilterSelectionState.CLEAR -> FilterChipDefaults.filterChipColors()
        FilterSelectionState.INCLUDED -> FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer
        )
        FilterSelectionState.EXCLUDED -> FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.errorContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onErrorContainer
        )
    }
    val display = when (state) {
        FilterSelectionState.CLEAR -> label
        FilterSelectionState.INCLUDED -> "+ $label"
        FilterSelectionState.EXCLUDED -> "− $label"
    }
    FilterChip(
        selected = state != FilterSelectionState.CLEAR,
        onClick = onClick,
        label = { Text(display) },
        colors = colors
    )
}

@Composable
private fun TagPairFields(
    includeLabel: String,
    includeValue: String,
    excludeLabel: String,
    excludeValue: String,
    candidates: List<String>,
    ao3Kind: String? = null,
    autocompleteRepository: io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository? = null,
    onIncludeChange: (String) -> Unit,
    onExcludeChange: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TagSuggestField(
            value = includeValue,
            onValueChange = onIncludeChange,
            label = includeLabel,
            candidates = candidates,
            ao3Kind = ao3Kind,
            autocompleteRepository = autocompleteRepository,
            modifier = Modifier.fillMaxWidth()
        )
        TagSuggestField(
            value = excludeValue,
            onValueChange = onExcludeChange,
            label = excludeLabel,
            candidates = candidates,
            ao3Kind = ao3Kind,
            autocompleteRepository = autocompleteRepository,
            modifier = Modifier.fillMaxWidth()
        )
    }
}
