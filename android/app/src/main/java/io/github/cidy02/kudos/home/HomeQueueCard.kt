package io.github.cidy02.kudos.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.CoverStack
import io.github.cidy02.kudos.ui.components.CoverStackKind
import io.github.cidy02.kudos.ui.components.CoverStackLayout
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.withOpacity

/**
 * Port of iOS `ReadingQueueCard` (T-461 / T-501): a 300dp row with a 72×72 queue `CoverStack`
 * beside the queue's name, detail line, and progress strip.
 */
@Composable
fun HomeQueueCard(
    queue: ReadingQueue,
    works: List<SavedWork>,
    /** `HomeFacts.queueFace`: required, so no caller names a work the privacy setting keeps back. */
    face: HomeFacts.QueueFace,
    modifier: Modifier = Modifier,
    backs: List<SavedWork> = if (face.obscured) emptyList() else listOfNotNull(face.upNext)
) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val maxWidth = (LocalConfiguration.current.screenWidthDp.dp - 32.dp).coerceAtLeast(1.dp)
    val rowWidth = if (accessibility) maxWidth else minOf(300.dp, maxWidth)
    val queueHue = queue.hue ?: HomeFacts.coverHue(queue.displayName.ifBlank { "Queue" })
    val palette = queue.colorHex?.let(::parseStoredColor)?.let { SubjectPalette.fromColor(it, tokens.theme) }
        ?: SubjectPalette.fromHue(queueHue, tokens.theme)
    Row(
        modifier = modifier
            .padding(top = 2.dp, bottom = 8.dp)
            .width(rowWidth),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = if (accessibility) Alignment.Top else Alignment.CenterVertically
    ) {
        CoverStack(
            kind = CoverStackKind.Queue,
            name = queue.displayName,
            hue = queueHue,
            pickedHex = queue.colorHex,
            backs = backs.take(CoverStackLayout.maxBacks),
            width = 72.dp,
            height = 72.dp
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = queue.displayName,
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = if (accessibility) Int.MAX_VALUE else 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = HomeFacts.queueCardFooter(works),
                color = tokens.secondaryInk,
                fontSize = 13.sp,
                maxLines = if (accessibility) Int.MAX_VALUE else 2,
                overflow = TextOverflow.Ellipsis
            )
            face.upNext?.let { upNext ->
                Text(
                    text = if (face.obscured) HIDDEN_WORK else upNext.title,
                    color = tokens.primaryInk,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = if (accessibility) Int.MAX_VALUE else 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (works.isNotEmpty()) {
                QueueProgressStrip(
                    progress = HomeFacts.queueProgress(works),
                    palette = palette
                )
            }
        }
    }
}

/** One segment per work, grouped finished → in progress → unread. Gaps close past 40. */
@Composable
private fun QueueProgressStrip(progress: HomeQueueProgress, palette: SubjectPalette) {
    val accent = palette.accent
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(3.5.dp)
    ) {
        val count = progress.total
        if (count <= 0) return@Canvas
        val gap = if (count > 40) 0f else 2.5.dp.toPx()
        val width = (size.width - gap * (count - 1)) / count
        val radius = if (gap == 0f) 0f else size.height / 2f
        for (index in 0 until count) {
            val left = index * (width + gap)
            val track = androidx.compose.ui.geometry.Rect(left, 0f, left + width, size.height)
            drawRoundRect(
                color = accent.withOpacity(0.22),
                topLeft = Offset(track.left, track.top),
                size = Size(track.width, track.height),
                cornerRadius = CornerRadius(radius, radius)
            )
            val fill = when {
                index < progress.finished -> 1f
                index < progress.finished + progress.inProgress -> 0.45f
                else -> 0f
            }
            if (fill > 0f) {
                drawRoundRect(
                    color = accent,
                    topLeft = Offset(left, 0f),
                    size = Size(width * fill, size.height),
                    cornerRadius = CornerRadius(radius, radius)
                )
            }
        }
    }
}

/** The words every obscured card uses. */
private const val HIDDEN_WORK = "Hidden mature work"
