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
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.padding

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
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        stats.forEach { stat ->
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
                // Secondary — not primary/accent. Language, words, kudos etc. sit
                // under the category chips as quiet metadata (iOS WorkStatLabel).
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
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
    val icon: ImageVector? = null,
    /** AO3's own colour coding for this value, if it has one — see [AO3StatusTint].
     *  Only [WorkStatusChipRow] paints it; the plain count labels ignore it. */
    val tint: Color? = null
)

/**
 * AO3's rating and category colour coding, as the site itself uses it, so a rating
 * or a ship category is identifiable before the text is read.
 *
 * Apple's system palette rather than Material's, deliberately: this is product
 * data shared with the iOS client (`WorkStat.ratingColor` / `categoryColor`), not
 * platform styling, and the two apps should agree on what "Explicit" looks like.
 * Every one of these is only ever drawn at low alpha behind [MaterialTheme]'s own
 * `onSurfaceVariant` text, so none of them has to satisfy MD3 contrast on its own.
 */
object AO3StatusTint {
    val green = Color(0xFF34C759)
    val yellow = Color(0xFFFFCC00)
    val orange = Color(0xFFFF9500)
    val red = Color(0xFFFF3B30)
    val pink = Color(0xFFFF2D55)
    val blue = Color(0xFF007AFF)
    val purple = Color(0xFFAF52DE)
    val gray = Color(0xFF8E8E93)

    /** Grey rather than null for "Not Rated": falling through to the theme accent
     *  painted it the app's red, which reads as the *most* severe rating. */
    fun rating(rating: String): Color? = when (rating.trim()) {
        "General Audiences" -> green
        "Teen And Up Audiences" -> yellow
        "Mature" -> orange
        "Explicit" -> red
        "Not Rated" -> gray
        else -> null
    }

    fun category(category: String): Color? = when (category.trim()) {
        "F/F" -> red
        "F/M" -> pink
        "Gen" -> green
        "M/M" -> blue
        "Multi" -> purple
        "Other" -> gray
        else -> null
    }
}

object WorkStatIcons {
    val rating: ImageVector get() = Icons.Outlined.Shield
    val chapters: ImageVector get() = Icons.Outlined.Book
    val complete: ImageVector get() = Icons.Outlined.CheckCircle
    val inProgress: ImageVector get() = Icons.Outlined.RadioButtonUnchecked
    val words: ImageVector get() = Icons.Outlined.TextFields
    val kudos: ImageVector get() = Icons.Outlined.FavoriteBorder
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

/** List-row stats: full rating name, compact numbers (Apple WorkListStatsRow fields). */
fun listRowStats(
    rating: String,
    wordCount: Int?,
    chapters: String,
    kudos: Int?
): List<WorkStatItem> {
    return listOfNotNull(
        rating.takeIf { it.isNotBlank() }?.let {
            WorkStatItem(text = it, icon = WorkStatIcons.rating)
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
        }
    )
}

/**
 * The four states AO3 itself surfaces up front on a work: rating, category,
 * warnings and completion. These are *what the work is*, where [listRowStats] is
 * counts — which is why they render as capsules and the counts don't.
 *
 * Every slot always says something, "N/A" and "No Warnings" included: a blank
 * reads as a layout gap rather than a real state. AO3's own legend never lists the
 * specific warnings either, just how many apply, so the visible text stays short
 * and the full list reaches TalkBack through the accessibility label.
 */
fun statusChips(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean?,
    /** The host card is showing its full detail. Only the category chip changes. */
    expanded: Boolean = false
): List<WorkStatItem> {
    val chips = mutableListOf<WorkStatItem>()

    rating.takeIf { it.isNotBlank() }?.let {
        chips += WorkStatItem(
            text = ratingDisplayName(it) ?: it,
            accessibilityLabel = it,
            icon = WorkStatIcons.rating,
            tint = AO3StatusTint.rating(it)
        )
    }

    val named = categories.filter { it.isNotBlank() && AO3StatusTint.category(it) != null }
    if (named.size > 1 && !expanded) {
        // AO3's own rule, verified live on 2026-08-07: its blurb draws
        // `category-multi` for *any* work with more than one category, whether or
        // not the literal "Multi" tag is among them — `F/F, M/M` and `Gen, M/M`
        // both get it. One chip keeps a collapsed card glanceable; expanding
        // spells them out, which is what AO3's own work page does.
        chips += WorkStatItem(
            text = "Multi",
            accessibilityLabel = "Categories: ${named.joinToString(", ")}",
            icon = Icons.Outlined.People,
            tint = AO3StatusTint.category("Multi")
        )
    } else if (named.isEmpty()) {
        chips += WorkStatItem(
            text = "N/A",
            accessibilityLabel = "Category: not categorized",
            icon = Icons.Outlined.People,
            tint = AO3StatusTint.gray
        )
    } else {
        named.forEach {
            chips += WorkStatItem(
                text = it,
                accessibilityLabel = "Category: $it",
                icon = Icons.Outlined.People,
                tint = AO3StatusTint.category(it)
            )
        }
    }

    // "No Archive Warnings Apply" and "Creator Chose Not To Use Archive Warnings"
    // are AO3's two ways of saying "nothing to flag"; anything else is a real
    // warning and gets counted rather than spelled out.
    val real = warnings.filter { warning ->
        val text = warning.trim()
        text.isNotBlank() &&
            !text.equals("No Archive Warnings Apply", ignoreCase = true) &&
            !text.startsWith("Creator Chose Not To Use", ignoreCase = true)
    }
    val chooseNotTo = warnings.any { it.trim().startsWith("Creator Chose Not To Use", ignoreCase = true) }
    if (real.isNotEmpty() && !chooseNotTo && expanded) {
        // Expanded, the count becomes the warnings themselves — the same split the
        // categories take. Only this branch has anything to expand: "No Warnings"
        // and "Not Disclosed" are single states, not folded lists.
        real.forEach { warning ->
            chips += WorkStatItem(
                text = warning,
                accessibilityLabel = "Warning: $warning",
                icon = Icons.Outlined.WarningAmber,
                tint = AO3StatusTint.red
            )
        }
    } else chips += when {
        real.isNotEmpty() && !chooseNotTo -> WorkStatItem(
            text = if (real.size == 1) "1 Warning" else "${real.size} Warnings",
            accessibilityLabel = "Warnings: ${real.joinToString(", ")}",
            icon = Icons.Outlined.WarningAmber,
            tint = AO3StatusTint.red
        )
        chooseNotTo -> WorkStatItem(
            text = "Not Disclosed",
            accessibilityLabel = "Creator chose not to use archive warnings",
            icon = Icons.Outlined.WarningAmber,
            tint = AO3StatusTint.orange
        )
        else -> WorkStatItem(
            text = "No Warnings",
            accessibilityLabel = "No archive warnings apply",
            icon = Icons.Outlined.CheckCircle,
            tint = AO3StatusTint.gray
        )
    }

    chips += when (isComplete) {
        true -> WorkStatItem(
            text = "Complete",
            accessibilityLabel = "Status: complete",
            icon = Icons.Outlined.CheckCircle,
            tint = AO3StatusTint.green
        )
        false -> WorkStatItem(
            text = "WIP",
            accessibilityLabel = "Status: work in progress",
            icon = Icons.Outlined.Schedule,
            tint = AO3StatusTint.orange
        )
        // AO3 omits the marker rather than saying "unknown", so neither do we.
        null -> WorkStatItem(
            text = "Unknown",
            accessibilityLabel = "Status: unknown",
            icon = Icons.Outlined.Schedule,
            tint = AO3StatusTint.gray
        )
    }

    return chips
}

/**
 * [statusChips] as capsules, bullet-separated and centred — matching Apple
 * `WorkListStatsRow`. Centred rather than stretched edge-to-edge: stretching only
 * squares this row with the counts row under it while both are full, and a
 * two-chip work would get two capsules pinned to opposite edges with a canyon
 * between them.
 */
@Composable
fun WorkStatusChipRow(
    stats: List<WorkStatItem>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) {
                Text(
                    text = "•",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .align(Alignment.CenterVertically)
                        .clearAndSetSemantics {}
                )
            }
            // The capsule carries AO3's colour coding, not the glyph — a chip is a
            // block of colour, so painting it is what the coding is for. Icon and
            // text stay on the theme's own onSurfaceVariant: legible on every tint
            // in both appearances, where a saturated glyph on a capsule of the same
            // hue just goes muddy. Tinted, not filled — "Explicit" is red and four
            // solid blocks of that beside the cover art would read as an error.
            Surface(
                color = stat.tint?.copy(alpha = 0.22f)
                    ?: MaterialTheme.colorScheme.surfaceContainerHighest,
                shape = MaterialTheme.shapes.small
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                        .semantics { contentDescription = stat.accessibilityLabel ?: stat.text }
                ) {
                    stat.icon?.let {
                        Icon(
                            imageVector = it,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(13.dp)
                        )
                    }
                    Text(text = stat.text, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}
