package io.github.cidy02.kudos.ui.components

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.hsb
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.withOpacity
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * What a stack of covers stands for (port of iOS `CoverStackKind`, T-461):
 * - [Collection]: a tilted pile with the collection's own card in front, works tilted behind it,
 *   and a plain corner tab.
 * - [Queue]: covers stacked straight up behind the front one, each a peek higher and a step
 *   narrower, with a numbered-list corner tab.
 */
enum class CoverStackKind {
    Collection,
    Queue
}

/**
 * Pure, Compose-free geometry for a collection or queue cover stack (port of iOS `CoverStackLayout`).
 * Guarantees that the front card, every kept back card's [Back.drawnBounds], and the corner [ribbon]
 * stay inside the frame.
 */
class CoverStackLayout(
    val kind: CoverStackKind,
    size: Size,
    backCount: Int
) {
    constructor(
        kind: CoverStackKind,
        width: Double,
        height: Double,
        backCount: Int
    ) : this(kind, Size(width, height), backCount)

    data class Size(val width: Double, val height: Double) {
        constructor(width: Number, height: Number) : this(width.toDouble(), height.toDouble())
    }

    data class Rect(
        val x: Double,
        val y: Double,
        val width: Double,
        val height: Double
    ) {
        val minX: Double get() = x
        val minY: Double get() = y
        val maxX: Double get() = x + width
        val maxY: Double get() = y + height
        val midX: Double get() = x + width / 2.0
        val midY: Double get() = y + height / 2.0
        val size: Size get() = Size(width, height)

        fun insetBy(dx: Double, dy: Double): Rect =
            Rect(x = x + dx, y = y + dy, width = width - 2.0 * dx, height = height - 2.0 * dy)

        fun contains(other: Rect): Boolean =
            other.minX >= minX && other.minY >= minY && other.maxX <= maxX && other.maxY <= maxY
    }

    data class Back(
        val frame: Rect,
        /** Degrees clockwise about the frame's bottom-leading corner; 0 in a queue. */
        val rotation: Double,
        /** How much darker than its own colour the card is drawn, 0..1. */
        val dimming: Double
    ) {
        /** Axis-aligned bounding box after rotating [frame] clockwise about `(frame.minX, frame.maxY)`. */
        val drawnBounds: Rect
            get() {
                val angle = rotation * PI / 180.0
                val cosine = cos(angle)
                val sine = sin(angle)
                val corners = listOf(
                    0.0 to 0.0,
                    frame.width to 0.0,
                    0.0 to -frame.height,
                    frame.width to -frame.height
                ).map { (cx, cy) ->
                    (frame.minX + cx * cosine - cy * sine) to (frame.maxY + cx * sine + cy * cosine)
                }
                val minX = corners.minOf { it.first }
                val maxX = corners.maxOf { it.first }
                val minY = corners.minOf { it.second }
                val maxY = corners.maxOf { it.second }
                return Rect(x = minX, y = minY, width = maxX - minX, height = maxY - minY)
            }
    }

    val front: Rect
    /** Nearest first (`0` = right behind front, `1` = furthest back). */
    val backs: List<Back>
    val cornerRadius: Double
    /** Corner tab in [front]-local coordinates, or `null` when the cover is narrower than 64dp. */
    val ribbon: Rect?

    init {
        val width = max(0.0, size.width)
        val height = max(0.0, size.height)
        val count = min(max(0, backCount), maxBacks)
        val hasTab = min(width, height * coverAspect) >= 64.0
        val computedFront: Rect
        val piled: List<Back>

        when (kind) {
            CoverStackKind.Queue -> {
                val peek = if (count > 0) min(max(4.0, height * 0.07), height * 0.1) else 0.0
                val frontHeight = height - peek * count.toDouble()
                val coverWidth = min(width, frontHeight * coverAspect)
                val frontLeft = (width - coverWidth) / 2.0
                computedFront = Rect(
                    x = frontLeft,
                    y = peek * count.toDouble(),
                    width = coverWidth,
                    height = frontHeight
                )
                piled = (0 until count).map { index ->
                    val step = (index + 1).toDouble()
                    val backWidth = coverWidth * (1.0 - 0.1 * step)
                    Back(
                        frame = Rect(
                            x = frontLeft + (coverWidth - backWidth) / 2.0,
                            y = peek * (count.toDouble() - step),
                            width = backWidth,
                            height = frontHeight
                        ),
                        rotation = 0.0,
                        dimming = 0.12 * step
                    )
                }
            }

            CoverStackKind.Collection -> {
                val turn = if (hasTab) 5.0 else 3.0
                fun pile(coverWidth: Double): List<Back> {
                    val shift = if (count > 0) max(4.0, coverWidth * 0.12) else 0.0
                    return (0 until count).map { index ->
                        val step = (index + 1).toDouble()
                        val scale = 1.0 - 0.04 * step
                        val degrees = turn * step
                        val sine = sin(degrees * PI / 180.0)
                        val cosine = cos(degrees * PI / 180.0)
                        val backWidth = coverWidth * scale
                        val backHeight = max(0.0, min(height * scale, (height - backWidth * sine) / cosine))
                        Back(
                            frame = Rect(
                                x = coverWidth - backWidth + step * shift,
                                y = height - backHeight - backWidth * sine,
                                width = backWidth,
                                height = backHeight
                            ),
                            rotation = degrees,
                            dimming = 0.1 * step
                        )
                    }
                }
                fun reach(coverWidth: Double): Double =
                    pile(coverWidth).fold(coverWidth) { acc, back -> max(acc, back.drawnBounds.maxX) }

                val widest = min(width, height * coverAspect)
                var coverWidth = widest
                if (reach(widest) > width) {
                    var fits = widest / 2.0
                    var tooWide = widest
                    repeat(24) {
                        val middle = (fits + tooWide) / 2.0
                        if (reach(middle) <= width) fits = middle else tooWide = middle
                    }
                    coverWidth = fits
                }
                computedFront = Rect(x = 0.0, y = 0.0, width = coverWidth, height = height)
                piled = pile(coverWidth)
            }
        }

        val bounds = Rect(x = 0.0, y = 0.0, width = width, height = height).insetBy(dx = -0.01, dy = -0.01)
        front = computedFront
        backs = piled.takeWhile { bounds.contains(it.drawnBounds) }
        cornerRadius = max(4.0, 0.09 * front.width)
        ribbon = if (hasTab) {
            val tabWidth = front.width * 0.2
            Rect(
                x = front.width - front.width * 0.09 - tabWidth,
                y = 0.0,
                width = tabWidth,
                height = tabWidth * 1.45
            )
        } else {
            null
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CoverStackLayout) return false
        return kind == other.kind &&
            front == other.front &&
            backs == other.backs &&
            cornerRadius == other.cornerRadius &&
            ribbon == other.ribbon
    }

    override fun hashCode(): Int {
        var result = kind.hashCode()
        result = 31 * result + front.hashCode()
        result = 31 * result + backs.hashCode()
        result = 31 * result + cornerRadius.hashCode()
        result = 31 * result + (ribbon?.hashCode() ?: 0)
        return result
    }

    companion object {
        const val coverAspect: Double = 0.72
        const val maxBacks: Int = 2
    }
}

/**
 * Port of iOS `StackedWorkCover`: draws a collection pile or queue stack using [CoverStackLayout].
 * The outer box is never clipped because [CoverStackLayout] keeps every card inside `[0..width, 0..height]`.
 * Purely decorative (`clearAndSetSemantics {}`); the enclosing card supplies the spoken label.
 */
@Composable
fun CoverStack(
    kind: CoverStackKind,
    width: Dp,
    height: Dp,
    backs: List<SavedWork>,
    modifier: Modifier = Modifier,
    face: @Composable (CoverStackLayout) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val layout = remember(kind, width, height, backs.size) {
        CoverStackLayout(
            kind = kind,
            width = width.value.toDouble(),
            height = height.value.toDouble(),
            backCount = backs.size
        )
    }
    val shape = RoundedCornerShape(layout.cornerRadius.dp)
    Box(
        modifier = modifier
            .size(width = width, height = height)
            .clearAndSetSemantics {}
    ) {
        for (index in layout.backs.indices.reversed()) {
            val back = layout.backs[index]
            BackCover(
                work = backs[index],
                dimming = back.dimming,
                shape = shape,
                modifier = Modifier
                    .offset(x = back.frame.minX.dp, y = back.frame.minY.dp)
                    .size(width = back.frame.width.dp, height = back.frame.height.dp)
                    .graphicsLayer {
                        transformOrigin = TransformOrigin(0f, 1f)
                        rotationZ = back.rotation.toFloat()
                    }
            )
        }
        Box(
            modifier = Modifier
                .offset(x = layout.front.minX.dp, y = layout.front.minY.dp)
                .size(width = layout.front.width.dp, height = layout.front.height.dp)
                .then(stackFrontShadow(tokens.theme, shape))
                .clip(shape)
                .border(0.5.dp, tokens.glassStroke(0.12), shape)
        ) {
            face(layout)
            layout.ribbon?.let { rect ->
                CornerTab(
                    kind = kind,
                    rect = rect,
                    modifier = Modifier
                        .offset(x = rect.minX.dp, y = rect.minY.dp)
                        .size(width = rect.width.dp, height = rect.height.dp)
                )
            }
        }
    }
}

/**
 * Convenience overload for a collection or queue's own card in front (colour gradient + serif initial).
 */
@Composable
fun CoverStack(
    kind: CoverStackKind,
    name: String,
    hue: Double,
    pickedHex: String?,
    backs: List<SavedWork>,
    width: Dp,
    height: Dp,
    modifier: Modifier = Modifier
) {
    CoverStack(
        kind = kind,
        width = width,
        height = height,
        backs = backs,
        modifier = modifier
    ) { layout ->
        CoverStackNameFace(
            kind = kind,
            name = name,
            hue = hue,
            pickedHex = pickedHex,
            coverWidth = layout.front.width.dp
        )
    }
}

@Composable
fun CoverStackNameFace(
    kind: CoverStackKind,
    name: String,
    hue: Double,
    pickedHex: String?,
    coverWidth: Dp,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val initial = remember(name) {
        name.trim().firstOrNull()?.uppercaseChar()?.toString().orEmpty()
    }
    val colors = remember(kind, tokens.theme, hue, pickedHex) {
        when (kind) {
            CoverStackKind.Collection -> {
                val (start, end) = carouselCollectionGradient(tokens.theme, hue, pickedHex)
                listOf(start, end)
            }
            CoverStackKind.Queue -> {
                val base = pickedHex?.let(::parseStoredColor)
                    ?: SubjectPalette.fromHue(hue, tokens.theme).accent
                listOf(base.mixWith(Color.Black, 0.38), base)
            }
        }
    }
    val paint = remember {
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb((0.15f * 255).toInt(), 255, 255, 255)
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
        }
    }
    Canvas(modifier = modifier.fillMaxSize()) {
        drawRect(
            brush = Brush.linearGradient(
                colors = colors,
                start = Offset(size.width * 0.2887f, size.height * 0.0468f),
                end = Offset(size.width * 0.7113f, size.height * 0.9532f)
            )
        )
        if (initial.isNotEmpty()) {
            val widthPx = coverWidth.toPx()
            paint.textSize = widthPx * 1.05f
            drawContext.canvas.nativeCanvas.drawText(
                initial,
                -widthPx * 0.06f,
                size.height + widthPx * 0.11f,
                paint
            )
        }
    }
}

@Composable
private fun BackCover(
    work: SavedWork,
    dimming: Double,
    shape: RoundedCornerShape,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val hue = remember(work.workFandoms, work.title) {
        workArtHueDegrees(work.workFandoms, work.title)
    }
    val colors = remember(hue) {
        listOf(
            hslColor(hue.toDouble(), saturation = 0.46, lightness = 0.27),
            hslColor(((hue + 22) % 360).toDouble(), saturation = 0.50, lightness = 0.41)
        )
    }
    Box(
        modifier = modifier
            .clip(shape)
            .border(0.5.dp, tokens.glassStroke(0.10), shape)
    ) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(
                brush = Brush.linearGradient(
                    colors = colors,
                    start = Offset(size.width * 0.2887f, size.height * 0.0468f),
                    end = Offset(size.width * 0.7113f, size.height * 0.9532f)
                )
            )
            if (dimming > 0.0) {
                drawRect(Color.Black.copy(alpha = dimming.toFloat().coerceIn(0f, 1f)))
            }
        }
    }
}

@Composable
private fun CornerTab(
    kind: CoverStackKind,
    rect: CoverStackLayout.Rect,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        val ribbonPath = Path().apply {
            moveTo(0f, 0f)
            lineTo(w, 0f)
            lineTo(w, h)
            lineTo(w * 0.5f, h * 0.8f)
            lineTo(0f, h)
            close()
        }
        drawPath(ribbonPath, Color.Black.copy(alpha = 0.24f))

        if (kind == CoverStackKind.Queue && rect.width > 0.0) {
            // Centred numbered-list glyph (`list.number` on iOS) inside the top square of the ribbon.
            val iconBox = w * 0.6f
            val left = (w - iconBox) * 0.5f
            val top = w * 0.2f
            val iconHeight = iconBox * 0.78f
            val dotRadius = max(1.2f, iconHeight * 0.09f)
            val barHeight = max(1.3f, iconHeight * 0.14f)
            val gap = max(1.5f, iconBox * 0.14f)
            val barLeft = left + dotRadius * 2f + gap
            val barWidth = (left + iconBox - barLeft).coerceAtLeast(1f)
            val ink = Color.White.copy(alpha = 0.92f)
            for (row in 0 until 3) {
                val cy = top + dotRadius + row * ((iconHeight - dotRadius * 2f) / 2f)
                drawCircle(
                    color = ink,
                    radius = dotRadius,
                    center = Offset(left + dotRadius, cy)
                )
                drawRoundRect(
                    color = ink,
                    topLeft = Offset(barLeft, cy - barHeight * 0.5f),
                    size = androidx.compose.ui.geometry.Size(barWidth, barHeight),
                    cornerRadius = CornerRadius(barHeight * 0.5f, barHeight * 0.5f)
                )
            }
        }
    }
}

internal fun carouselCollectionGradient(
    theme: ReaderTheme,
    hue: Double,
    pickedHex: String? = null
): Pair<Color, Color> {
    val picked = pickedHex?.let(::parseStoredColor)
    if (picked != null) {
        return picked to picked.mixWith(Color.Black, 0.30)
    }
    return when (theme) {
        ReaderTheme.Dark, ReaderTheme.Oled ->
            hsb(hue, 0.50, 0.80) to hsb(hue, 0.62, 0.55)
        ReaderTheme.Light ->
            hsb(hue, 0.45, 0.85) to hsb(hue, 0.58, 0.62)
        ReaderTheme.Sepia ->
            hsb(hue, 0.40, 0.80) to hsb(hue, 0.52, 0.58)
    }
}

private fun workArtHueDegrees(fandoms: List<String>, title: String): Int {
    val familyHue = (HomeFacts.workHue(fandoms, title) * 360.0).toInt()
    val seed = title.fold(0) { acc, ch -> (acc * 31 + ch.code) and 0x7fffffff }
    val shade = (seed % 29) - 14
    return (familyHue + shade + 360) % 360
}

private fun Color.mixWith(other: Color, fraction: Double): Color {
    val t = fraction.toFloat().coerceIn(0f, 1f)
    return Color(
        red = red + (other.red - red) * t,
        green = green + (other.green - green) * t,
        blue = blue + (other.blue - blue) * t,
        alpha = alpha + (other.alpha - alpha) * t
    )
}

private fun hslColor(hue: Double, saturation: Double, lightness: Double): Color {
    val chroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation
    val normalizedHue = ((hue % 360.0) + 360.0) % 360.0
    val sector = normalizedHue / 60.0
    val second = chroma * (1.0 - abs(sector % 2.0 - 1.0))
    val (r, g, b) = when {
        sector < 1.0 -> Triple(chroma, second, 0.0)
        sector < 2.0 -> Triple(second, chroma, 0.0)
        sector < 3.0 -> Triple(0.0, chroma, second)
        sector < 4.0 -> Triple(0.0, second, chroma)
        sector < 5.0 -> Triple(second, 0.0, chroma)
        else -> Triple(chroma, 0.0, second)
    }
    val match = lightness - chroma / 2.0
    return Color(
        red = (r + match).toFloat().coerceIn(0f, 1f),
        green = (g + match).toFloat().coerceIn(0f, 1f),
        blue = (b + match).toFloat().coerceIn(0f, 1f)
    )
}

private fun stackFrontShadow(theme: ReaderTheme, shape: RoundedCornerShape): Modifier {
    val color = when (theme) {
        ReaderTheme.Oled -> return Modifier
        ReaderTheme.Dark -> Color.Black.withOpacity(0.34)
        ReaderTheme.Light -> Color.Black.withOpacity(0.13)
        ReaderTheme.Sepia -> Color(red = 0.34f, green = 0.22f, blue = 0.08f).withOpacity(0.22)
    }
    return Modifier.shadow(8.dp, shape, clip = false, ambientColor = color, spotColor = color)
}
