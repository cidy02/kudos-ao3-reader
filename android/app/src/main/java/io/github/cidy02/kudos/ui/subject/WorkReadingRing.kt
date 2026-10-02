package io.github.cidy02.kudos.ui.subject

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

/**
 * `WorkProgressRing`, or while a download is queued the same ring sweeping and
 * labelled Downloading. Android's download queue has no byte fraction, so the
 * sweep is indeterminate until the file lands.
 * Port of `WorkReadingOrDownloadRing` (`SubjectSurface.swift`).
 */
@Composable
fun WorkReadingOrDownloadRing(
    downloading: Boolean,
    progress: Double?,
    state: String?,
    modifier: Modifier = Modifier,
    diameter: Dp = SubjectMetrics.ringDiameter,
    tint: androidx.compose.ui.graphics.Color? = null
) {
    if (downloading) {
        val transition = rememberInfiniteTransition(label = "downloadRing")
        val sweep by transition.animateFloat(
            initialValue = 0.08f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 1400, easing = LinearEasing),
                repeatMode = RepeatMode.Restart
            ),
            label = "downloadSweep"
        )
        WorkProgressRing(
            progress = sweep.toDouble(),
            state = if (state == null) null else "Downloading",
            modifier = modifier,
            diameter = diameter,
            tint = tint
        )
    } else if (progress != null) {
        WorkProgressRing(
            progress = progress,
            state = state,
            modifier = modifier,
            diameter = diameter,
            tint = tint
        )
    }
}

/**
 * Greys a card while its work downloads: saturation 0, then RGB scaled by 0.88
 * (iOS `brightness(-0.12)` has no Compose twin). [amount] is 0…1 so the change
 * can animate.
 */
fun Modifier.downloadDimmed(amount: Float): Modifier {
    if (amount <= 0.001f) return this
    val saturation = 1f - amount
    val scale = 1f - 0.12f * amount
    val matrix = ColorMatrix().apply { setToSaturation(saturation) }
    matrix.timesAssign(
        ColorMatrix(
            floatArrayOf(
                scale, 0f, 0f, 0f, 0f,
                0f, scale, 0f, 0f, 0f,
                0f, 0f, scale, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            )
        )
    )
    return graphicsLayer { colorFilter = ColorFilter.colorMatrix(matrix) }
}
