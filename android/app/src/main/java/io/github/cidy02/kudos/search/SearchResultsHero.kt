package io.github.cidy02.kudos.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.search.AO3ResultSummary
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import java.text.NumberFormat

/**
 * `.Card` is the tappable summary Browse still uses.
 * `.SubjectPage` is Search's artboard 1k header: count, subject, sort, figure
 * strip, and the filter rail. The dashed Filter chip is gone — the toolbar
 * Filter button is the one way into the panel.
 */
enum class SearchHeroPresentation { Card, SubjectPage }

/**
 * AO3's own result-count line plus the filters producing it:
 *
 * ```
 * Naruto (Anime & Manga)                    1–20
 * 142,327 works
 * [Sort: Date Updated] [English] [Complete]
 * ```
 *
 * The total is the one fact a page of blurbs cannot tell you — the app knows it has
 * 20 works and how many pages there are, but "how big is this fandom" exists only in
 * AO3's heading.
 *
 * Tapping anywhere opens the filter sheet, which is what makes the chips worth their
 * height: they are the control, not a caption about it.
 */
@Composable
fun SearchResultsHero(
    summary: AO3ResultSummary,
    modifier: Modifier = Modifier,
    filterLabels: List<SummaryLabel> = emptyList(),
    /**
     * The subject's own tag category, so the heading is labelled the way its chips
     * are — a fandom, a character and a ship should not all look alike. Null leaves
     * the heading unlabelled rather than guessing.
     */
    subjectCategory: AO3ResultSummary.SubjectCategory? = null,
    onEditFilters: (() -> Unit)? = null,
    presentation: SearchHeroPresentation = SearchHeroPresentation.Card,
    currentPage: Int = 1,
    totalPages: Int = 1,
    sort: AO3SearchSort? = null,
    sortOptions: List<AO3SearchSort> = AO3SearchSort.entries,
    onSortSelected: ((AO3SearchSort) -> Unit)? = null
) {
    if (presentation == SearchHeroPresentation.SubjectPage) {
        SearchSubjectPageHeader(
            summary = summary,
            filterLabels = filterLabels,
            currentPage = currentPage,
            totalPages = totalPages,
            sort = sort,
            sortOptions = sortOptions,
            onSortSelected = onSortSelected,
            modifier = modifier
        )
        return
    }
    val count = "${NumberFormat.getIntegerInstance().format(summary.total)} " +
        if (summary.total == 1) "work" else "works"
    val spoken = buildList {
        add(count)
        summary.scope?.let { add(it) }
        summary.range?.let { add("showing ${it.first} to ${it.last}") }
        addAll(filterLabels.map { it.text })
    }.joinToString(", ")

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium,
        modifier = modifier
            .fillMaxWidth()
            .then(if (onEditFilters != null) Modifier.clickable { onEditFilters() } else Modifier)
            .semantics { contentDescription = spoken }
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                // Only tag and user lists name a subject or state a range; a plain
                // search has neither, so its card starts at the count rather than
                // padding out a title row with something invented.
                if (summary.subject != null || summary.range != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        summary.subject?.let { subject ->
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.weight(1f)
                            ) {
                                SummaryLabel.iconFor(subjectCategory)?.let {
                                    Icon(
                                        imageVector = it,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(20.dp)
                                    )
                                }
                                Text(
                                    text = subject,
                                    style = MaterialTheme.typography.titleLarge,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                        summary.range?.let { range ->
                            // Filled rather than the neutral capsules the filter chips
                            // use: it is a status, not another filter, and side by side
                            // they would otherwise read as the same kind of thing.
                            Surface(
                                color = MaterialTheme.colorScheme.primary,
                                contentColor = MaterialTheme.colorScheme.onPrimary,
                                shape = MaterialTheme.shapes.small
                            ) {
                                Text(
                                    text = "${range.first}–${range.last}",
                                    style = MaterialTheme.typography.labelMedium,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                                )
                            }
                        }
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = SummaryLabel.worksIcon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = count,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (filterLabels.isNotEmpty()) {
                val visible = filterLabels.take(VISIBLE_CHIP_LIMIT)
                val overflow = filterLabels.size - visible.size
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    visible.forEach { FilterSummaryChip(it) }
                    if (overflow > 0) FilterSummaryChip(SummaryLabel("+$overflow more"))
                }
            }
        }
    }
}

/**
 * Beyond this the chips would crowd out the works. The overflow is *counted* rather
 * than silently dropped, so the card never implies it listed everything.
 */
private const val VISIBLE_CHIP_LIMIT = 6

@Composable
private fun SearchSubjectPageHeader(
    summary: AO3ResultSummary,
    filterLabels: List<SummaryLabel>,
    currentPage: Int,
    totalPages: Int,
    sort: AO3SearchSort?,
    sortOptions: List<AO3SearchSort>,
    onSortSelected: ((AO3SearchSort) -> Unit)?,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val numberFormat = NumberFormat.getIntegerInstance()
    val palette = summary.subject?.let {
        SubjectPalette.fromHue(HomeFacts.coverHue(it), tokens.theme)
    } ?: LocalSubjectPalette.current
    val nonSort = filterLabels.filter { !it.text.startsWith("Sort: ") }
    val worksLabel = if (summary.total == 1) "work" else "works"
    val sortControl: (@Composable () -> Unit)? = if (sort == null) {
        null
    } else {
        {
            SortChip(
                sort = sort,
                options = sortOptions,
                onSelected = onSortSelected
            )
        }
    }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SubjectHeaderBlock(
            kicker = "Search results",
            title = "${numberFormat.format(summary.total)} $worksLabel",
            subtitle = summary.subject,
            palette = palette,
            trailing = sortControl
        )
        SubjectStatStrip(
            cells = listOf(
                SubjectStatCell(numberFormat.format(summary.total), "Works"),
                SubjectStatCell(nonSort.size.toString(), "Filters"),
                SubjectStatCell(numberFormat.format(totalPages), "Pages"),
                SubjectStatCell(numberFormat.format(currentPage), "Page", isHighlighted = true)
            ),
            palette = palette,
            modifier = Modifier.padding(horizontal = SubjectMetrics.panelGutter)
        )
        if (nonSort.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = SubjectMetrics.headerGutter),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                nonSort.forEach { label ->
                    SubjectChip(
                        text = label.text,
                        style = SubjectChipStyle.Tinted,
                        leadingIcon = label.icon,
                        palette = palette
                    )
                }
            }
        }
    }
}

@Composable
private fun SortChip(
    sort: AO3SearchSort,
    options: List<AO3SearchSort>,
    onSelected: ((AO3SearchSort) -> Unit)?
) {
    var open by remember { mutableStateOf(false) }
    Box {
        SubjectChip(
            text = sort.title,
            style = SubjectChipStyle.Neutral,
            trailingIcon = if (onSelected != null) Icons.Filled.KeyboardArrowDown else null,
            modifier = if (onSelected != null) {
                Modifier.clickable { open = true }
            } else {
                Modifier
            }
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option.title) },
                    onClick = {
                        open = false
                        if (option != sort) onSelected?.invoke(option)
                    }
                )
            }
        }
    }
}

@Composable
private fun FilterSummaryChip(label: SummaryLabel) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        shape = MaterialTheme.shapes.small
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            label.icon?.let {
                Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(14.dp)
                )
            }
            Text(text = label.text, style = MaterialTheme.typography.labelMedium)
        }
    }
}
