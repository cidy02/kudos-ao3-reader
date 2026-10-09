package io.github.cidy02.kudos.author

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.search.FilterGroup
import io.github.cidy02.kudos.ui.subject.*

internal const val WorksSortFooter = "AO3 applies this choice to all matching works, not only the page you can see."

/** Swift refineActiveCount counts groups, and intentionally does not count Include Not Rated. */
internal val io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters.activeCountForRefine: Int
    get() = listOf(
        rating != io.github.cidy02.kudos.network.ao3.search.AO3Rating.ANY,
        warnings.isNotEmpty(), excludedWarnings.isNotEmpty(), categories.isNotEmpty(), excludedCategories.isNotEmpty(),
        completion != io.github.cidy02.kudos.network.ao3.search.AO3Completion.ANY,
        chapterCount != io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount.ANY,
        language != io.github.cidy02.kudos.network.ao3.search.AO3Language.ANY,
        wordsFrom.isNotBlank() || wordsTo.isNotBlank()
    ).count { it } + listOf(fandom, characters, relationships, additionalTags, excludedFandoms,
        excludedCharacters, excludedRelationships, excludedAdditionalTags).count { it.isNotBlank() }

/** This half is a draft. The rest of SearchFilterSheet remains a live local refine. */
@Composable
internal fun AuthorWorksSortFields(draft: AO3AuthorWorksSort, onChange: (AO3AuthorWorksSort) -> Unit) {
    val tokens = LocalKudosTokens.current
    var columnsOpen by remember { mutableStateOf(false) }
    FilterGroup {
        Box {
            val named = Modifier.semantics { contentDescription = "Sort by, ${draft.column.label}, 9 fields" }
            if (isAccessibilityFontScale()) {
                SubjectFormRow("Sort by", value = "${draft.column.label}, 9 fields", valueMaxLines = Int.MAX_VALUE,
                    onClick = { columnsOpen = true }, showsDisclosure = true, modifier = named)
            } else SubjectFormRow("Sort by", onClick = { columnsOpen = true }, showsDisclosure = true,
                modifier = named, trailing = {
                    Column {
                        Text(draft.column.label, color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                        Text("9 fields", color = tokens.tertiaryInk, fontSize = 12.sp, lineHeight = 17.sp)
                    }
                })
            DropdownMenu(columnsOpen, onDismissRequest = { columnsOpen = false }) {
                AO3AuthorWorksSortColumn.entries.forEach { column ->
                    DropdownMenuItem(text = {
                        Text(column.label, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                    }, modifier = Modifier.semantics { selected = column == draft.column }, onClick = {
                        onChange(draft.select(column)); columnsOpen = false
                    }, trailingIcon = {
                        if (column == draft.column) Icon(Icons.Outlined.Check, null, tint = tokens.accent)
                    })
                }
            }
        }
        SubjectRowSeparator()
        SubjectFormRow("Direction")
        if (isAccessibilityFontScale()) {
            SortChips(AO3AuthorWorksSortDirection.entries, draft.direction, { it.label }) {
                onChange(draft.copy(direction = it))
            }
        } else {
            SubjectSegmentedControl(AO3AuthorWorksSortDirection.entries, draft.direction,
                { onChange(draft.copy(direction = it)) }, { it.label },
                modifier = Modifier.padding(12.dp), contentDescription = "Direction")
        }
    }
    FilterGroup("Completion", WorksSortFooter) {
        SortChips(AO3AuthorWorksCompletion.entries, draft.completion, { it.label }) {
            onChange(draft.copy(completion = it))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> SortChips(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    FlowRow(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            SubjectChip(label(option), style = SubjectChipStyle.Pill(option == selected),
                palette = LocalKudosTokens.current.scopePalette,
                maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 1,
                modifier = Modifier.clickable { onSelect(option) }.semantics { this.selected = option == selected })
        }
    }
}
