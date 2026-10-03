package io.github.cidy02.kudos.works.detail

import android.net.Uri
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Schedule
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.text.NumberFormat

/**
 * Artboard 1a's Summary section (`WorkDetailOverviewSections.swift:33`).
 * 16sp serif font, 25.6sp line-height (CSS 1.6), and 8-line collapse.
 */
@Composable
fun WorkDetailSummarySection(
    summary: String,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    if (summary.isBlank()) return
    val tokens = LocalKudosTokens.current
    var expanded by remember { mutableStateOf(false) }
    val collapses = summary.length > 600

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = summary,
            fontFamily = FontFamily.Serif,
            fontSize = 16.sp,
            lineHeight = 25.6.sp,
            color = tokens.primaryInk.copy(alpha = 0.82f),
            maxLines = if (collapses && !expanded) 8 else Int.MAX_VALUE,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.animateContentSize()
        )
        if (collapses) {
            Text(
                text = if (expanded) "Show Less" else "Show More",
                fontSize = 14.5.sp,
                fontWeight = FontWeight.Medium,
                color = palette.accent,
                modifier = Modifier
                    .semantics { contentDescription = if (expanded) "Show less summary" else "Show more summary" }
                    .clickable { expanded = !expanded }
            )
        }
    }
}

/**
 * Artboard 1a's ON AO3 chips (`WorkDetailAO3Actions.swift:15`).
 * Four archive actions: Kudos, Subscribe, Bookmark, Mark for Later.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WorkDetailAo3ActionChips(
    kudosCount: Int?,
    hasGivenKudos: Boolean,
    isSubscribed: Boolean?,
    isBookmarked: Boolean,
    isWorking: Boolean,
    palette: SubjectPalette,
    onKudos: () -> Unit,
    onSubscribe: () -> Unit,
    onBookmark: () -> Unit,
    onMarkForLater: () -> Unit,
    modifier: Modifier = Modifier
) {
    val kudosLabel = if (kudosCount != null && kudosCount > 0) {
        "Kudos · ${HomeFacts.compactFigure(kudosCount)}"
    } else {
        "Kudos"
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        SubjectFieldLabel(text = "ON AO3")

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SubjectChip(
                text = kudosLabel,
                style = if (hasGivenKudos) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                leadingIcon = if (hasGivenKudos) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder,
                palette = palette,
                modifier = Modifier.clickable(enabled = !isWorking, onClick = onKudos)
            )

            val subscribed = isSubscribed == true
            SubjectChip(
                text = if (subscribed) "Subscribed" else "Subscribe",
                style = if (subscribed) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                leadingIcon = if (subscribed) Icons.Outlined.NotificationsOff else Icons.Outlined.Notifications,
                palette = palette,
                modifier = Modifier.clickable(enabled = !isWorking, onClick = onSubscribe)
            )

            SubjectChip(
                text = if (isBookmarked) "Edit Bookmark" else "Bookmark",
                style = if (isBookmarked) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                leadingIcon = if (isBookmarked) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,
                palette = palette,
                modifier = Modifier.clickable(enabled = !isWorking, onClick = onBookmark)
            )

            SubjectChip(
                text = "Mark for Later",
                style = SubjectChipStyle.Neutral,
                leadingIcon = Icons.Outlined.Schedule,
                palette = palette,
                modifier = Modifier.clickable(enabled = !isWorking, onClick = onMarkForLater)
            )
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
    modifier: Modifier = Modifier
) {
    val uriHandler = LocalUriHandler.current
    val tokens = LocalKudosTokens.current

    data class TagCluster(val title: String, val tags: List<String>, val isTinted: Boolean = false)

    val clusters = listOf(
        TagCluster("Archive Warnings", warnings),
        TagCluster("Fandoms", fandoms),
        TagCluster("Relationships", relationships, isTinted = true),
        TagCluster("Characters", characters),
        TagCluster("Additional Tags", freeforms)
    ).filter { it.tags.isNotEmpty() }

    if (clusters.isEmpty()) return

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
                            modifier = Modifier.clickable {
                                uriHandler.openUri("https://archiveofourown.org/tags/${Uri.encode(tag)}/works")
                            }
                        )
                    }
                }

                if (index == clusters.lastIndex) {
                    Text(
                        text = "Tags come from AO3. Tap one to find other AO3 works with that tag.",
                        fontSize = 12.sp,
                        color = tokens.secondaryInk,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
        }
    }
}

/**
 * Artboard 1a's grouped facts card (`WorkDetailFactsSections.swift:24`).
 * Outlined, unfilled panel on the wash with Series, Headline facts, and Published date.
 */
@Composable
fun WorkDetailFactsCard(
    seriesTitle: String,
    seriesPosition: Int,
    seriesUrl: String,
    language: String,
    wordCount: Int,
    updatedDate: String,
    publishedDate: String,
    modifier: Modifier = Modifier,
    onOpenSeries: (String) -> Unit = {}
) {
    val hasSeries = seriesTitle.isNotBlank()
    val headlineSegments = buildList {
        if (language.isNotBlank()) add(language)
        if (wordCount > 0) add("${NumberFormat.getIntegerInstance().format(wordCount)} words")
    }
    val hasHeadline = headlineSegments.isNotEmpty()
    val hasPublished = publishedDate.isNotBlank()

    if (!hasSeries && !hasHeadline && !hasPublished) return

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
            .subjectPanel(cornerRadius = 16.dp, isFilled = false)
    ) {
        var needsDivider = false

        if (hasSeries) {
            val partText = if (seriesPosition > 0) "Part $seriesPosition" else "Series"
            SubjectFormRow(
                label = seriesTitle,
                value = partText,
                showsDisclosure = seriesUrl.isNotBlank(),
                onClick = if (seriesUrl.isNotBlank()) {
                    { onOpenSeries(seriesUrl) }
                } else null
            )
            needsDivider = true
        }

        if (hasHeadline) {
            if (needsDivider) SubjectRowSeparator(inset = 0.dp)
            val updatedValue = if (updatedDate.isNotBlank()) "upd $updatedDate" else null
            SubjectFormRow(
                label = headlineSegments.joinToString(" · "),
                value = updatedValue
            )
            needsDivider = true
        }

        if (hasPublished) {
            if (needsDivider) SubjectRowSeparator(inset = 0.dp)
            SubjectFormRow(
                label = "Published",
                value = publishedDate
            )
        }
    }
}

/**
 * Artboard 1a's archive stats strip (`WorkDetailFactsSections.swift:128`).
 * Kudos, Comments (accented, opens discussion), Bookmarks, Hits.
 */
@Composable
fun WorkDetailArchiveStatsStrip(
    kudosCount: Int?,
    commentsCount: Int?,
    bookmarksCount: Int?,
    hitsCount: Int?,
    palette: SubjectPalette,
    hasAO3Work: Boolean,
    modifier: Modifier = Modifier,
    onComments: () -> Unit = {}
) {
    val cells = buildList {
        if (kudosCount != null) {
            add(
                SubjectStatCell(
                    value = kudosCount.compactCount(),
                    label = "Kudos"
                )
            )
        }
        // iOS: only an AO3 work gets the accented, tappable cell ("—" when unknown).
        if (hasAO3Work) {
            add(
                SubjectStatCell(
                    value = commentsCount?.compactCount() ?: "—",
                    label = "Comments",
                    isHighlighted = true,
                    onClick = onComments
                )
            )
        } else if (commentsCount != null) {
            add(SubjectStatCell(value = commentsCount.compactCount(), label = "Comments"))
        }
        if (bookmarksCount != null) {
            add(
                SubjectStatCell(
                    value = bookmarksCount.compactCount(),
                    label = "Bookmarks"
                )
            )
        }
        if (hitsCount != null) {
            add(
                SubjectStatCell(
                    value = hitsCount.compactCount(),
                    label = "Hits"
                )
            )
        }
    }

    if (cells.isEmpty()) return

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
    ) {
        SubjectStatStrip(cells = cells, palette = palette)
    }
}

/**
 * Artboard 1a's Comments section (`WorkDetailSections.swift:122`).
 * Form rows linking to All comments, Chapter comments, and Write a comment.
 */
@Composable
fun WorkDetailCommentsSection(
    commentsCount: Int?,
    chapters: String,
    modifier: Modifier = Modifier,
    onAllComments: () -> Unit,
    onChapterComments: () -> Unit,
    onWriteComment: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val hasMultipleChapters = chapters.contains('/') || (chapters.toIntOrNull() ?: 1) > 1

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        SubjectFieldLabel(text = "COMMENTS")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .subjectPanel(cornerRadius = 14.dp)
        ) {
            SubjectFormRow(
                label = "All comments",
                value = commentsCount?.compactCount() ?: "",
                showsDisclosure = true,
                onClick = onAllComments
            )

            if (hasMultipleChapters) {
                SubjectRowSeparator(inset = 14.dp)
                SubjectFormRow(
                    label = "Chapter comments",
                    value = "",
                    showsDisclosure = true,
                    onClick = onChapterComments
                )
            }

            SubjectRowSeparator(inset = 14.dp)
            SubjectFormRow(
                label = "Write a comment",
                value = "",
                showsDisclosure = true,
                onClick = onWriteComment
            )
        }

        Text(
            text = "Comments load only when you open them.",
            fontSize = 12.sp,
            color = tokens.secondaryInk
        )
    }
}

/**
 * Artboard 1a's page outline buttons (`WorkDetailFactsSections.swift:182`).
 * "Mark as Finished" / "Finished", and "Open on AO3".
 */
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
            title = if (isFinished) "Finished" else "Mark as Finished",
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
    onOpenSeries: (String) -> Unit
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
