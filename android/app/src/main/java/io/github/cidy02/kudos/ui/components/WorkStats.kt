package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Comment
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Error
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Update
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
            if (index > 0) StatSeparator()
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
                tint = item.tint ?: MaterialTheme.colorScheme.primary,
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

/**
 * Rating, category, warnings, and completion status — the four fields AO3
 * itself always surfaces up front on a work — justified across the full card
 * width: the first badge hugs the leading edge, the last the trailing edge, and
 * the slack is split evenly across every gap ([Arrangement.SpaceBetween]) so
 * the row's ends line up card to card (iOS `WorkListStatsRow.topRow` parity).
 *
 * Not four equal-width columns: a badge that outgrew its quarter would wrap or
 * truncate unpredictably, which is exactly what device testing rejected.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WorkTopStatsRow(
    stats: List<WorkStatItem>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) StatSeparator()
            WorkStatLabel(item = stat)
        }
    }
}

@Composable
private fun StatSeparator() {
    Text(
        text = "•",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.semantics { invisibleToUser() }
    )
}

/**
 * The four always-present top-row badges. Every one shows something even when
 * empty ("N/A", "No Warnings") — a blank slot reads as a layout gap rather than
 * a real state. Categories are filtered to recognized values first: an
 * unrecognized string would otherwise pass an `isNotEmpty` check and still
 * render nothing, leaving the slot silently blank.
 */
fun topRowStats(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean?
): List<WorkStatItem> = buildList {
    ratingLetter(rating)?.let {
        add(
            WorkStatItem(
                text = it,
                accessibilityLabel = rating,
                icon = WorkStatIcons.rating,
                tint = ratingColor(rating)
            )
        )
    }
    val recognized = categories.filter { categoryColor(it) != null }
    if (recognized.isEmpty()) {
        add(
            WorkStatItem(
                text = "N/A",
                accessibilityLabel = "Category: not categorized",
                icon = WorkStatIcons.category,
                tint = UnknownStatColor
            )
        )
    } else {
        recognized.forEach { category ->
            add(
                WorkStatItem(
                    text = category,
                    accessibilityLabel = "Category: $category",
                    icon = WorkStatIcons.category,
                    tint = categoryColor(category)
                )
            )
        }
    }
    // AO3's own legend never lists the specific warnings in its badge either —
    // just how many apply — so the visible text stays short; the full list
    // still reaches TalkBack through the content description.
    val warningStatus = WorkWarningStatus.from(warnings)
    add(
        WorkStatItem(
            text = warningStatus.text,
            accessibilityLabel = when (warningStatus) {
                is WorkWarningStatus.Present ->
                    "Warnings: ${realWarnings(warnings).joinToString(", ")}"
                is WorkWarningStatus.Undisclosed ->
                    "Archive warnings: creator chose not to disclose"
                is WorkWarningStatus.None -> "No archive warnings"
            },
            icon = WorkStatIcons.warning,
            tint = warningStatus.color
        )
    )
    add(
        WorkStatItem(
            text = completionShortText(isComplete),
            accessibilityLabel = "Status: ${completionStatText(isComplete)}",
            icon = completionIcon(isComplete),
            tint = completionColor(isComplete)
        )
    )
}

data class WorkStatItem(
    val text: String,
    val accessibilityLabel: String? = null,
    val icon: ImageVector? = null,
    val tint: Color? = null
)

object WorkStatIcons {
    val rating: ImageVector get() = Icons.Outlined.Shield
    val category: ImageVector get() = Icons.Outlined.Group
    val warning: ImageVector get() = Icons.Outlined.Error
    val language: ImageVector get() = Icons.Outlined.Language
    val chapters: ImageVector get() = Icons.Outlined.Book
    val complete: ImageVector get() = Icons.Outlined.CheckCircle
    val inProgress: ImageVector get() = Icons.Outlined.RadioButtonUnchecked
    val unknown: ImageVector get() = Icons.AutoMirrored.Outlined.HelpOutline
    val words: ImageVector get() = Icons.Outlined.TextFields
    val comments: ImageVector get() = Icons.AutoMirrored.Outlined.Comment
    val kudos: ImageVector get() = Icons.Outlined.FavoriteBorder
    val bookmarks: ImageVector get() = Icons.Outlined.BookmarkBorder
    val hits: ImageVector get() = Icons.Outlined.Visibility
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

/**
 * AO3's single-letter rating shorthand, for the dense four-badge top row where
 * the spelled-out names don't all fit on one line. Deliberately NOT used by the
 * compact cover cards, which spell their stats out and have the width for it
 * (iOS parity — see WorkStat.ratingLetter).
 */
fun ratingLetter(rating: String): String? = when (rating.trim()) {
    "" -> null
    "General Audiences" -> "G"
    "Teen And Up Audiences" -> "T"
    "Mature" -> "M"
    "Explicit" -> "E"
    "Not Rated" -> "NR"
    else -> rating
}

/** AO3's own General/Teen/Mature/Explicit rating-icon color coding (iOS parity). */
fun ratingColor(rating: String): Color? = when (rating.trim()) {
    "General Audiences" -> Color(0xFF2E7D32)
    "Teen And Up Audiences" -> Color(0xFFF9A825)
    "Mature" -> Color(0xFFEF6C00)
    "Explicit" -> Color(0xFFC62828)
    // Explicitly gray rather than null: falling through to the theme's primary
    // tint painted it the app's accent, which reads as the most severe rating —
    // the opposite of what "no rating given" means.
    "Not Rated" -> UnknownStatColor
    else -> null
}

/** The neutral tint shared by every "absent / not stated" badge. */
private val UnknownStatColor = Color(0xFF616161)

/**
 * AO3's own category color coding (F/F, F/M, Gen, M/M, Multi, Other). No Material
 * icon distinguishes them by shape any better than SF Symbols does on iOS, so
 * every category shares [WorkStatIcons.category] and color alone differentiates
 * (iOS parity — see WorkStat.categoryColor).
 */
fun categoryColor(category: String): Color? = when (category) {
    "F/F" -> Color(0xFFC62828)
    "F/M" -> Color(0xFFD81B60)
    "Gen" -> Color(0xFF2E7D32)
    "M/M" -> Color(0xFF1565C0)
    "Multi" -> Color(0xFF6A1B9A)
    "Other" -> Color(0xFF616161)
    else -> null
}

/**
 * AO3's "No Archive Warnings Apply" / "Creator Chose Not To Use Archive
 * Warnings" are sentinel non-warnings, not warnings worth flagging red.
 */
fun realWarnings(warnings: List<String>): List<String> = warnings.filter {
    !it.contains("No Archive Warnings", ignoreCase = true) &&
        !it.contains("Chose Not To Use", ignoreCase = true)
}

/**
 * AO3's Archive Warnings field is one of three mutually-exclusive states, not a
 * present/absent flag: specific warnings listed (red), "No Archive Warnings
 * Apply" (gray), or "Creator Chose Not To Use Archive Warnings" (amber — the
 * content *could* include any standard warning, the creator just didn't say).
 * Collapsing the last two together would present an undisclosed work as a
 * confirmed-clean one (iOS parity — see WorkWarningStatus).
 */
sealed class WorkWarningStatus {
    object None : WorkWarningStatus()
    object Undisclosed : WorkWarningStatus()
    data class Present(val count: Int) : WorkWarningStatus()

    val text: String
        get() = when (this) {
            is None -> "No Warnings"
            is Undisclosed -> "Not Disclosed"
            is Present -> if (count == 1) "1 Warning Applies" else "$count Warnings Apply"
        }

    val color: Color
        get() = when (this) {
            is None -> UnknownStatColor
            is Undisclosed -> Color(0xFFEF6C00)
            is Present -> Color(0xFFC62828)
        }

    companion object {
        fun from(rawWarnings: List<String>): WorkWarningStatus {
            if (rawWarnings.any { it.contains("Chose Not To Use", ignoreCase = true) }) {
                return Undisclosed
            }
            val real = realWarnings(rawWarnings)
            return if (real.isEmpty()) None else Present(real.size)
        }
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

/** Complete / In Progress / Unknown — `null` is a genuinely unknown status, not "not yet checked". */
fun completionStatText(isComplete: Boolean?): String = when (isComplete) {
    true -> "Complete"
    false -> "In Progress"
    null -> "Unknown"
}

/**
 * For the dense four-badge top row, where "In Progress" is the one label long
 * enough to push the row onto a second line. The compact cover cards keep the
 * spelled-out [completionStatText] (iOS parity).
 */
fun completionShortText(isComplete: Boolean?): String = when (isComplete) {
    true -> "Complete"
    false -> "WIP"
    null -> "Unknown"
}

/** iOS `WorkCompletionStatus.color` parity — green/amber/gray tri-state. */
fun completionColor(isComplete: Boolean?): Color = when (isComplete) {
    true -> Color(0xFF2E7D32)
    false -> Color(0xFFF9A825)
    null -> UnknownStatColor
}

fun completionIcon(isComplete: Boolean?): ImageVector = when (isComplete) {
    true -> WorkStatIcons.complete
    false -> WorkStatIcons.inProgress
    null -> WorkStatIcons.unknown
}

fun completionStatItem(isComplete: Boolean?): WorkStatItem = WorkStatItem(
    text = completionStatText(isComplete),
    accessibilityLabel = "Status: ${completionStatText(isComplete)}",
    icon = completionIcon(isComplete),
    tint = completionColor(isComplete)
)

fun coverCardStats(
    rating: String,
    chapters: String,
    isComplete: Boolean?,
    wordCount: Int?,
    kudos: Int? = null
): List<WorkStatItem> {
    return listOfNotNull(
        ratingDisplayName(rating)?.let {
            WorkStatItem(
                text = it,
                accessibilityLabel = rating,
                icon = WorkStatIcons.rating,
                tint = ratingColor(rating)
            )
        },
        chapters.takeIf { it.isNotBlank() }?.let {
            WorkStatItem(
                text = chapterStatText(it),
                accessibilityLabel = "Chapters $it",
                icon = WorkStatIcons.chapters
            )
        },
        completionStatItem(isComplete),
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

/**
 * The stat row below the top badges, in AO3's own `dl.stats` order: language,
 * words, chapters, comments, kudos, bookmarks, hits — then the published date.
 *
 * Counts always show, zeros included. AO3 omits a `dd` entirely when its count
 * is zero, so a null here means "AO3 said nothing", which for a count means
 * zero — and dropping those badges made a card's stat row change shape for no
 * reason a reader could see. Language and chapters are the two that can be
 * genuinely absent rather than zero, so they fall back to an em dash.
 *
 * The updated date is not here: it sits in the card's top-right corner beside
 * the expand control (iOS `WorkUpdatedDateBadge` parity).
 */
fun listRowStats(
    language: String,
    wordCount: Int?,
    chapters: String,
    comments: Int?,
    kudos: Int?,
    bookmarks: Int?,
    hits: Int?,
    datePublished: String? = null
): List<WorkStatItem> {
    fun count(value: Int?, icon: ImageVector, noun: String): WorkStatItem {
        val formatted = "%,d".format(value ?: 0)
        return WorkStatItem(text = formatted, accessibilityLabel = "$formatted $noun", icon = icon)
    }
    val unknownText = "—"
    return buildList {
        add(
            WorkStatItem(
                // AO3 scrapes `dd.language` as a display name already
                // ("English", "Español"), so there is no code to map here.
                text = language.ifBlank { unknownText },
                accessibilityLabel = if (language.isBlank()) {
                    "Language unknown"
                } else {
                    "Language: $language"
                },
                icon = WorkStatIcons.language
            )
        )
        add(count(wordCount, WorkStatIcons.words, "words"))
        add(
            WorkStatItem(
                text = chapters.ifBlank { unknownText },
                accessibilityLabel = if (chapters.isBlank()) {
                    "Chapter count unknown"
                } else {
                    "Chapters $chapters"
                },
                icon = WorkStatIcons.chapters
            )
        )
        add(count(comments, WorkStatIcons.comments, "comments"))
        add(count(kudos, WorkStatIcons.kudos, "kudos"))
        add(count(bookmarks, WorkStatIcons.bookmarks, "bookmarks"))
        add(count(hits, WorkStatIcons.hits, "hits"))
        datePublished?.takeIf { it.isNotBlank() }?.let {
            val display = displayDate(it)
            add(
                WorkStatItem(
                    text = display,
                    accessibilityLabel = "Published $display",
                    icon = WorkStatIcons.datePublished
                )
            )
        }
    }
}
