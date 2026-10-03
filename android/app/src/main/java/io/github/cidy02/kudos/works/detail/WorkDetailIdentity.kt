package io.github.cidy02.kudos.works.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.WorkReadingOrDownloadRing
import java.time.Instant

/**
 * Port of iOS `WorkWarningStatus` (`WorkStatLabel.swift:857`).
 * AO3's Archive Warnings field is one of three mutually-exclusive states.
 */
sealed class WorkWarningStatus {
    data object None : WorkWarningStatus()
    data object Undisclosed : WorkWarningStatus()
    data class Present(val count: Int) : WorkWarningStatus()

    val figureText: String
        get() = when (this) {
            is None -> "None"
            is Undisclosed -> "Undisclosed"
            is Present -> count.toString()
        }

    val figureColor: Color
        get() = when (this) {
            is None -> Color(0xFF35C46A)
            is Undisclosed -> Color(0xFFFF9500)
            is Present -> Color(0xFFFF3B30)
        }

    companion object {
        fun from(rawWarnings: List<String>): WorkWarningStatus {
            if (rawWarnings.any { it.contains("Chose Not To Use", ignoreCase = true) }) {
                return Undisclosed
            }
            val real = rawWarnings.filter {
                !it.contains("No Archive Warnings", ignoreCase = true) &&
                    !it.contains("Chose Not To Use", ignoreCase = true)
            }
            return if (real.isEmpty()) None else Present(real.size)
        }
    }
}

/**
 * Port of iOS `WorkStat.ratingLetter` and `WorkStat.ratingColor` (`WorkStatLabel.swift:1009`).
 */
object WorkStatRating {
    fun letter(rating: String): String {
        return when (rating.trim()) {
            "General Audiences" -> "G"
            "Teen And Up Audiences" -> "T"
            "Mature" -> "M"
            "Explicit" -> "E"
            "Not Rated" -> "NR"
            else -> if (rating.isBlank()) "—" else rating.trim().take(2).uppercase()
        }
    }

    fun color(rating: String, isDark: Boolean): Color? {
        return when (rating.trim()) {
            "General Audiences" -> Color(0xFF35C46A)
            "Teen And Up Audiences" -> if (isDark) Color(0xFFFFCC00) else Color(0xFF8C6600)
            "Mature" -> Color(0xFFFF9500)
            "Explicit" -> Color(0xFFFF3B30)
            "Not Rated" -> Color(0xFF8E8E93)
            else -> null
        }
    }
}

/**
 * Port of iOS `WorkCompletionStatus` (`WorkStatLabel.swift:795`).
 */
enum class WorkCompletionStatus(val text: String, val shortText: String) {
    Complete("Complete", "Complete"),
    InProgress("In Progress", "WIP"),
    Unknown("Unknown", "Unknown");

    companion object {
        fun from(isComplete: Boolean?): WorkCompletionStatus {
            return when (isComplete) {
                true -> Complete
                false -> InProgress
                null -> Unknown
            }
        }
    }
}

/**
 * Artboard 1a's WorkDetailIdentityHeader (`WorkDetailIdentityBlock.swift:26`).
 * Kicker (primary fandom), 32sp title, and tappable author byline underneath.
 */
@Composable
fun WorkDetailIdentityHeader(
    title: String,
    author: String,
    authorNames: List<String>,
    fandoms: List<String>,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    onOpenAuthor: (String) -> Unit = {}
) {
    val namedFandoms = fandoms.filter { it.isNotBlank() }
    val primaryFandom = HomeFacts.primaryFandom(namedFandoms) ?: "Work"
    val kickerCount = (namedFandoms.size - 1).coerceAtLeast(0)

    SubjectHeaderBlock(
        kicker = primaryFandom,
        title = title.ifBlank { "Work" },
        palette = palette,
        modifier = modifier,
        kickerTrailingCount = kickerCount,
        gutter = SubjectMetrics.headerGutter,
        trailing = {
            AuthorBylineRow(
                authorNames = authorNames,
                displayAuthor = author,
                onOpenAuthor = onOpenAuthor
            )
        }
    )
}

/**
 * 15.5sp byline row where each author name is individually tappable.
 */
@Composable
private fun AuthorBylineRow(
    authorNames: List<String>,
    displayAuthor: String,
    onOpenAuthor: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    if (authorNames.isEmpty()) {
        Text(
            text = displayAuthor.ifBlank { "Anonymous" },
            color = tokens.secondaryInk,
            fontSize = 15.5.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        authorNames.forEachIndexed { index, name ->
            Text(
                text = name,
                color = tokens.secondaryInk,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .semantics { contentDescription = "Author: $name" }
                    .clickable { onOpenAuthor(name) }
            )
            if (index < authorNames.lastIndex) {
                Text(
                    text = ",",
                    color = tokens.secondaryInk,
                    fontSize = 15.5.sp
                )
            }
        }
    }
}

/**
 * Artboard 1a's WorkDetailFigureStrip (`WorkDetailIdentityBlock.swift:76`).
 * Four-cell strip: Rating, Warnings, Category, Chapters / Complete.
 */
@Composable
fun WorkDetailFigureStrip(
    rating: String,
    warnings: List<String>,
    categories: List<String>,
    chapters: String,
    isComplete: Boolean?,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val warningStatus = WorkWarningStatus.from(warnings)

    val ratingCell = SubjectStatCell(
        value = WorkStatRating.letter(rating),
        label = "Rating",
        tint = WorkStatRating.color(rating, tokens.theme.isDarkFamily)
    )

    val warningsCell = SubjectStatCell(
        value = warningStatus.figureText,
        label = "Warnings",
        tint = warningStatus.figureColor
    )

    val namedCategories = categories.filter { it.isNotBlank() }
    val categoryValue = when {
        namedCategories.isEmpty() -> "—"
        namedCategories.size == 1 -> namedCategories.first()
        else -> "${namedCategories.first()} +${namedCategories.size - 1}"
    }
    val categoryCell = SubjectStatCell(
        value = categoryValue,
        label = "Category"
    )

    val completionStatus = WorkCompletionStatus.from(isComplete)
    val chaptersValue = chapters.trim().ifEmpty { completionStatus.shortText }
    val completionCell = SubjectStatCell(
        value = chaptersValue,
        label = "Complete"
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
    ) {
        SubjectStatStrip(
            cells = listOf(ratingCell, warningsCell, categoryCell, completionCell),
            palette = palette
        )
    }
}

/**
 * Artboard 1a's WorkDetailResumeCard (`WorkDetailIdentityBlock.swift:163`).
 * 20dp corner radius glass panel, progress ring, primary/secondary reading labels,
 * and 42dp solid filled accent circle play control.
 */
@Composable
fun WorkDetailResumeCard(
    actionTitle: String,
    isBusy: Boolean,
    isDownloading: Boolean,
    readingProgress: Double?,
    savedPositionTitle: String?,
    lastReadDate: Instant?,
    palette: SubjectPalette,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val clampedProgress = readingProgress?.coerceIn(0.0, 1.0)
    val hasReadingState = clampedProgress != null

    val primaryLine = if (hasReadingState) {
        savedPositionTitle ?: "Reading"
    } else {
        actionTitle
    }

    val secondaryLine = if (hasReadingState && lastReadDate != null) {
        HomeFacts.relativeNamed(lastReadDate, Instant.now())
    } else {
        null
    }

    val shape = RoundedCornerShape(20.dp)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.panelGutter)
            .clip(shape)
            .background(tokens.glassFill(0.10), shape)
            .border(0.5.dp, tokens.glassStroke(0.14), shape)
            .clickable(enabled = !isBusy, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 16.dp)
            .semantics { contentDescription = "$actionTitle: $primaryLine" }
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(15.dp)
        ) {
            if (isDownloading || clampedProgress != null) {
                WorkReadingOrDownloadRing(
                    downloading = isDownloading,
                    progress = clampedProgress,
                    state = null,
                    diameter = 48.dp
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(3.dp)
            ) {
                Text(
                    text = primaryLine,
                    fontSize = 16.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = tokens.primaryInk,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (secondaryLine != null) {
                    Text(
                        text = secondaryLine,
                        fontSize = 12.5.sp,
                        color = tokens.primaryInk.copy(alpha = 0.6f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(palette.solidButtonFill),
                contentAlignment = Alignment.Center
            ) {
                if (isBusy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = palette.solidButtonLabel,
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = null,
                        tint = palette.solidButtonLabel,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }
    }
}
