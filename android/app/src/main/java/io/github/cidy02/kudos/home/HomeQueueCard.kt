package io.github.cidy02.kudos.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.withOpacity

/**
 * 1b's stacked deck: two glass backs and the next work's face.
 * The face uses that work's `cardWash`, matching `ReadingQueueCard` and the
 * iOS Home screenshot. `hue` / `colorHex` tint the glass backs via
 * `carouselQueueTint`, which is where iOS shows the queue's own colour.
 */
@Composable
fun HomeQueueCard(
    queue: ReadingQueue,
    works: List<SavedWork>,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val tint = HomeFacts.carouselQueueTint(tokens.theme, queue.hue, queue.colorHex)
    val upNext = HomeFacts.upNext(works)
    Column(
        modifier
            .padding(top = 2.dp, bottom = 8.dp)
            .size(width = HomeCardMetrics.width, height = 168.dp)
    ) {
        Deck(tint = tint, upNext = upNext, works = works)
        Spacer(Modifier.height(9.dp))
        Text(
            text = queue.displayName,
            color = tokens.primaryInk,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = HomeFacts.queueCardFooter(works),
            color = tokens.secondaryInk,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun Deck(tint: Color?, upNext: SavedWork?, works: List<SavedWork>) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(12.dp)
    val back = tint ?: tokens.glassFill(0.06)
    val mid = tint?.withOpacity(0.85) ?: tokens.glassFill(0.09)
    Box(Modifier.size(width = HomeCardMetrics.width, height = 96.dp)) {
        GlassCard(
            fill = back,
            shape = shape,
            modifier = Modifier
                .size(148.dp, 88.dp)
                .offset(x = 16.dp)
        )
        GlassCard(
            fill = mid,
            shape = shape,
            modifier = Modifier
                .size(148.dp, 88.dp)
                .offset(x = 8.dp, y = 4.dp)
        )
        Box(
            Modifier
                .size(148.dp, 88.dp)
                .offset(y = 8.dp)
        ) {
            if (upNext == null) {
                GlassCard(fill = tokens.glassFill(0.12), shape = shape, modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = "No works yet",
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(10.dp)
                    )
                }
            } else {
                val palette = SubjectPalette.fromHue(
                    HomeFacts.workHue(upNext.workFandoms, upNext.title),
                    tokens.theme
                )
                Column(
                    Modifier
                        .fillMaxSize()
                        .clip(shape)
                        .background(palette.cardWash)
                        .border(0.5.dp, tokens.glassStroke(0.12), shape)
                        .padding(10.dp)
                ) {
                    val fandom = HomeFacts.primaryFandom(upNext.workFandoms)
                    if (fandom != null) {
                        SubjectKicker(
                            text = fandom,
                            palette = palette,
                            size = 8.5.sp,
                            ruleWidth = 18.dp,
                            ruleSpacing = 5.dp
                        )
                    }
                    Text(
                        text = upNext.title,
                        color = tokens.primaryInk,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(Modifier.weight(1f))
                    QueueProgressStrip(progress = HomeFacts.queueProgress(works), palette = palette)
                }
            }
        }
    }
}

@Composable
private fun GlassCard(
    fill: Color,
    shape: RoundedCornerShape,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .clip(shape)
            .background(fill)
            .border(0.5.dp, tokens.glassStroke(0.09), shape)
    ) {
        content()
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
