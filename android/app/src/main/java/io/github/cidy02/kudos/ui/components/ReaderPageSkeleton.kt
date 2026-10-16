package io.github.cidy02.kudos.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Full-page reading wireframe shown while the EPUB opens.
 *
 * Material expression of hig-review's `ReaderPageSkeleton` / `ReaderOpeningSkeleton`:
 * fills the available height, uses the current theme surface (no system-background
 * flash), and avoids a centered spinner that competes with the first paint of the
 * navigator. Decorative only — does not trigger network or open work.
 */
@Composable
fun ReaderPageSkeleton(
    message: String = "Opening…",
    modifier: Modifier = Modifier,
    backgroundColor: Color = MaterialTheme.colorScheme.background
) {
    val lineColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
    val shimmerAlpha by rememberInfiniteTransition(label = "readerSkeleton")
        .animateFloat(
            initialValue = 0.55f,
            targetValue = 0.95f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 1100),
                repeatMode = RepeatMode.Reverse
            ),
            label = "readerSkeletonAlpha"
        )
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(backgroundColor)
            .clipToBounds()
            .semantics { contentDescription = message }
    ) {
        val paragraphs = ReaderPageSkeletonLayout.paragraphs((maxHeight.value - 28f).coerceAtLeast(0f))
        val shortLineLimit = (maxWidth - 56.dp).coerceAtLeast(0.dp) * 0.8f
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = 28.dp, end = 28.dp, top = 12.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(ReaderPageSkeletonLayout.paragraphSpacing.dp)
        ) {
            SkeletonLine(
                widthFraction = 0.62f,
                height = (ReaderPageSkeletonLayout.headingHeight + 4).dp,
                color = lineColor.copy(alpha = 0.18f * shimmerAlpha + 0.06f)
            )
            paragraphs.forEach { widths ->
                Column(verticalArrangement = Arrangement.spacedBy(ReaderPageSkeletonLayout.lineSpacing.dp)) {
                    widths.forEach { width ->
                        Box(
                            modifier = (if (width == null) Modifier.fillMaxWidth()
                                else Modifier.width(width.dp.coerceAtMost(shortLineLimit)))
                                .height(ReaderPageSkeletonLayout.lineHeight.dp)
                                .clip(RoundedCornerShape(percent = 50))
                                .background(lineColor.copy(alpha = 0.16f * shimmerAlpha + 0.05f))
                        )
                    }
                }
            }
        }
    }
}

/** iOS's bounded paragraph budget, in dp; the view clips the tiny-height fallback. */
internal object ReaderPageSkeletonLayout {
    const val headingHeight = 22f
    const val lineHeight = 13f
    const val lineSpacing = 9f
    const val paragraphSpacing = 20f
    private val shortLineEnds = listOf(180f, 120f, 210f, 160f, 140f, 200f)

    fun paragraphHeight(lineCount: Int): Float =
        lineCount * lineHeight + (lineCount - 1).coerceAtLeast(0) * lineSpacing

    fun paragraphs(height: Float): List<List<Float?>> {
        var remaining = (height - headingHeight - 4 - paragraphSpacing).coerceAtLeast(0f)
        val result = mutableListOf<List<Float?>>()
        while (remaining >= lineHeight) {
            val spacingBefore = if (result.isEmpty()) 0f else paragraphSpacing
            val budget = remaining - spacingBefore
            if (budget < lineHeight) break
            var lineCount = 1
            while (lineCount < 5 && paragraphHeight(lineCount + 1) <= budget) lineCount++
            result += List<Float?>(lineCount - 1) { null } + shortLineEnds[result.size % shortLineEnds.size]
            remaining -= spacingBefore + paragraphHeight(lineCount)
            if (result.size > 40) break
        }
        return result.ifEmpty { listOf(listOf(null, null, 160f)) }
    }
}

@Composable
private fun SkeletonLine(
    widthFraction: Float,
    height: Dp,
    color: Color
) {
    Box(
        modifier = Modifier
            .fillMaxWidth(widthFraction.coerceIn(0.2f, 1f))
            .height(height)
            .clip(RoundedCornerShape(percent = 50))
            .background(color)
    )
}
