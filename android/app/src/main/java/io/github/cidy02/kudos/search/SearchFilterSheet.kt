package io.github.cidy02.kudos.search

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.time.LocalDate

/** iOS AO3FilterPanel's section order; Refine changes only the loaded page. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchFilterSheet(
    filters: AO3SearchFilters,
    onFiltersChange: (AO3SearchFilters) -> Unit,
    onApply: () -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit,
    onSave: (() -> Unit)? = null,
    allowsRelevanceSort: Boolean = true,
    localTagSuggestions: LocalTagSuggestions = LocalTagSuggestions(),
    autocompleteRepository: AO3TagAutocompleteRepository? = null,
    refine: Boolean = false,
    refineMatchText: String? = null,
    showFandomPicker: Boolean = true,
    canReset: Boolean = filters.hasActiveFilters
) {
    val tokens = LocalKudosTokens.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.background
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.headerGutter).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onClear, enabled = canReset) {
                    Icon(Icons.Outlined.Refresh, "Reset filters",
                        tint = if (canReset) tokens.accent else tokens.tertiaryInk)
                }
                Text(
                    if (refine) "Refine" else "Filters", Modifier.weight(1f),
                    color = tokens.primaryInk, fontSize = 18.sp, fontWeight = FontWeight.SemiBold
                )
                // iOS's accent-filled confirm icon wins over the brief's plain-actions description.
                FilledIconButton(
                    onClick = onApply, enabled = refine || filters.isSearchable,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = tokens.accent, contentColor = SubjectPalette.label(tokens.accent)
                    )
                ) {
                    Icon(if (refine) Icons.Outlined.Check else Icons.Outlined.Search,
                        if (refine) "Done" else "Apply filters")
                }
            }
            if (refine && refineMatchText != null) {
                FilterNote(refineMatchText, Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            }
            Column(
                Modifier.fillMaxWidth().heightIn(max = 520.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                FilterGroup {
                    if (!refine) {
                        FilterChoiceRow("Sort by", AO3SearchSort.entries.filter {
                            allowsRelevanceSort || it != AO3SearchSort.RELEVANCE
                        }, filters.sort, { it.title }) {
                            onFiltersChange(filters.copy(sort = it, sortDirection = it.naturalDirection))
                        }
                        if (filters.sort != AO3SearchSort.RELEVANCE) {
                            SubjectRowSeparator()
                            if (isAccessibilityFontScale()) {
                                FilterChoiceRow("Order", AO3SortDirection.entries, filters.sortDirection, { it.title }) {
                                    onFiltersChange(filters.copy(sortDirection = it))
                                }
                            } else {
                                SubjectFormRow("Order", trailing = {
                                    SubjectSegmentedControl(
                                        AO3SortDirection.entries, filters.sortDirection,
                                        { onFiltersChange(filters.copy(sortDirection = it)) }, { it.title },
                                        modifier = Modifier.fillMaxWidth(0.75f), contentDescription = "Order"
                                    )
                                })
                            }
                        }
                        SubjectRowSeparator()
                    }
                    FilterChoiceRow("Rating", AO3Rating.searchCases, filters.rating, { it.title }) {
                        onFiltersChange(withRatingSelected(filters, it))
                    }
                    if (filters.rating != AO3Rating.ANY) {
                        SubjectRowSeparator()
                        FilterChoiceRow("Match", AO3RatingMatch.entries, filters.ratingMatch, { it.title }) {
                            onFiltersChange(filters.copy(ratingMatch = it))
                        }
                    }
                    SubjectRowSeparator()
                    SubjectFormRow("Include Not Rated", trailing = {
                        SubjectToggle(filters.includeNotRated, {
                            onFiltersChange(filters.copy(includeNotRated = it))
                        }, contentDescription = "Include Not Rated")
                    })
                }
                FilterGroup("Warnings") {
                    AO3Warning.entries.forEachIndexed { index, warning ->
                        if (index > 0) SubjectRowSeparator()
                        FilterFacetRow(warning.title, warningSelection(filters, warning)) {
                            onFiltersChange(cycleWarning(filters, warning))
                        }
                    }
                }
                FilterGroup("Categories") {
                    AO3Category.entries.forEachIndexed { index, category ->
                        if (index > 0) SubjectRowSeparator()
                        FilterFacetRow(category.title, categorySelection(filters, category)) {
                            onFiltersChange(cycleCategory(filters, category))
                        }
                    }
                }
                FilterGroup(note = if (refine) null else CROSSOVER_NOTE) {
                    if (!refine) {
                        FilterChoiceRow("Crossovers", AO3Crossover.entries, filters.crossover, { it.title }) {
                            onFiltersChange(filters.copy(crossover = it))
                        }
                        SubjectRowSeparator()
                    }
                    FilterChoiceRow("Completion", AO3Completion.entries, filters.completion, { it.title }) {
                        onFiltersChange(filters.copy(completion = it))
                    }
                    SubjectRowSeparator()
                    FilterChoiceRow("Chapters", AO3ChapterCount.entries, filters.chapterCount, { it.title }) {
                        onFiltersChange(filters.copy(chapterCount = it))
                    }
                }
                FilterGroup(note = if (refine) null else DATE_NOTE) {
                    if (!refine) {
                        FilterChoiceRow("Updated", AO3Updated.entries, filters.updated, { it.title }) {
                            onFiltersChange(filters.copy(updated = it))
                        }
                        SubjectRowSeparator()
                        FilterDateRow("After", filters.dateFrom) { onFiltersChange(filters.copy(dateFrom = it)) }
                        SubjectRowSeparator()
                        FilterDateRow("Before", filters.dateTo) { onFiltersChange(filters.copy(dateTo = it)) }
                        SubjectRowSeparator()
                    }
                    FilterLanguageRow(filters.language) { onFiltersChange(filters.copy(language = it)) }
                }
                FilterGroup("Tags", TAG_NOTE) {
                    if (showFandomPicker) {
                        FilterTagRow("Fandoms", "fandom", filters.fandom, filters.excludedFandoms,
                            localTagSuggestions.fandoms, if (refine) null else autocompleteRepository) { included, excluded ->
                            onFiltersChange(filters.copy(fandom = included, excludedFandoms = excluded))
                        }
                        SubjectRowSeparator()
                    }
                    FilterTagRow("Characters", "character", filters.characters, filters.excludedCharacters,
                        localTagSuggestions.characters, if (refine) null else autocompleteRepository) { included, excluded ->
                        onFiltersChange(filters.copy(characters = included, excludedCharacters = excluded))
                    }
                    SubjectRowSeparator()
                    FilterTagRow("Relationships", "relationship", filters.relationships, filters.excludedRelationships,
                        localTagSuggestions.relationships, if (refine) null else autocompleteRepository) { included, excluded ->
                        onFiltersChange(filters.copy(relationships = included, excludedRelationships = excluded))
                    }
                    SubjectRowSeparator()
                    FilterTagRow("Additional Tags", "freeform", filters.additionalTags, filters.excludedAdditionalTags,
                        localTagSuggestions.freeforms, if (refine) null else autocompleteRepository) { included, excluded ->
                        onFiltersChange(filters.copy(additionalTags = included, excludedAdditionalTags = excluded))
                    }
                }
                if (!refine) FilterGroup("Title & creator") {
                    FilterTextRow("Title", filters.title) { onFiltersChange(filters.copy(title = it)) }
                    SubjectRowSeparator()
                    FilterTextRow("Creator", filters.creators) { onFiltersChange(filters.copy(creators = it)) }
                }
                FilterGroup("Word count", if (refine) RANGE_NOTE else null) {
                    FilterRangeSlider(filters.wordsFrom, filters.wordsTo, 200_000) { from, to ->
                        onFiltersChange(filters.copy(wordsFrom = from, wordsTo = to))
                    }
                }
                if (!refine) {
                    FilterGroup("Hits") {
                        FilterRangeSlider(filters.hitsFrom, filters.hitsTo, 1_000_000) { from, to ->
                            onFiltersChange(filters.copy(hitsFrom = from, hitsTo = to))
                        }
                    }
                    FilterGroup("Kudos") {
                        FilterRangeSlider(filters.kudosFrom, filters.kudosTo, 50_000) { from, to ->
                            onFiltersChange(filters.copy(kudosFrom = from, kudosTo = to))
                        }
                    }
                    FilterGroup("Comments") {
                        FilterRangeSlider(filters.commentsFrom, filters.commentsTo, 10_000) { from, to ->
                            onFiltersChange(filters.copy(commentsFrom = from, commentsTo = to))
                        }
                    }
                    FilterGroup("Bookmarks", RANGE_NOTE) {
                        FilterRangeSlider(filters.bookmarksFrom, filters.bookmarksTo, 10_000) { from, to ->
                            onFiltersChange(filters.copy(bookmarksFrom = from, bookmarksTo = to))
                        }
                    }
                    if (onSave != null) FilterGroup {
                        SubjectFormRow("Save Search…", onClick = if (filters.isSearchable) onSave else null)
                    }
                    // Android's existing dismissal row remains available.
                    FilterGroup { SubjectFormRow("Close", onClick = onDismiss) }
                }
            }
        }
    }
}

@Composable
internal fun FilterGroup(title: String? = null, note: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (title != null) SubjectFieldLabel(title)
        Column(Modifier.subjectPanel()) { content() }
        if (note != null) FilterNote(note)
    }
}

@Composable
internal fun FilterNote(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
}

@Composable
private fun <T> FilterChoiceRow(
    title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        SubjectFormRow(title, value = label(selected), showsDisclosure = true, onClick = { expanded = true },
            valueMaxLines = 3)
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(label(option)) },
                    modifier = Modifier.semantics { this.selected = option == selected },
                    trailingIcon = {
                        if (option == selected) Icon(Icons.Outlined.Check, null, tint = LocalKudosTokens.current.accent)
                    },
                    onClick = { onSelect(option); expanded = false })
            }
        }
    }
}

@Composable
private fun FilterTextRow(title: String, value: String, onChange: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    BasicTextField(
        value, onChange, singleLine = true, cursorBrush = SolidColor(tokens.accent),
        textStyle = TextStyle(color = tokens.primaryInk, fontSize = 14.5.sp),
        modifier = Modifier.fillMaxWidth().padding(13.dp).semantics { contentDescription = title },
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(title, color = tokens.secondaryInk, fontSize = 14.5.sp)
                inner()
            }
        }
    )
}

@Composable
private fun FilterDateRow(title: String, date: LocalDate?, onChange: (LocalDate?) -> Unit) {
    val context = LocalContext.current
    SubjectFormRow(title, trailing = {
        SubjectToggle(date != null, { onChange(if (it) date ?: LocalDate.now() else null) }, contentDescription = title)
    })
    if (date != null) SubjectFormRow(
        title, value = date.toString(), showsDisclosure = true, onClick = {
            DatePickerDialog(context, { _, year, month, day ->
                onChange(LocalDate.of(year, month + 1, day))
            }, date.year, date.monthValue - 1, date.dayOfMonth).show()
        }
    )
}

private const val CROSSOVER_NOTE =
    "When you change crossover status, Kudos runs a new AO3 search because each result doesn't include it."
private const val DATE_NOTE =
    "The Updated, After, and Before choices all use the work's update date. " +
        "A work appears only if it matches every date choice."
private const val TAG_NOTE =
    "Tap a tag once to include it, twice to exclude it, and a third time to clear it."
private const val RANGE_NOTE =
    "Leave either end of the slider at its starting position if you don't want a minimum " +
        "or maximum. AO3 treats one-sided ranges as “more than” or “fewer than”."
