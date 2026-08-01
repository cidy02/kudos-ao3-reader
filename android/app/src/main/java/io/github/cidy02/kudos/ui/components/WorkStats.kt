package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * One-stat-per-row presentation for compact work cards.
 *
 * Ports the hig-review `CoverCardStatsRow` rule: values are spelled out
 * ("12K words", "3/5 chapters") rather than bare numbers or single-letter
 * rating badges, because the row is no longer shared with wrapping chips.
 */
@Composable
fun CoverCardStatsColumn(
    stats: List<WorkStatItem>,
    modifier: Modifier = Modifier
) {
    if (stats.isEmpty()) return
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        stats.forEach { stat ->
            Text(
                text = stat.text,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics {
                    contentDescription = stat.accessibilityLabel ?: stat.text
                }
            )
        }
    }
}

data class WorkStatItem(
    val text: String,
    val accessibilityLabel: String? = null
)

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
