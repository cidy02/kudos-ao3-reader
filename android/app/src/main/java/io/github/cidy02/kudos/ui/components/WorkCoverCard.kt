package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlin.math.absoluteValue

/**
 * Compact shelf card — Material 3 [ElevatedCard] expressing the product
 * hierarchy of Apple's cover cards (title → attribution → stats → progress),
 * not a pixel clone of the 164×228 SwiftUI tile.
 *
 * - Whole-card open is the primary action (usually Read).
 * - [IconButton] + [Icons.Outlined.Info] is the Work Detail affordance (MD3).
 * - Local status badges stay off the face when possible; progress uses
 *   [LinearProgressIndicator].
 */
@Composable
fun WorkCoverCard(
    title: String,
    author: String,
    fandom: String?,
    stats: List<WorkStatItem>,
    onOpen: () -> Unit,
    onOpenDetails: () -> Unit,
    modifier: Modifier = Modifier,
    progress: Float? = null,
    progressLabel: String? = null,
    statusChips: List<String> = emptyList(),
    obscured: Boolean = false,
    obscuredLabel: String = "Mature work hidden",
    contentDescription: String? = null
) {
    val a11y = contentDescription ?: buildString {
        append(if (obscured) obscuredLabel else title)
        if (!obscured && author.isNotBlank()) append(", by $author")
    }
    ElevatedCard(
        onClick = onOpen,
        modifier = modifier
            .width(WorkCoverCardMetrics.width)
            .heightIn(min = WorkCoverCardMetrics.minHeight)
            .semantics { this.contentDescription = a11y },
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.elevatedCardColors(
            containerColor = coverContainerColor(title)
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(WorkCoverCardMetrics.contentPadding),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (obscured) {
                StatusBadge(obscuredLabel)
                MetadataChipRow(labels = listOf(statusChips.firstOrNull() ?: "Mature content"))
                Spacer(Modifier.weight(1f))
                return@Column
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                WorkDetailsIconButton(onClick = onOpenDetails)
            }

            if (author.isNotBlank()) {
                CardMetaLine(
                    text = author,
                    icon = Icons.Outlined.Person,
                    accessibilityLabel = "Author: $author"
                )
            }
            if (!fandom.isNullOrBlank()) {
                CardMetaLine(
                    text = fandom,
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    accessibilityLabel = "Fandom: $fandom"
                )
            }

            if (author.isNotBlank() || !fandom.isNullOrBlank()) {
                CardMetaSeparator()
            }

            CoverCardStatsColumn(stats = stats)

            if (statusChips.isNotEmpty()) {
                MetadataChipRow(labels = statusChips, maxItems = 2)
            }

            Spacer(Modifier.weight(1f, fill = true))

            progress?.let { value ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    LinearProgressIndicator(
                        progress = { value.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth(),
                        trackColor = MaterialTheme.colorScheme.surfaceVariant,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = progressLabel
                            ?: if (value >= 0.999f) "Finished" else "Reading",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
fun WorkDetailsIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    contentDescription: String = "Work details"
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(40.dp)
    ) {
        Icon(
            imageVector = Icons.Outlined.Info,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
fun CardMetaLine(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    accessibilityLabel: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.semantics { contentDescription = accessibilityLabel },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(14.dp)
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun CardMetaSeparator(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        contentAlignment = Alignment.Center
    ) {
        androidx.compose.material3.HorizontalDivider(
            modifier = Modifier.width(40.dp),
            thickness = 1.dp,
            color = MaterialTheme.colorScheme.outlineVariant
        )
    }
}

/**
 * Soft tonal distinction between adjacent shelf cards.
 * Uses HSL wash over the MD3 surface container — not iOS cover-art cloning.
 */
@Composable
private fun coverContainerColor(title: String): Color {
    val base = MaterialTheme.colorScheme.surfaceContainerHigh
    val hue = coverHue(title)
    val wash = Color.hsl(
        hue = hue,
        saturation = 0.28f,
        lightness = 0.55f,
        alpha = 0.10f
    )
    return blendOver(base, wash)
}

/** djb2-style stable hue 0…360 from the title string (matches Apple CoverArt intent). */
fun coverHue(title: String): Float {
    var hash = 5381L
    title.forEach { ch ->
        hash = ((hash * 33) + ch.code).absoluteValue
    }
    return (hash % 360).toFloat()
}

private fun blendOver(base: Color, overlay: Color): Color {
    val a = overlay.alpha
    val inv = 1f - a
    return Color(
        red = base.red * inv + overlay.red * a,
        green = base.green * inv + overlay.green * a,
        blue = base.blue * inv + overlay.blue * a,
        alpha = 1f
    )
}

object WorkCoverCardMetrics {
    /** Comfortable MD3 shelf width; product density, not a 164pt iOS lock. */
    val width = 176.dp
    val minHeight = 220.dp
    val contentPadding = 12.dp
    val shelfSpacing = 12.dp
}
