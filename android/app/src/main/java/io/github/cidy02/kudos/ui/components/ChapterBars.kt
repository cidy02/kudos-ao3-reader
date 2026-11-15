package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Where a chapter bar is drawn. Width and gap stay fixed until the line is full,
 * then the bars shrink (`ChapterBars.swift`).
 */
enum class ChapterBarScale(
    val nominalWidth: Float,
    val gap: Float,
    val trackHeight: Dp
) {
    Row(nominalWidth = 6f, gap = 2f, trackHeight = 16.dp),
    Card(nominalWidth = 14f, gap = 4f, trackHeight = 76.dp)
}

/** How far a reader is through one planned chapter. */
sealed interface ChapterBarRole {
    data object Read : ChapterBarRole
    data class Current(val fill: Double) : ChapterBarRole
    data object PostedUnread : ChapterBarRole
    data object NotPosted : ChapterBarRole
    data object NewChapter : ChapterBarRole
}

data class ChapterBarItem(
    val role: ChapterBarRole,
    val weight: Double
)

data class ChapterBarMetrics(
    val width: Float,
    val gap: Float,
    val radius: Float
)

/** Pure bar layout matching iOS `ChapterBarGeometry`. */
object ChapterBarGeometry {
    fun metrics(
        count: Int,
        availableWidth: Float,
        nominalWidth: Float,
        gap: Float
    ): ChapterBarMetrics {
        if (count <= 0 || nominalWidth <= 0f) {
            return ChapterBarMetrics(width = 0f, gap = 0f, radius = 0f)
        }
        val width: Float
        val usedGap: Float
        if (availableWidth <= 0f) {
            width = nominalWidth
            usedGap = gap
        } else if (count == 1) {
            width = min(nominalWidth, availableWidth)
            usedGap = gap
        } else {
            val natural = count * nominalWidth + (count - 1) * gap
            if (natural <= availableWidth) {
                width = nominalWidth
                usedGap = gap
            } else {
                val gapBudget = (count - 1) * gap
                if (availableWidth > gapBudget) {
                    width = (availableWidth - gapBudget) / count.toFloat()
                    usedGap = gap
                } else {
                    val scale = availableWidth / natural
                    width = nominalWidth * scale
                    usedGap = gap * scale
                }
            }
        }
        return ChapterBarMetrics(width = width, gap = usedGap, radius = min(3f, width / 2f))
    }

    fun items(
        planned: Int,
        posted: Int,
        progress: Double?,
        weights: List<Double>?,
        heights: List<Double>? = null,
        newChapterCount: Int = 0
    ): List<ChapterBarItem> {
        val clampedPlanned = maxOf(0, planned)
        val clampedPosted = min(maxOf(0, posted), clampedPlanned)
        if (clampedPlanned <= 0) return emptyList()

        fun usable(values: List<Double>?): List<Double>? =
            values?.takeIf { it.size == clampedPosted && clampedPosted > 0 && it.all { value -> value > 0.0 } }

        val known = usable(weights)
        val postedWeights = List(clampedPosted) { index -> known?.get(index) ?: 1.0 }
        val drawn = usable(heights) ?: known
        val postedHeights = List(clampedPosted) { index -> drawn?.get(index) ?: 1.0 }
        val unpostedHeight = drawn?.let { it.sum() / it.size.toDouble() } ?: 1.0
        val total = postedWeights.sum()
        val fraction = progress?.coerceIn(0.0, 1.0)
        var remaining = (fraction ?: 0.0) * total
        val fresh = min(maxOf(0, newChapterCount), clampedPosted)
        val freshStart = clampedPosted - fresh

        return List(clampedPlanned) { index ->
            val weight: Double
            val role: ChapterBarRole
            if (index >= clampedPosted) {
                weight = unpostedHeight
                role = ChapterBarRole.NotPosted
            } else {
                weight = postedHeights[index]
                val span = postedWeights[index]
                when {
                    fraction == null || fraction == 0.0 -> role = ChapterBarRole.PostedUnread
                    remaining >= span - 0.000_001 -> {
                        role = ChapterBarRole.Read
                        remaining -= span
                    }
                    remaining > 0.000_001 -> {
                        role = ChapterBarRole.Current(fill = remaining / span)
                        remaining = 0.0
                    }
                    else -> role = ChapterBarRole.PostedUnread
                }
            }
            if (index in freshStart until clampedPosted && fresh > 0) {
                ChapterBarItem(role = ChapterBarRole.NewChapter, weight = weight)
            } else {
                ChapterBarItem(role = role, weight = weight)
            }
        }
    }

    fun progressLabel(
        chapters: String,
        progress: Double?,
        isFinished: Boolean,
        weights: List<Int>? = null
    ): String? {
        val fraction = if (isFinished) 1.0 else progress
        if (fraction == null || fraction <= 0.0) return null
        val percent = (min(fraction, 1.0) * 100.0).roundToInt()
        val posted = ChapterBarModel.postedChapterCount(chapters)
        if (posted <= 0) return "$percent%"
        val chapter = readingChapter(
            posted = posted,
            progress = fraction,
            weights = weights?.map(Int::toDouble)
        )
        return "Ch $chapter · $percent%"
    }

    fun readingChapter(posted: Int, progress: Double, weights: List<Double>?): Int {
        if (posted <= 0) return 1
        val fraction = progress.coerceIn(0.0, 1.0)
        if (fraction >= 1.0) return posted
        val known = weights?.takeIf { it.size == posted && it.all { value -> value > 0.0 } }
        val postedWeights = List(posted) { index -> known?.get(index) ?: 1.0 }
        val total = postedWeights.sum()
        var remaining = fraction * total
        for (index in 0 until posted) {
            val weight = postedWeights[index]
            if (remaining < weight - 0.000_001 || index == posted - 1) {
                return index + 1
            }
            remaining -= weight
        }
        return posted
    }

    fun accessibilityLabel(items: List<ChapterBarItem>): String {
        val read = items.count { it.role is ChapterBarRole.Read }
        val posted = items.count { it.role !is ChapterBarRole.NotPosted }
        val unposted = items.size - posted
        val fresh = items.count { it.role is ChapterBarRole.NewChapter }
        return buildString {
            append("$read of $posted posted chapters read")
            if (unposted > 0) append(", $unposted not posted yet")
            if (fresh > 0) append(", $fresh new")
        }
    }
}

object ChapterBarModel {
    fun postedChapterCount(chapters: String): Int =
        chapters.substringBefore('/').trim().toIntOrNull()?.coerceAtLeast(0) ?: 0

    fun totalChapterCount(chapters: String): Int? =
        chapters.substringAfter('/', missingDelimiterValue = "").trim().toIntOrNull()?.takeIf { it > 0 }

    fun items(
        chapters: String,
        progress: Double?,
        isFinished: Boolean = false,
        weights: List<Int>?,
        heights: List<Int>? = null,
        newChapterCount: Int = 0
    ): List<ChapterBarItem> {
        val posted = postedChapterCount(chapters)
        val planned = maxOf(totalChapterCount(chapters) ?: posted, posted)
        val fraction = if (isFinished) 1.0 else progress
        return ChapterBarGeometry.items(
            planned = planned,
            posted = posted,
            progress = fraction,
            weights = weights?.map(Int::toDouble),
            heights = heights?.map(Int::toDouble),
            newChapterCount = newChapterCount
        )
    }
}

/**
 * One bar per planned chapter (`ChapterBars.swift`).
 * Read is the app accent on a row and white on a gradient card.
 */
@Composable
fun ChapterBars(
    items: List<ChapterBarItem>,
    scale: ChapterBarScale = ChapterBarScale.Row,
    onGradient: Boolean = false,
    height: Dp? = null,
    accessibilityLabel: String? = null,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val density = LocalDensity.current
    val resolvedHeight = height ?: if (scale == ChapterBarScale.Row) {
        scale.trackHeight * density.fontScale.coerceAtMost(1.8f)
    } else {
        scale.trackHeight
    }
    val spoken = accessibilityLabel ?: ChapterBarGeometry.accessibilityLabel(items)

    if (items.isEmpty()) {
        Spacer(
            modifier
                .height(0.dp)
                .clearAndSetSemantics { contentDescription = spoken }
        )
        return
    }

    val readColor = if (onGradient) Color.White else tokens.accentInk
    val faintColor = if (onGradient) {
        Color.White.copy(alpha = 0.28f)
    } else {
        tokens.primaryInk.copy(alpha = 0.14f)
    }
    val dashedStrokeColor = if (onGradient) {
        Color.White.copy(alpha = 0.55f)
    } else {
        tokens.primaryInk.copy(alpha = 0.35f)
    }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .height(resolvedHeight)
            .clearAndSetSemantics { contentDescription = spoken },
        contentAlignment = Alignment.BottomStart
    ) {
        val availableWidthDp = maxWidth.value
        val metrics = ChapterBarGeometry.metrics(
            count = items.size,
            availableWidth = availableWidthDp,
            nominalWidth = scale.nominalWidth,
            gap = scale.gap
        )
        val tallest = items.maxOfOrNull { it.weight } ?: 1.0

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(metrics.gap.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            items.forEach { item ->
                val fraction = if (tallest > 0.0) (item.weight / tallest).toFloat() else 1f
                val barHeight = maxOf(2f, resolvedHeight.value * fraction).dp
                val barShape = RoundedCornerShape(metrics.radius.dp)
                val barWidth = metrics.width.dp

                when (val role = item.role) {
                    ChapterBarRole.NotPosted -> Canvas(
                        Modifier
                            .width(barWidth)
                            .height(barHeight)
                    ) {
                        val strokePx = 1.dp.toPx()
                        val radiusPx = metrics.radius.dp.toPx()
                        val inset = strokePx / 2f
                        drawRoundRect(
                            color = dashedStrokeColor,
                            topLeft = Offset(inset, inset),
                            size = Size(
                                (size.width - strokePx).coerceAtLeast(0f),
                                (size.height - strokePx).coerceAtLeast(0f)
                            ),
                            cornerRadius = CornerRadius(radiusPx, radiusPx),
                            style = Stroke(
                                width = strokePx,
                                pathEffect = PathEffect.dashPathEffect(
                                    floatArrayOf(2.dp.toPx(), 1.5.dp.toPx()),
                                    0f
                                )
                            )
                        )
                    }

                    is ChapterBarRole.Current -> {
                        val fillFraction = role.fill.coerceIn(0.0, 1.0).toFloat()
                        val filledHeight = if (fillFraction > 0f) {
                            maxOf(2.dp, barHeight * fillFraction)
                        } else {
                            0.dp
                        }
                        Box(
                            modifier = Modifier
                                .width(barWidth)
                                .height(barHeight)
                                .clip(barShape)
                                .background(faintColor),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            if (filledHeight > 0.dp) {
                                Box(
                                    Modifier
                                        .fillMaxWidth()
                                        .height(filledHeight)
                                        .background(readColor)
                                )
                            }
                        }
                    }

                    ChapterBarRole.Read -> Box(
                        Modifier
                            .width(barWidth)
                            .height(barHeight)
                            .background(readColor, barShape)
                    )

                    ChapterBarRole.PostedUnread -> Box(
                        Modifier
                            .width(barWidth)
                            .height(barHeight)
                            .background(faintColor, barShape)
                    )

                    ChapterBarRole.NewChapter -> Box(
                        Modifier
                            .width(barWidth)
                            .height(barHeight)
                            .background(tokens.accentInk, barShape)
                    )
                }
            }
        }
    }
}
