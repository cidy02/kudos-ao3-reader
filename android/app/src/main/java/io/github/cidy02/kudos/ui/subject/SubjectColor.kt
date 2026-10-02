package io.github.cidy02.kudos.ui.subject

import androidx.compose.ui.graphics.Color
import kotlin.math.max
import kotlin.math.pow

/**
 * sRGB hue / saturation / brightness, matching SwiftUI
 * `Color(hue:saturation:brightness:)`. [hue] is a 0…1 fraction, not degrees.
 */
fun hsb(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1.0): Color {
    val wrapped = ((hue % 1.0) + 1.0) % 1.0
    val s = saturation.coerceIn(0.0, 1.0)
    val v = brightness.coerceIn(0.0, 1.0)
    val sector = wrapped * 6.0
    val index = sector.toInt().mod(6)
    val fraction = sector - sector.toInt()
    val p = v * (1.0 - s)
    val q = v * (1.0 - fraction * s)
    val t = v * (1.0 - (1.0 - fraction) * s)
    val (red, green, blue) = when (index) {
        0 -> Triple(v, t, p)
        1 -> Triple(q, v, p)
        2 -> Triple(p, v, t)
        3 -> Triple(p, q, v)
        4 -> Triple(t, p, v)
        else -> Triple(v, p, q)
    }
    return Color(
        red = red.toFloat(),
        green = green.toFloat(),
        blue = blue.toFloat(),
        alpha = alpha.toFloat().coerceIn(0f, 1f)
    )
}

/**
 * SwiftUI `Color.opacity`, which multiplies the existing alpha.
 * sRGB [Color] stores each channel in 8 bits, so the result is within 1/255 of the ideal.
 */
fun Color.withOpacity(opacity: Double): Color =
    copy(alpha = (alpha * opacity.toFloat()).coerceIn(0f, 1f))

/**
 * Hue as a 0…1 fraction, matching `Color.hueComponent`.
 * Grey has no hue; UIKit reports 0 for it, and so does this.
 */
fun Color.hueComponent(): Double {
    val r = red.toDouble()
    val g = green.toDouble()
    val b = blue.toDouble()
    val maxChannel = max(r, max(g, b))
    val minChannel = minOf(r, g, b)
    val delta = maxChannel - minChannel
    if (delta == 0.0) return 0.0
    val sector = when (maxChannel) {
        r -> ((g - b) / delta).mod(6.0)
        g -> ((b - r) / delta) + 2.0
        else -> ((r - g) / delta) + 4.0
    }
    return sector / 6.0
}

/** WCAG relative luminance. [SubjectPalette.label] crosses over at about 0.179. */
fun Color.relativeLuminance(): Double {
    fun channel(component: Float): Double {
        val value = component.toDouble()
        return if (value <= 0.03928) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
}
