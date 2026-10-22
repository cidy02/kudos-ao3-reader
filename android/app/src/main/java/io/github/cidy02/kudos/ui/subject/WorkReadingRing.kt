package io.github.cidy02.kudos.ui.subject

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

/** Reading progress, replaced by this work's own download fraction while it is active. */
@Composable
fun WorkReadingOrDownloadRing(
    downloadFraction: Double?,
    progress: Double?,
    state: String?,
    modifier: Modifier = Modifier,
    diameter: Dp = SubjectMetrics.ringDiameter,
    tint: androidx.compose.ui.graphics.Color? = null,
    showsZeroPercent: Boolean = false
) {
    if (downloadFraction != null) {
        WorkProgressRing(
            progress = downloadFraction,
            state = if (state == null) null else "Downloading",
            modifier = modifier,
            diameter = diameter,
            tint = tint,
            showsZeroPercent = true
        )
    } else if (progress != null) {
        WorkProgressRing(
            progress = progress,
            state = state,
            modifier = modifier,
            diameter = diameter,
            tint = tint,
            showsZeroPercent = showsZeroPercent
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
