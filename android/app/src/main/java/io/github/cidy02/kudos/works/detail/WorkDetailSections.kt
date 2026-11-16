package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.works.finishedActionLabel
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.net.URLDecoder
import java.net.URLEncoder
import java.text.NumberFormat

/**
 * Version E's Summary section (`WorkDetailOverviewSections.swift`): sans-serif body clamped to
 * 3 lines with `More` / `Less` shown only when the 3-line layout actually truncates, plus an
 * inline `Notes` button opening the work on AO3 when `ao3WorkId != null`.
 */
@Composable
fun WorkDetailSummarySection(
    summary: String,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    ao3WorkId: Long? = null,
    onOpenNotes: (() -> Unit)? = null
) {
    if (summary.isBlank()) return
    val tokens = LocalKudosTokens.current
    val uriHandler = LocalUriHandler.current
    val fontScale = LocalDensity.current.fontScale
    var expanded by remember(summary) { mutableStateOf(false) }
    var truncated by remember(summary, fontScale) { mutableStateOf(false) }
    val notesAction = onOpenNotes ?: ao3WorkId?.let { id ->
        { uriHandler.openUri("https://archiveofourown.org/works/$id") }
    }

    Column(
        modifier = modifier.fillMaxWidth()
    ) {
        SectionRuleHeader(title = "Summary")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = SubjectMetrics.panelGutter)
                .padding(top = 6.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = summary,
                fontSize = 15.5.sp,
                lineHeight = 22.sp,
                color = tokens.primaryInk,
                maxLines = if (expanded) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis,
                onTextLayout = { result ->
                    if (!expanded) {
                        truncated = result.hasVisualOverflow
                    }
                },
                modifier = Modifier.animateContentSize()
            )
            if (truncated || notesAction != null) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (truncated) {
                        Box(
                            modifier = Modifier
                                .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                                .clickable(
                                    role = Role.Button,
                                    onClickLabel = if (expanded) "Collapse summary" else "Expand summary"
                                ) { expanded = !expanded }
                                .padding(horizontal = 2.dp),
                            contentAlignment = Alignment.CenterStart
                        ) {
                            Text(
                                text = if (expanded) "Less" else "More",
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = palette.controlInk
                            )
                        }
                    }
                    if (truncated && notesAction != null) {
                        Text(
                            text = "·",
                            fontSize = 15.5.sp,
                            color = tokens.secondaryInk,
                            modifier = Modifier.clearAndSetSemantics {}
                        )
                    }
                    if (notesAction != null) {
                        Box(
                            modifier = Modifier
                                .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
                                .clickable(
                                    role = Role.Button,
                                    onClickLabel = "Opens this work on AO3, where the author's notes are"
                                ) { notesAction() }
                                .padding(horizontal = 2.dp),
                            contentAlignment = Alignment.CenterStart
                        ) {
                            Text(
                                text = "Notes",
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.Medium,
                                color = palette.controlInk
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Pure Version E disclosure digest helpers (`WorkDetailOverviewSections.swift`).
 */
object WorkDetailDisclosure {
    fun tagsDigest(relationships: Int, characters: Int, additional: Int): String {
        val parts = buildList {
            if (relationships > 0) {
                add("$relationships relationship${if (relationships == 1) "" else "s"}")
            }
            if (characters > 0) {
                add("$characters character${if (characters == 1) "" else "s"}")
            }
            if (additional > 0) {
                add("$additional more")
            }
        }
        return if (parts.isEmpty()) "No AO3 tags" else parts.joinToString(" · ")
    }

    /** Device only knows downloaded parts, so Series claims no total work or word count. */
    fun seriesDigest(title: String, position: Int): String =
        if (position > 0) "$title · part $position" else title
}

/** Round-trip tag link encoding matching iOS `WorkDetailTagLink`. */
object WorkDetailTagLink {
    const val SCHEME = "kudos-tag"

    fun url(tag: String): String =
        "$SCHEME:${URLEncoder.encode(tag, "UTF-8").replace("+", "%20")}"

    fun tagFromUrl(url: String): String? {
        if (!url.startsWith("$SCHEME:")) return null
        return runCatching { URLDecoder.decode(url.removePrefix("$SCHEME:"), "UTF-8") }.getOrNull()
    }

    fun joinedText(tags: List<String>): String = tags.joinToString(", ")
}

@Composable
fun WorkDetailDisclosureHeader(
    title: String,
    digest: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val accessible = isAccessibilityFontScale()
    Column(modifier = modifier.fillMaxWidth()) {
        SubjectRowSeparator(inset = 0.dp)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 52.dp)
                .clickable(
                    role = Role.Button,
                    onClickLabel = if (expanded) "Collapse $title" else "Expand $title",
                    onClick = onToggle
                )
                .padding(vertical = 10.dp)
                .semantics(mergeDescendants = true) {
                    heading()
                    contentDescription = "$title, $digest"
                    stateDescription = if (expanded) "Expanded" else "Collapsed"
                },
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = tokens.primaryInk
                )
                Text(
                    text = digest,
                    fontSize = 12.5.sp,
                    color = tokens.secondaryInk,
                    maxLines = if (accessible) Int.MAX_VALUE else 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = tokens.secondaryInk,
                modifier = Modifier
                    .size(18.dp)
                    .rotate(if (expanded) 180f else 0f)
            )
        }
    }
}

/**
 * Version E's Tags section (`WorkDetailSections.swift`): collapsible with persisted app-wide
 * state, opening to AO3-style rows (grey category label column + comma-separated inline links).
 */
@Composable
fun WorkDetailTagSections(
    warnings: List<String>,
    fandoms: List<String>,
    relationships: List<String>,
    characters: List<String>,
    freeforms: List<String>,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    hasAo3WorkId: Boolean = true,
    flatTags: List<String> = emptyList(),
    expanded: Boolean = true,
    onToggleExpanded: (() -> Unit)? = null
) {
    val searchTag = LocalTagSearch.current
    val tokens = LocalKudosTokens.current

    data class TagGroup(
        val title: String,
        val tags: List<String>,
        val field: SearchSubjectField
    )

    val categorized = listOf(
        TagGroup("Relationships", relationships, SearchSubjectField.RELATIONSHIP),
        TagGroup("Characters", characters, SearchSubjectField.CHARACTER),
        TagGroup("Additional tags", freeforms, SearchSubjectField.FREEFORM),
        TagGroup("Warnings", warnings, SearchSubjectField.WARNING),
        TagGroup("Fandoms", fandoms, SearchSubjectField.FANDOM)
    ).filter { it.tags.isNotEmpty() }

    val groups = when {
        categorized.isNotEmpty() -> categorized
        flatTags.isNotEmpty() -> listOf(TagGroup("Tags", flatTags, SearchSubjectField.FREEFORM))
        else -> emptyList()
    }

    val baseDigest = WorkDetailDisclosure.tagsDigest(
        relationships = relationships.size,
        characters = characters.size,
        additional = freeforms.size
    )
    val totalTags = groups.sumOf { it.tags.size }
    val digest = if (baseDigest == "No AO3 tags" && totalTags > 0) {
        "$totalTags tag${if (totalTags == 1) "" else "s"}"
    } else {
        baseDigest
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
    ) {
        if (onToggleExpanded != null) {
            WorkDetailDisclosureHeader(
                title = "Tags",
                digest = digest,
                expanded = expanded,
                onToggle = onToggleExpanded
            )
        }

        if (expanded) {
            if (groups.isEmpty()) {
                Text(
                    text = noWorkTagsMessage(hasAo3WorkId),
                    color = tokens.secondaryInk,
                    fontSize = 15.sp,
                    modifier = Modifier.padding(top = 6.dp, bottom = 8.dp)
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = if (onToggleExpanded != null) 2.dp else 0.dp, bottom = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    groups.forEach { group ->
                        val annotated = buildAnnotatedString {
                            val linkStyles = TextLinkStyles(
                                style = SpanStyle(
                                    color = palette.controlInk,
                                    fontWeight = FontWeight.Normal
                                )
                            )
                            group.tags.forEachIndexed { index, tag ->
                                if (index > 0) append(", ")
                                withLink(
                                    LinkAnnotation.Clickable(
                                        tag = WorkDetailTagLink.url(tag),
                                        styles = linkStyles
                                    ) {
                                        searchTag(group.field, tag)
                                    }
                                ) {
                                    append(tag)
                                }
                            }
                        }

                        // The group's name on its own line, its tags below at full width (owner,
                        // 2026-11-16: "below - not next to - their header"), as on iOS.
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = group.title,
                                fontSize = 13.sp,
                                color = tokens.secondaryInk,
                                modifier = Modifier.semantics { heading() }
                            )
                            Text(
                                text = annotated,
                                fontSize = 15.sp,
                                lineHeight = 21.sp,
                                color = tokens.secondaryInk
                            )
                        }
                    }
                }
            }
        }
    }
}

internal fun noWorkTagsMessage(hasAo3WorkId: Boolean): String = if (hasAo3WorkId) {
    "AO3 hasn't provided tags for this work yet."
} else {
    "This imported work isn't linked to AO3, so you won't see AO3 tags here."
}

/**
 * Board 19's single Comments row (`WorkDetailSections.swift`): opens the native Comments screen
 * (which provides By Chapter filtering and Write a comment without loading comments up front).
 */
@Composable
fun WorkDetailCommentsSection(
    commentsCount: Int?,
    modifier: Modifier = Modifier,
    onComments: () -> Unit
) {
    val countText = commentsCount?.let { NumberFormat.getIntegerInstance(java.util.Locale.US).format(it) }.orEmpty()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
            .subjectPanel(cornerRadius = SubjectMetrics.panelRadius)
    ) {
        SubjectFormRow(
            label = "Comments",
            value = countText,
            showsDisclosure = true,
            onClick = onComments,
            modifier = Modifier.semantics {
                contentDescription = if (countText.isEmpty()) {
                    "Comments, comments load only when you open them"
                } else {
                    "Comments, $countText, comments load only when you open them"
                }
            }
        )
    }
}

/** Retained for [io.github.cidy02.kudos.reader.ReaderFanMenuUiTest]. */
@Composable
fun WorkDetailPageActions(
    isFinished: Boolean,
    hasSourceUrl: Boolean,
    isWorking: Boolean,
    modifier: Modifier = Modifier,
    onToggleFinished: () -> Unit,
    onOpenAo3: () -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        WorkDetailOutlineButton(
            // The action, as iOS `WorkActionLabels.finished`. It said "Finished", which read as
            // a state on a button that takes the work back out of Finished.
            title = finishedActionLabel(isFinished),
            enabled = !isWorking,
            onClick = onToggleFinished,
            modifier = Modifier.weight(1f)
        )
        if (hasSourceUrl) {
            WorkDetailOutlineButton(
                title = "Open on AO3",
                enabled = true,
                onClick = onOpenAo3,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/**
 * 15sp medium outline button matching iOS `WorkDetailOutlineButton` (`WorkDetailFactsSections.swift:224`).
 */
@Composable
fun WorkDetailOutlineButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(12.dp)

    Box(
        modifier = modifier
            .clip(shape)
            .border(1.dp, tokens.glassStroke(0.18), shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 13.dp, horizontal = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = title,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            color = if (enabled) tokens.primaryInk else tokens.tertiaryInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * Version E's collapsible Series section (`WorkDetailOverviewSections.swift`).
 * Digest claims only `<series> · part N`; the device lists only downloaded works it knows.
 */
@Composable
fun WorkDetailSeriesSection(
    seriesTitle: String,
    seriesPosition: Int,
    seriesUrl: String,
    queuingSeries: Boolean,
    currentWorkTitle: String = "",
    hasLocalWork: Boolean = true,
    expanded: Boolean = true,
    onToggleExpanded: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    onDownloadSeries: () -> Unit,
    onOpenSeries: (String) -> Unit,
    localWorks: List<SavedWork> = emptyList(),
    isObscured: (SavedWork) -> Boolean = { false },
    onOpenLocalWork: (String) -> Unit = {},
    onReveal: (SavedWork) -> Unit = {}
) {
    if (seriesTitle.isBlank()) return
    val tokens = LocalKudosTokens.current

    data class SeriesEntry(
        val id: String,
        val position: Int,
        val title: String,
        val work: SavedWork?
    )

    val sortedEntries = remember(seriesWorksKey(localWorks), seriesPosition, currentWorkTitle) {
        val raw = buildList {
            localWorks.forEach { add(SeriesEntry(it.id, it.seriesPosition, it.title, it)) }
            add(SeriesEntry("current", seriesPosition, currentWorkTitle.ifBlank { seriesTitle }, null))
        }
        raw.withIndex()
            .sortedWith(
                compareBy<IndexedValue<SeriesEntry>>(
                    { if (it.value.position > 0) it.value.position else Int.MAX_VALUE },
                    { it.index }
                )
            )
            .map { it.value }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
    ) {
        if (onToggleExpanded != null) {
            WorkDetailDisclosureHeader(
                title = "Series",
                digest = WorkDetailDisclosure.seriesDigest(seriesTitle, seriesPosition),
                expanded = expanded,
                onToggle = onToggleExpanded
            )
        }

        if (expanded) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp, bottom = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .subjectPanel(cornerRadius = 14.dp)
                ) {
                    SubjectFormRow(
                        label = seriesTitle,
                        value = if (seriesPosition > 0) "Part $seriesPosition" else null,
                        showsDisclosure = seriesUrl.isNotBlank(),
                        onClick = if (seriesUrl.isNotBlank()) {
                            { onOpenSeries(seriesUrl) }
                        } else null
                    )

                    sortedEntries.forEach { entry ->
                        SubjectRowSeparator(inset = 14.dp)
                        val numberPrefix = if (entry.position > 0) "${entry.position}. " else ""
                        val other = entry.work
                        if (other == null) {
                            SubjectFormRow(
                                label = numberPrefix + entry.title,
                                value = "This work"
                            )
                        } else {
                            val obscured = isObscured(other)
                            SubjectFormRow(
                                label = if (obscured) "Hidden mature work" else numberPrefix + other.title,
                                showsDisclosure = !obscured,
                                onClick = { if (obscured) onReveal(other) else onOpenLocalWork(other.id) }
                            )
                        }
                    }

                    if (seriesUrl.isNotBlank()) {
                        if (hasLocalWork) {
                            SubjectRowSeparator(inset = 14.dp)
                            SubjectFormRow(
                                label = if (queuingSeries) "Fetching series…" else "Download Whole Series",
                                value = null,
                                showsDisclosure = false,
                                onClick = onDownloadSeries,
                                trailing = if (queuingSeries) {
                                    { CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp) }
                                } else null
                            )
                        }

                        SubjectRowSeparator(inset = 14.dp)
                        SubjectFormRow(
                            label = "View Full Series on AO3",
                            value = null,
                            showsDisclosure = true,
                            onClick = { onOpenSeries(seriesUrl) }
                        )
                    }
                }

                if (hasLocalWork && localWorks.isEmpty()) {
                    Text(
                        text = "When you download more works from this series, they will appear here.",
                        fontSize = 12.sp,
                        color = tokens.secondaryInk
                    )
                }
            }
        }
    }
}

private fun seriesWorksKey(works: List<SavedWork>): List<String> =
    works.map { "${it.id}:${it.seriesPosition}:${it.title}" }

/**
 * Version E's collapsible My copy section (`WorkDetailFactsSections.swift`):
 * two-column compact cells (single-column at accessibility sizes) without the repeated Progress
 * row, plus `"Storage and History"` opening the My copy detail sheet.
 */
@Composable
fun WorkDetailMyCopySection(
    cells: List<WorkDetailPresentation.MyCopyRow>,
    summary: String,
    palette: SubjectPalette,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onCellAction: (WorkDetailPresentation.MyCopyKind) -> Unit,
    onOpenSheet: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val accessible = isAccessibilityFontScale()
    val storageCell = WorkDetailPresentation.MyCopyRow(
        kind = WorkDetailPresentation.MyCopyKind.File,
        label = "Storage and History",
        value = "View details",
        action = null
    )
    val allItems = cells.map { it to { onCellAction(it.kind) } } + listOf(storageCell to onOpenSheet)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
    ) {
        WorkDetailDisclosureHeader(
            title = "My copy",
            digest = "Private to this device",
            expanded = expanded,
            onToggle = onToggleExpanded
        )

        if (expanded) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp, bottom = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (accessible) {
                    allItems.forEachIndexed { index, (cell, action) ->
                        val isStorage = index == allItems.lastIndex
                        WorkDetailMyCopyCell(
                            cell = cell,
                            palette = palette,
                            accessible = true,
                            tokensFill = tokens.glassFill(0.09),
                            primaryInk = tokens.primaryInk,
                            secondaryInk = tokens.secondaryInk,
                            onClick = if (isStorage || cell.action != null) action else null,
                            accessibilityOverride = if (isStorage) "Storage and History, $summary" else null
                        )
                    }
                } else {
                    allItems.chunked(2).forEach { pair ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            pair.forEach { (cell, action) ->
                                val isStorage = cell === storageCell
                                WorkDetailMyCopyCell(
                                    cell = cell,
                                    palette = palette,
                                    accessible = false,
                                    tokensFill = tokens.glassFill(0.09),
                                    primaryInk = tokens.primaryInk,
                                    secondaryInk = tokens.secondaryInk,
                                    onClick = if (isStorage || cell.action != null) action else null,
                                    accessibilityOverride = if (isStorage) "Storage and History, $summary" else null,
                                    modifier = Modifier.weight(1f)
                                )
                            }
                            if (pair.size == 1) {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WorkDetailMyCopyCell(
    cell: WorkDetailPresentation.MyCopyRow,
    palette: SubjectPalette,
    accessible: Boolean,
    tokensFill: Color,
    primaryInk: Color,
    secondaryInk: Color,
    onClick: (() -> Unit)?,
    accessibilityOverride: String?,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(12.dp)
    val baseModifier = modifier
        .fillMaxWidth()
        .defaultMinSize(minHeight = 56.dp)
        .clip(shape)
        .background(tokensFill, shape)
        .then(
            if (onClick != null) {
                Modifier.clickable(
                    role = Role.Button,
                    onClickLabel = cell.action?.let { "${it.title} ${cell.label.lowercase()}" },
                    onClick = onClick
                )
            } else {
                Modifier
            }
        )
        .padding(horizontal = 12.dp, vertical = 8.dp)
        .let { mod ->
            if (accessibilityOverride != null) {
                mod.clearAndSetSemantics { contentDescription = accessibilityOverride }
            } else {
                mod.semantics(mergeDescendants = true) {}
            }
        }

    Column(
        modifier = baseModifier,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = cell.label,
                fontSize = 12.sp,
                color = secondaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            cell.action?.let { action ->
                Text(
                    text = action.title,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.controlInk,
                    maxLines = 1
                )
            }
        }
        Text(
            text = cell.value,
            fontSize = 14.5.sp,
            color = primaryInk,
            maxLines = if (accessible) Int.MAX_VALUE else 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * iOS `WorkDetailComponents.myCopySummary`: the line under "My copy". Saved for Later is a
 * queue like any other and counts as one; Android's count had left it out.
 */
internal fun myCopySummary(isDownloaded: Boolean, queueCount: Int, collectionCount: Int, tagCount: Int): String {
    fun counted(count: Int, noun: String) = "$count " + if (count == 1) noun else "${noun}s"
    val segments = listOfNotNull(
        "Downloaded".takeIf { isDownloaded },
        counted(queueCount, "queue").takeIf { queueCount > 0 },
        counted(collectionCount, "collection").takeIf { collectionCount > 0 },
        counted(tagCount, "tag").takeIf { tagCount > 0 }
    )
    return segments.joinToString(" · ").ifEmpty { "You haven't saved anything on this device yet" }
}
