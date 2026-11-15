package io.github.cidy02.kudos.works.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.Locale

/**
 * Board 19's stats card data (`WorkDetailStatsCard.swift`): nine labelled figures in a 3x3
 * grid replacing the old archive stats strip, headline row, published row, and Chapters cell.
 */
object WorkDetailStats {
    data class Cell(
        val label: String,
        val value: String,
        val showsGivenHeart: Boolean = false,
        val accessibilityText: String
    )

    const val emptyFigure = "—"

    private val parsers = listOf("uuuu-MM-dd", "dd MMM uuuu").map {
        DateTimeFormatter.ofPattern(it, Locale.US).withResolverStyle(ResolverStyle.STRICT)
    }
    private val sameYearFormatter = DateTimeFormatter.ofPattern("MMM d", Locale.US)
    private val otherYearFormatter = DateTimeFormatter.ofPattern("MMM d, uuuu", Locale.US)

    private fun grouped(number: Int): String =
        NumberFormat.getIntegerInstance(Locale.US).format(number)

    fun cells(
        words: Int?,
        chapters: String,
        kudos: Int?,
        kudosGiven: Boolean,
        hits: Int?,
        comments: Int?,
        bookmarks: Int?,
        published: String,
        updated: String,
        language: String,
        now: Instant = Instant.now()
    ): List<Cell> {
        val chapterText = chapters.trim()
        val lang = language.trim()
        return listOf(
            Cell(
                label = "Words",
                value = words?.let(::grouped) ?: emptyFigure,
                accessibilityText = words?.let { "${grouped(it)} words" } ?: "Words unknown"
            ),
            Cell(
                label = "Chapters",
                value = chapterText.ifEmpty { emptyFigure },
                accessibilityText = if (chapterText.isEmpty()) "Chapters unknown" else "$chapterText chapters"
            ),
            Cell(
                label = "Kudos",
                value = kudos?.let(::grouped) ?: emptyFigure,
                showsGivenHeart = kudosGiven,
                accessibilityText = (kudos?.let { "${grouped(it)} kudos" } ?: "Kudos unknown") +
                    if (kudosGiven) ", given by you" else ""
            ),
            Cell(
                label = "Hits",
                value = hits?.compactCount() ?: emptyFigure,
                accessibilityText = hits?.let { "${grouped(it)} hits" } ?: "Hits unknown"
            ),
            Cell(
                label = "Comments",
                value = comments?.compactCount() ?: emptyFigure,
                accessibilityText = comments?.let { "${grouped(it)} comments" } ?: "Comments unknown"
            ),
            Cell(
                label = "Bookmarks",
                value = bookmarks?.compactCount() ?: emptyFigure,
                accessibilityText = bookmarks?.let { "${grouped(it)} bookmarks" } ?: "Bookmarks unknown"
            ),
            dateCell("Published", published, now),
            dateCell("Updated", updated, now),
            Cell(
                label = "Language",
                value = lang.ifEmpty { emptyFigure },
                accessibilityText = if (lang.isEmpty()) "Language unknown" else "Language: $lang"
            )
        )
    }

    /** Short date: `"Mar 3"` in the current UTC year, `"Oct 21, 2023"` otherwise; raw if unparseable. */
    fun shortDate(raw: String, now: Instant = Instant.now()): String {
        val trimmed = raw.trim()
        val parsed = parsers.firstNotNullOfOrNull { parser ->
            runCatching { LocalDate.parse(trimmed, parser) }.getOrNull()
        } ?: return raw
        val currentYear = now.atZone(ZoneOffset.UTC).year
        val formatter = if (parsed.year == currentYear) sameYearFormatter else otherYearFormatter
        return parsed.format(formatter)
    }

    private fun dateCell(label: String, raw: String, now: Instant): Cell {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return Cell(label = label, value = emptyFigure, accessibilityText = "$label date unknown")
        }
        val printed = shortDate(trimmed, now)
        return Cell(label = label, value = printed, accessibilityText = "$label $printed")
    }
}

/**
 * 3x3 stats card; switches to single-column labelled rows at accessibility font scales.
 */
@Composable
fun WorkDetailStatsCard(
    cells: List<WorkDetailStats.Cell>,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val accessible = isAccessibilityFontScale()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
            .subjectPanel(cornerRadius = SubjectMetrics.panelRadius)
    ) {
        if (accessible) {
            cells.forEachIndexed { index, cell ->
                if (index > 0) SubjectRowSeparator()
                Box(
                    modifier = Modifier.clearAndSetSemantics {
                        contentDescription = cell.accessibilityText
                    }
                ) {
                    SubjectFormRow(
                        label = cell.label,
                        trailing = {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(5.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                if (cell.showsGivenHeart) {
                                    Icon(
                                        imageVector = Icons.Filled.Favorite,
                                        contentDescription = null,
                                        tint = tokens.accentInk,
                                        modifier = Modifier.size(14.dp)
                                    )
                                }
                                Text(
                                    text = cell.value,
                                    fontSize = 15.sp,
                                    color = tokens.secondaryInk
                                )
                            }
                        }
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                cells.chunked(3).forEach { row ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(IntrinsicSize.Min),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        row.forEachIndexed { index, cell ->
                            if (index > 0) {
                                Box(
                                    modifier = Modifier
                                        .width(0.5.dp)
                                        .fillMaxHeight()
                                        .background(tokens.glassStroke(0.13))
                                )
                            }
                            StatsGridCell(
                                cell = cell,
                                accentInk = tokens.accentInk,
                                primaryInk = tokens.primaryInk,
                                secondaryInk = tokens.secondaryInk,
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatsGridCell(
    cell: WorkDetailStats.Cell,
    accentInk: androidx.compose.ui.graphics.Color,
    primaryInk: androidx.compose.ui.graphics.Color,
    secondaryInk: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .padding(horizontal = 4.dp)
            .clearAndSetSemantics { contentDescription = cell.accessibilityText },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = cell.label.uppercase(Locale.US),
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.4.sp,
            color = secondaryInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (cell.showsGivenHeart) {
                Icon(
                    imageVector = Icons.Filled.Favorite,
                    contentDescription = null,
                    tint = accentInk,
                    modifier = Modifier.size(12.dp)
                )
            }
            Text(
                text = cell.value,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = primaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum")
            )
        }
    }
}
