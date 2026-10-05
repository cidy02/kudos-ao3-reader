package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.works.WorkSearchIndex

/** Live local filters, in iOS LibraryFilterPanel's order, with Android's extra controls retained. */
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
    onDismiss: () -> Unit,
    searchQuery: String? = null,
    onSearchQueryChange: (String) -> Unit = {},
    works: List<SavedWork> = emptyList()
) {
    val tokens = LocalKudosTokens.current
    val languages = remember(works) { works.map { it.language }.filter { it.isNotEmpty() }.distinct().sorted() }
    val canReset = filters.hasActiveFilters || sort != LibrarySort.Natural || !searchQuery.isNullOrBlank()
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
                IconButton(
                    onClick = {
                        onClear()
                        onSortChange(LibrarySort.Natural)
                        if (searchQuery != null) onSearchQueryChange("")
                    },
                    enabled = canReset
                ) {
                    Icon(Icons.Outlined.Refresh, "Reset filters", tint = if (canReset) tokens.accent else tokens.tertiaryInk)
                }
                Text(
                    "Filters", Modifier.weight(1f), color = tokens.primaryInk,
                    fontSize = 18.sp, fontWeight = FontWeight.SemiBold
                )
                // iOS draws this one accent-filled (`.borderedProminent`), as on its search
                // filter panel: the confirm is the only filled circle, Reset stays plain.
                FilledIconButton(
                    onClick = onApply,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = tokens.accent, contentColor = SubjectPalette.label(tokens.accent)
                    )
                ) { Icon(Icons.Outlined.Check, "Done") }
            }
            Column(
                Modifier.fillMaxWidth().heightIn(max = 520.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Column(Modifier.subjectPanel()) {
                    LibraryChoiceRow("Sort by", LibrarySort.entries, sort, { it.label }, onSortChange)
                    SubjectRowSeparator()
                    LibraryChoiceRow("Rating", AO3Rating.entries, filters.rating, { it.title }) {
                        onFiltersChange(filters.copy(rating = it))
                    }
                }
                LibraryFilterGroup("Warnings") {
                    AO3Warning.entries.forEachIndexed { index, warning ->
                        if (index > 0) SubjectRowSeparator()
                        LibrarySelectableRow(warning.title, warning.title in filters.warnings) {
                            onFiltersChange(filters.copy(warnings = filters.warnings.toggled(warning.title)))
                        }
                    }
                }
                LibraryFilterGroup("Categories") {
                    AO3Category.entries.forEachIndexed { index, category ->
                        if (index > 0) SubjectRowSeparator()
                        LibrarySelectableRow(category.title, category.title in filters.categories) {
                            onFiltersChange(filters.copy(categories = filters.categories.toggled(category.title)))
                        }
                    }
                }
                Column(Modifier.subjectPanel()) {
                    LibraryChoiceRow(
                        "Completion", LibraryCompletionFilter.entries, filters.completion,
                        { when (it) {
                            LibraryCompletionFilter.Any -> AO3Completion.ANY.title
                            LibraryCompletionFilter.Complete -> AO3Completion.COMPLETE.title
                            LibraryCompletionFilter.InProgress -> AO3Completion.IN_PROGRESS.title
                        } }
                    ) { onFiltersChange(filters.copy(completion = it)) }
                    if (languages.isNotEmpty()) {
                        SubjectRowSeparator()
                        LibraryChoiceRow("Language", listOf("") + languages, filters.language, {
                            it.ifEmpty { "Any language" }
                        }) { onFiltersChange(filters.copy(language = it)) }
                    }
                }
                LibraryFilterGroup(
                    "Word count", "A work's word count appears after you open it, using the number from AO3."
                ) {
                    LibraryWordRow("From", filters.wordsFrom) { onFiltersChange(filters.copy(wordsFrom = it)) }
                    SubjectRowSeparator()
                    LibraryWordRow("To", filters.wordsTo) { onFiltersChange(filters.copy(wordsTo = it)) }
                }
                LibraryFilterGroup(
                    "Tags", "Choose AO3 tags to show matching works. Exclude Tags hides works with those tags."
                ) {
                    if (userTags.isNotEmpty()) {
                        LibraryMultiSelectRow(
                            "Your Tags", userTags.map { it.id to it.normalizedName }, filters.userTagIds
                        ) { onFiltersChange(filters.copy(userTagIds = it)) }
                        SubjectRowSeparator()
                    }
                    LibraryTagRow("Fandoms", works, { it.workFandoms }, filters.fandoms) {
                        onFiltersChange(filters.copy(fandoms = it))
                    }
                    SubjectRowSeparator()
                    LibraryTagRow("Characters", works, { it.workCharacters }, filters.characters) {
                        onFiltersChange(filters.copy(characters = it))
                    }
                    SubjectRowSeparator()
                    LibraryTagRow("Relationships", works, { it.workRelationships }, filters.relationships) {
                        onFiltersChange(filters.copy(relationships = it))
                    }
                    SubjectRowSeparator()
                    LibraryTagRow("Additional Tags", works, { it.workFreeforms }, filters.freeforms) {
                        onFiltersChange(filters.copy(freeforms = it))
                    }
                    SubjectRowSeparator()
                    LibraryTagRow("Exclude Tags", works, { it.workTags }, filters.excludeTags) {
                        onFiltersChange(filters.copy(excludeTags = it))
                    }
                }
                // These Android controls remain available after the shared iOS sections.
                LibraryFilterGroup("Status") {
                    SubjectFormRow("Favorites", onClick = {
                        onFiltersChange(filters.copy(favoriteOnly = !filters.favoriteOnly))
                    }, trailing = {
                        SubjectToggle(filters.favoriteOnly, {
                            onFiltersChange(filters.copy(favoriteOnly = it))
                        }, contentDescription = "Favorites")
                    })
                    SubjectRowSeparator()
                    LibraryChoiceRow("Status", LibraryFinishedFilter.entries, filters.finished, { it.name }) {
                        onFiltersChange(filters.copy(finished = it))
                    }
                }
                Column(Modifier.subjectPanel()) {
                    LibraryChoiceRow("Download", LibraryDownloadFilter.entries, filters.download, {
                        if (it == LibraryDownloadFilter.NotDownloaded) "Not Downloaded" else it.name
                    }) { onFiltersChange(filters.copy(download = it)) }
                }
                if (collections.isNotEmpty()) {
                    Column(Modifier.subjectPanel()) {
                        LibraryMultiSelectRow(
                            "Collections", collections.map { it.id to it.name }, filters.collectionIds
                        ) { onFiltersChange(filters.copy(collectionIds = it)) }
                    }
                }
                if (searchQuery != null) {
                    GlassFieldBar(searchQuery, onSearchQueryChange, "Search library", Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun LibraryFilterGroup(title: String, note: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SubjectFieldLabel(title)
        Column(Modifier.subjectPanel()) { content() }
        if (note != null) LibraryFilterNote(note)
    }
}

@Composable
private fun LibraryFilterNote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
}

@Composable
private fun <T> LibraryChoiceRow(
    title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        SubjectFormRow(title, value = label(selected), showsDisclosure = true, onClick = { expanded = true })
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option)) },
                    modifier = Modifier.semantics { this.selected = option == selected },
                    trailingIcon = {
                        if (option == selected) Icon(Icons.Outlined.Check, null, tint = LocalKudosTokens.current.accent)
                    },
                    onClick = { onSelect(option); expanded = false }
                )
            }
        }
    }
}

@Composable
private fun LibrarySelectableRow(title: String, selected: Boolean, onClick: () -> Unit) {
    SubjectFormRow(
        title, modifier = Modifier.semantics { this.selected = selected }, onClick = onClick,
        trailing = { if (selected) Icon(Icons.Outlined.Check, null, tint = LocalKudosTokens.current.accent) }
    )
}

@Composable
private fun LibraryWordRow(title: String, value: String, onChange: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    SubjectFormRow(title, trailing = {
        BasicTextField(
            value, onChange, singleLine = true,
            textStyle = TextStyle(color = tokens.primaryInk, fontSize = 14.5.sp),
            cursorBrush = SolidColor(tokens.accent),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.width(150.dp).semantics { contentDescription = title }
        )
    })
}

@Composable
private fun LibraryTagRow(
    title: String, works: List<SavedWork>, field: (SavedWork) -> List<String>,
    selection: Set<String>, onChange: (Set<String>) -> Unit
) {
    val options = remember(works, title) { works.flatMap(field).distinct().sorted().map { it to it } }
    LibraryMultiSelectRow(title, options, selection, onChange)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LibraryMultiSelectRow(
    title: String, options: List<Pair<String, String>>, selection: Set<String>, onChange: (Set<String>) -> Unit
) {
    var picking by remember { mutableStateOf(false) }
    SubjectFormRow(
        title, value = if (selection.isEmpty()) "Any" else "${selection.size} selected",
        showsDisclosure = true, onClick = { picking = true }
    )
    if (picking) {
        val tokens = LocalKudosTokens.current
        var query by remember { mutableStateOf("") }
        val normalized = remember(options) { options.map { it to WorkSearchIndex.normalize(it.second) } }
        val matches = remember(normalized, query) {
            val term = WorkSearchIndex.normalize(query)
            normalized.filter { term.isEmpty() || it.second.contains(term) }.map { it.first }
        }
        ModalBottomSheet(
            onDismissRequest = { picking = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = tokens.background
        ) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.headerGutter).padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(title, Modifier.weight(1f), color = tokens.primaryInk, fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold)
                    IconButton(onClick = { picking = false }) { Icon(Icons.Outlined.Check, "Done", tint = tokens.accent) }
                }
                GlassFieldBar(query, { query = it }, "Filter $title", Modifier.fillMaxWidth())
                if (options.isEmpty()) {
                    LibraryFilterNote("Your Library has no ${title.lowercase()} yet.")
                } else if (matches.isEmpty()) {
                    LibraryFilterNote("None of your options match “$query”.")
                } else {
                    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp).subjectPanel()) {
                        itemsIndexed(matches, key = { _, option -> option.first }) { index, option ->
                            if (index > 0) SubjectRowSeparator()
                            LibrarySelectableRow(option.second, option.first in selection) {
                                onChange(selection.toggled(option.first))
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun Set<String>.toggled(value: String): Set<String> = if (value in this) this - value else this + value
