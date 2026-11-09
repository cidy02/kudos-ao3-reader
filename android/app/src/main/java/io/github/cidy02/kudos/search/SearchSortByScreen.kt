package io.github.cidy02.kudos.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.FormatListBulleted
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRank
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRankOrder
import io.github.cidy02.kudos.network.ao3.search.SearchSortDirections
import io.github.cidy02.kudos.network.ao3.search.SearchWaysToFind
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale

/**
 * Filters › Sort By. Ways to Find and the AO3 column take effect when the search runs.
 * The rank below applies to works already loaded and does not ask AO3 for a page.
 */
@Composable
internal fun SearchSortByPage(
    filters: AO3SearchFilters,
    onFiltersChange: (AO3SearchFilters) -> Unit,
    allowsRelevanceSort: Boolean,
    ranksLoadedWorks: Boolean
) {
    val ranking = filters.loadedWorksRanking
    val columns = AO3SearchSort.entries.filter { allowsRelevanceSort || it != AO3SearchSort.RELEVANCE }
    val defaultSort = if (allowsRelevanceSort) AO3SearchSort.RELEVANCE else AO3SearchSort.DATE_UPDATED
    val preset = SearchWaysToFind.applied(filters)
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        FilterGroup("Ways to Find") {
            SearchWaysToFind.entries.forEachIndexed { index, way ->
                if (index > 0) SubjectRowSeparator()
                SortCheckRow(way.title, way.subtitle, iconFor(way), way.isApplied(filters)) {
                    onFiltersChange(SearchWaysToFind.toggle(way, filters, defaultSort))
                }
            }
        }
        FilterGroup(
            "Load from AO3 By",
            note = preset?.let { "${it.title} adds \u201C${it.queryNote}\u201D to the search AO3 runs." }
        ) {
            columns.forEachIndexed { index, column ->
                if (index > 0) SubjectRowSeparator()
                SortCheckRow(column.title, null, iconFor(column), filters.sort == column) {
                    if (filters.sort != column) {
                        onFiltersChange(filters.copy(sort = column, sortDirection = column.naturalDirection))
                    }
                }
            }
        }
        if (ranksLoadedWorks) {
            FilterGroup(
                "Then Rank Loaded Works By",
                note = "Ranks only the works already loaded from AO3. Kudos never loads extra pages to rank."
            ) {
                LoadedWorksRank.entries.forEachIndexed { index, rank ->
                    if (index > 0) SubjectRowSeparator()
                    SortCheckRow(rank.title, rank.subtitle, iconFor(rank), ranking.rank == rank) {
                        onFiltersChange(ranking.select(rank, filters))
                    }
                }
            }
            FilterGroup("Ranking") {
                SortToggleRow(
                    "Rank Cautiously",
                    "Works with few readers need more kudos to rank high",
                    ranking.ranksCautiously,
                    enabled = ranking.isActive
                ) { onFiltersChange(filters.copy(loadedWorksRanking = ranking.copy(ranksCautiously = it))) }
                SubjectRowSeparator()
                SortToggleRow(
                    "Set Aside Unusual Stats",
                    "More kudos than hits, or thousands of kudos and almost no bookmarks",
                    ranking.setsAsideUnusual,
                    enabled = ranking.isActive
                ) { onFiltersChange(filters.copy(loadedWorksRanking = ranking.copy(setsAsideUnusual = it))) }
                SubjectRowSeparator()
                MinimumHitsRow(filters, onFiltersChange)
                SubjectRowSeparator()
                SortToggleRow(
                    "Show the signal on each result",
                    null,
                    ranking.showsSignal,
                    enabled = ranking.isActive
                ) { onFiltersChange(filters.copy(loadedWorksRanking = ranking.copy(showsSignal = it))) }
            }
        } else {
            FilterGroup {
                MinimumHitsRow(filters, onFiltersChange)
            }
        }
        if (ranksLoadedWorks && ranking.isActive) {
            FilterGroup {
                OrderRow(LoadedWorksRankOrder.entries, ranking.order, { it.title }) {
                    onFiltersChange(filters.copy(loadedWorksRanking = ranking.copy(order = it)))
                }
            }
        } else if (filters.sort != AO3SearchSort.RELEVANCE) {
            val directions = SearchSortDirections.forSort(filters.sort)
            FilterGroup {
                OrderRow(directions, filters.sortDirection, { SearchSortDirections.title(it, filters.sort) }) {
                    onFiltersChange(filters.copy(sortDirection = it))
                }
            }
        }
    }
}

@Composable
private fun MinimumHitsRow(filters: AO3SearchFilters, onFiltersChange: (AO3SearchFilters) -> Unit) {
    val options = SearchWaysToFind.minimumHitsOptions(filters.hitsFrom)
    val selected = filters.hitsFrom.trim().let { if (it in options) it else filters.hitsFrom }
    SortMenuRow(
        title = "Leave Out Works Under",
        subtitle = "Sent to AO3 with the search, so pages stay full",
        value = SearchWaysToFind.minimumHitsTitle(selected),
        options = options,
        selected = selected,
        label = { SearchWaysToFind.minimumHitsTitle(it) }
    ) { onFiltersChange(filters.copy(hitsFrom = it)) }
}

@Composable
private fun <T> OrderRow(options: List<T>, selected: T, title: (T) -> String, onSelect: (T) -> Unit) {
    if (isAccessibilityFontScale()) {
        SortMenuRow("Order", null, title(selected), options, selected, title, onSelect)
    } else {
        SubjectFormRow("Order", trailing = {
            SubjectSegmentedControl(
                options, selected, onSelect, title,
                modifier = Modifier.fillMaxWidth(0.75f), contentDescription = "Order"
            )
        })
    }
}

@Composable
private fun SortCheckRow(
    title: String,
    subtitle: String?,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics { this.selected = selected }
            .padding(horizontal = 13.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
            if (subtitle != null) {
                Text(subtitle, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
        if (selected) {
            Icon(Icons.Outlined.Check, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun SortToggleRow(
    title: String,
    subtitle: String?,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
            if (subtitle != null) {
                Text(subtitle, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
        SubjectToggle(checked, onCheckedChange, enabled = enabled, contentDescription = title)
    }
}

@Composable
private fun <T> SortMenuRow(
    title: String,
    subtitle: String?,
    value: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { expanded = true }
                .padding(horizontal = 13.dp, vertical = 11.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                if (subtitle != null) {
                    Text(subtitle, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 16.sp)
                }
            }
            Text(value, color = tokens.accent, fontSize = 14.5.sp)
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option)) },
                    modifier = Modifier.semantics { this.selected = option == selected },
                    trailingIcon = {
                        if (option == selected) Icon(Icons.Outlined.Check, null, tint = tokens.accent)
                    },
                    onClick = { onSelect(option); expanded = false }
                )
            }
        }
    }
}

private fun iconFor(way: SearchWaysToFind): ImageVector = when (way) {
    SearchWaysToFind.READER_FAVOURITES -> Icons.Outlined.FavoriteBorder
    SearchWaysToFind.NEW_AND_LOVED -> Icons.Outlined.Event
    SearchWaysToFind.HIDDEN_GEMS -> Icons.Outlined.AutoAwesome
    SearchWaysToFind.ACTIVE_WIPS -> Icons.Outlined.Schedule
}

private fun iconFor(column: AO3SearchSort): ImageVector = when (column) {
    AO3SearchSort.RELEVANCE -> Icons.Outlined.AutoAwesome
    AO3SearchSort.DATE_UPDATED -> Icons.Outlined.Schedule
    AO3SearchSort.DATE_POSTED -> Icons.Outlined.Event
    AO3SearchSort.TITLE -> Icons.Outlined.TextFields
    AO3SearchSort.CREATOR -> Icons.Outlined.Person
    AO3SearchSort.WORDS -> Icons.Outlined.TextFields
    AO3SearchSort.HITS -> Icons.Outlined.Visibility
    AO3SearchSort.KUDOS -> Icons.Outlined.FavoriteBorder
    AO3SearchSort.COMMENTS -> Icons.Outlined.ChatBubbleOutline
    AO3SearchSort.BOOKMARKS -> Icons.Outlined.BookmarkBorder
}

private fun iconFor(rank: LoadedWorksRank): ImageVector = when (rank) {
    LoadedWorksRank.AO3_ORDER -> Icons.AutoMirrored.Outlined.FormatListBulleted
    LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED -> Icons.Outlined.FavoriteBorder
    LoadedWorksRank.SAVES_PER_KUDOS -> Icons.Outlined.BookmarkBorder
    LoadedWorksRank.COMMENTS_PER_KUDOS -> Icons.Outlined.ChatBubbleOutline
    LoadedWorksRank.MOMENTUM -> Icons.Filled.SwapVert
    LoadedWorksRank.KUDOS_PER_THOUSAND_WORDS -> Icons.Outlined.TextFields
}
