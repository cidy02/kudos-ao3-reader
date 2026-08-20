package io.github.cidy02.kudos.ui.components

import android.provider.Settings
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
private fun isReduceMotionEnabled(): Boolean {
    val context = LocalContext.current
    return Settings.Global.getFloat(
        context.contentResolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f
    ) == 0f
}

/**
 * Rounded placeholder. [width] is an exact size (not a max) so wrapping
 * layouts like FlowRow get a real intrinsic width instead of a sliver.
 * Null [width] fills the parent.
 */
@Composable
fun SkeletonBlock(
    width: Dp? = null,
    height: Dp,
    cornerRadius: Dp = 6.dp,
    modifier: Modifier = Modifier
) {
    val reduceMotion = isReduceMotionEnabled()
    val infiniteTransition = rememberInfiniteTransition(label = "skeleton")
    val pulse by infiniteTransition.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1100),
            repeatMode = RepeatMode.Reverse
        ),
        label = "skeleton_alpha"
    )
    val alpha = if (reduceMotion) 1f else pulse

    val sized = if (width != null) {
        modifier.size(width, height)
    } else {
        modifier.fillMaxWidth().height(height)
    }

    Box(
        modifier = sized
            .clip(RoundedCornerShape(cornerRadius))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f * alpha))
            .clearAndSetSemantics { }
    )
}
