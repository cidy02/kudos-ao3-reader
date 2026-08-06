package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Update
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * Compact work metadata expressed with Material 3 color/type roles.
 *
 * Product rule (from Apple cover cards): one stat per row on compact cards,
 * spelled-out nouns. Expression: [Material 3 icon + labelSmall] on the
 * surface, using [MaterialTheme.colorScheme.primary] for icons and
 * [MaterialTheme.colorScheme.onSurfaceVariant] for values — not SF Symbols
 * and not a SwiftUI caption clone.
 */
@Composable
fun CoverCardStatsColumn(
    stats: List<WorkStatItem>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        stats.forEach { stat ->
            WorkStatLabel(item = stat)
        }
    }
}

/**
 * Horizontal wrapping stats for dense list rows (Search / Library detailed).
 * Material [FlowRow] + icon labels — same product fields as Apple
 * `WorkListStatsRow`, MD3 expression.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WorkListStatsRow(
    stats: List<WorkStatItem>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) {
                Text(
                    text = "•",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.semantics { invisibleToUser() }
                )
            }
            WorkStatLabel(item = stat)
        }
    }
}

@Composable
fun WorkStatLabel(
    item: WorkStatItem,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.semantics {
            contentDescription = item.accessibilityLabel ?: item.text
        },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        item.icon?.let { icon ->
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(14.dp)
            )
        }
        Text(
            text = item.text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

data class WorkStatItem(
    val text: String,
    val accessibilityLabel: String? = null,
    val icon: ImageVector? = null
)

object WorkStatIcons {
    val rating: ImageVector get() = Icons.Outlined.Shield
    val chapters: ImageVector get() = Icons.Outlined.Book
    val complete: ImageVector get() = Icons.Outlined.CheckCircle
    val inProgress: ImageVector get() = Icons.Outlined.RadioButtonUnchecked
    val words: ImageVector get() = Icons.Outlined.TextFields
    val kudos: ImageVector get() = Icons.Outlined.FavoriteBorder
    val datePublished: ImageVector get() = Icons.Outlined.CalendarToday
    val dateUpdated: ImageVector get() = Icons.Outlined.Update
}

/** AO3 rating → short readable name for cover-card density (not single letters). */
fun ratingDisplayName(rating: String): String? {
    return when (rating.trim()) {
        "" -> null
        "General Audiences" -> "General"
        "Teen And Up Audiences" -> "Teen"
        "Mature" -> "Mature"
        "Explicit" -> "Explicit"
        "Not Rated" -> "Not Rated"
        else -> rating
    }
}

fun chapterStatText(chapters: String): String {
    val trimmed = chapters.trim()
    if (trimmed.isEmpty()) return ""
    return if (trimmed == "1") "1 chapter" else "$trimmed chapters"
}

fun wordStatText(count: Int): String {
    return when {
        count <= 0 -> ""
        count == 1 -> "1 word"
        count < 1_000 -> "%,d words".format(count)
        count < 10_000 -> {
            val tenths = (count + 50) / 100
            val whole = tenths / 10
            val frac = tenths % 10
            if (frac == 0) "${whole}K words" else "$whole.${frac}K words"
        }
        else -> {
            val k = (count + 500) / 1_000
            "%,dK words".format(k)
        }
    }
}

fun completionStatText(isComplete: Boolean?): String? {
    return when (isComplete) {
        true -> "Complete"
        false -> "In Progress"
        null -> null
    }
}

fun coverCardStats(
    rating: String,
    chapters: String,
    isComplete: Boolean?,
    wordCount: Int?,
    kudos: Int? = null
): List<WorkStatItem> {
    val completion = completionStatText(isComplete)
    return listOfNotNull(
        ratingDisplayName(rating)?.let {
            WorkStatItem(
                text = it,
                accessibilityLabel = rating,
                icon = WorkStatIcons.rating
            )
        },
        chapters.takeIf { it.isNotBlank() }?.let {
            WorkStatItem(
                text = chapterStatText(it),
                accessibilityLabel = "Chapters $it",
                icon = WorkStatIcons.chapters
            )
        },
        completion?.let {
            WorkStatItem(
                text = it,
                icon = if (isComplete == true) WorkStatIcons.complete else WorkStatIcons.inProgress
            )
        },
        wordCount?.takeIf { it > 0 }?.let {
            WorkStatItem(
                text = wordStatText(it),
                accessibilityLabel = "%,d words".format(it),
                icon = WorkStatIcons.words
            )
        },
        kudos?.takeIf { it > 0 }?.let {
            WorkStatItem(
                text = if (it == 1) "1 kudos" else "%,d kudos".format(it),
                icon = WorkStatIcons.kudos
            )
        }
    )
}

/**
 * AO3 renders Published/Updated in two different formats depending on which page
 * it was scraped from — "2025-11-01" (ISO) on a work's own detail page
 * (`dd.published`/`dd.status`), "01 Nov 2025" on search/listing blurbs
 * (`p.datetime`) — both confirmed live against archiveofourown.org. Tries both,
 * normalizes to MM/DD/YYYY; falls back to the raw string unparsed rather than
 * showing nothing if AO3 ever changes either format.
 */
fun displayDate(rawText: String): String {
    val isoFormat = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
    val blurbFormat = java.text.SimpleDateFormat("dd MMM yyyy", java.util.Locale.US)
    val outputFormat = java.text.SimpleDateFormat("MM/dd/yyyy", java.util.Locale.US)
    for (format in listOf(isoFormat, blurbFormat)) {
        format.isLenient = false
        val parsed = runCatching { format.parse(rawText) }.getOrNull()
        if (parsed != null) return outputFormat.format(parsed)
    }
    return rawText
}

/** List-row stats: short rating name, compact numbers (Apple WorkListStatsRow parity). */
fun listRowStats(
    rating: String,
    wordCount: Int?,
    chapters: String,
    kudos: Int?,
    datePublished: String? = null,
    dateUpdated: String? = null
): List<WorkStatItem> {
    // Updated only shows when it actually differs from published — a
    // never-updated oneshot has nothing new to say twice.
    val showsUpdated = !dateUpdated.isNullOrBlank() && dateUpdated != datePublished
    return listOfNotNull(
        ratingDisplayName(rating)?.let {
            WorkStatItem(text = it, accessibilityLabel = rating, icon = WorkStatIcons.rating)
        },
        wordCount?.takeIf { it > 0 }?.let {
            WorkStatItem(
                text = "%,d".format(it),
                accessibilityLabel = "%,d words".format(it),
                icon = WorkStatIcons.words
            )
        },
        chapters.takeIf { it.isNotBlank() }?.let {
            WorkStatItem(
                text = it,
                accessibilityLabel = "Chapters $it",
                icon = WorkStatIcons.chapters
            )
        },
        kudos?.takeIf { it > 0 }?.let {
            WorkStatItem(
                text = "%,d".format(it),
                accessibilityLabel = "%,d kudos".format(it),
                icon = WorkStatIcons.kudos
            )
        },
        datePublished?.takeIf { it.isNotBlank() }?.let {
            val display = displayDate(it)
            WorkStatItem(text = display, accessibilityLabel = "Published $display", icon = WorkStatIcons.datePublished)
        },
        dateUpdated?.takeIf { showsUpdated }?.let {
            val display = displayDate(it)
            WorkStatItem(text = display, accessibilityLabel = "Updated $display", icon = WorkStatIcons.dateUpdated)
        }
    )
}
