package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.works.finishedActionLabel
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Smartphone
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
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
 * Artboard 1a's tag clusters (`WorkDetailSections.swift:12`).
 * Categorized AO3 tags. Exactly one cluster — Relationships — is tinted.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WorkDetailTagSections(
    warnings: List<String>,
    fandoms: List<String>,
    relationships: List<String>,
    characters: List<String>,
    freeforms: List<String>,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    hasAo3WorkId: Boolean = true
) {
    val searchTag = LocalTagSearch.current
    val tokens = LocalKudosTokens.current

    data class TagCluster(
        val title: String,
        val tags: List<String>,
        val field: SearchSubjectField,
        val isTinted: Boolean = false
    )

    val clusters = listOf(
        TagCluster("Archive Warnings", warnings, SearchSubjectField.WARNING),
        TagCluster("Fandoms", fandoms, SearchSubjectField.FANDOM),
        TagCluster("Relationships", relationships, SearchSubjectField.RELATIONSHIP, isTinted = true),
        TagCluster("Characters", characters, SearchSubjectField.CHARACTER),
        TagCluster("Additional Tags", freeforms, SearchSubjectField.FREEFORM)
    ).filter { it.tags.isNotEmpty() }

    if (clusters.isEmpty()) {
        Text(
            text = noWorkTagsMessage(hasAo3WorkId),
            color = tokens.secondaryInk,
            fontSize = 15.sp,
            modifier = modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.panelGutter)
        )
        return
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        clusters.forEachIndexed { index, cluster ->
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SubjectFieldLabel(text = cluster.title)
                    if (cluster.tags.size > 4) {
                        Text(
                            text = "${cluster.tags.size}",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = tokens.tertiaryInk
                        )
                    }
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalArrangement = Arrangement.spacedBy(7.dp)
                ) {
                    cluster.tags.forEach { tag ->
                        SubjectChip(
                            text = tag,
                            style = if (cluster.isTinted) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                            palette = palette,
                            modifier = Modifier.clickable(onClickLabel = "search AO3 for works with this tag") {
                                searchTag(cluster.field, tag)
                            }
                        )
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
 * Artboard 1a's Series section (`WorkDetailOverviewSections.swift:145`).
 */
@Composable
fun WorkDetailSeriesSection(
    seriesTitle: String,
    seriesPosition: Int,
    seriesUrl: String,
    queuingSeries: Boolean,
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

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        SubjectFieldLabel(text = "SERIES")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .subjectPanel(cornerRadius = 14.dp)
        ) {
            val partText = if (seriesPosition > 0) "Part $seriesPosition" else ""
            SubjectFormRow(
                label = seriesTitle,
                value = partText
            )

            localWorks.forEach { work ->
                val obscured = isObscured(work)
                SubjectRowSeparator(inset = 14.dp)
                SubjectFormRow(
                    label = if (obscured) "Hidden mature work" else
                        (if (work.seriesPosition > 0) "${work.seriesPosition}. " else "") + work.title,
                    onClick = { if (obscured) onReveal(work) else onOpenLocalWork(work.id) }
                )
            }

            if (seriesUrl.isNotBlank()) {
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

                SubjectRowSeparator(inset = 14.dp)
                SubjectFormRow(
                    label = "View Full Series on AO3",
                    value = null,
                    showsDisclosure = true,
                    onClick = { onOpenSeries(seriesUrl) }
                )
            }
        }

        Text(
            text = "When you download more works from this series, they will appear here.",
            fontSize = 12.sp,
            color = tokens.secondaryInk
        )
    }
}

/**
 * Artboard 1a's My copy row (`WorkDetailFactsSections.swift:252`).
 * Smartphone icon, "My copy", summary subtitle, and chevron into local details sheet.
 */
@Composable
fun WorkDetailMyCopyRow(
    summary: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
            .subjectPanel(cornerRadius = 14.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .semantics { contentDescription = "My copy: $summary" }
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.Smartphone,
                contentDescription = null,
                tint = tokens.secondaryInk,
                modifier = Modifier.size(20.dp)
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = "My copy",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = tokens.primaryInk,
                    maxLines = 1
                )
                Text(
                    text = summary,
                    fontSize = 12.sp,
                    color = tokens.secondaryInk,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = tokens.secondaryInk.copy(alpha = 0.7f),
                modifier = Modifier.size(16.dp)
            )
        }
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
