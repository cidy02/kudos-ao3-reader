package io.github.cidy02.kudos.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
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
    modifier: Modifier = Modifier
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
    val screenHeightDp = LocalConfiguration.current.screenHeightDp.coerceAtLeast(400)
    // Rough paragraph budget: leave room for margins + heading + caption.
    val bodyLines = ((screenHeightDp - 160) / 28).coerceIn(8, 18)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .semantics {
                contentDescription = message
            }
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 36.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            SkeletonLine(
                widthFraction = 0.62f,
                height = 18.dp,
                color = lineColor.copy(alpha = 0.18f * shimmerAlpha + 0.06f)
            )
            SkeletonLine(
                widthFraction = 0.38f,
                height = 12.dp,
                color = lineColor.copy(alpha = 0.14f * shimmerAlpha + 0.05f)
            )
            repeat(bodyLines) { index ->
                val fraction = when (index % 4) {
                    0 -> 1f
                    1 -> 0.94f
                    2 -> 0.88f
                    else -> 0.72f
                }
                SkeletonLine(
                    widthFraction = fraction,
                    height = 12.dp,
                    color = lineColor.copy(alpha = 0.16f * shimmerAlpha + 0.05f)
                )
            }
        }
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 32.dp)
        )
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
