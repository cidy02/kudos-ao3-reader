package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp

/** AO3's fixed required-tag palette, shared with iOS T-479. */
object AO3TagPalette {
    val General = Color(0xFF2F8F3A)
    val Teen = Color(0xFFF5C400)
    val Mature = Color(0xFFE07000)
    val Explicit = Color(0xFFC8102E)
    val FemaleFemale = Color(0xFFD2264B)
    val FemaleMale = Color(0xFFB3127A)
    val MaleMale = Color(0xFF1E63C8)
    val Other = Color(0xFF1C1C1E)
    val OtherOnDark = Color(0xFF48484A)
    val TeenInk = Color(0xFF3A2C00)
    val TeenTextOnLight = Color(0xFF8C6600)

    val AbsentFill = Color(0xFFE6E6EB)
    val AbsentInk = Color(0xFF6C6C70)
    val AbsentFillDark = Color(0xFF3A3A3C)
    val AbsentInkDark = Color(0xFFAEAEB2)

    val WipFill = Color(0xFFFFE6C2)
    val WipInk = Color(0xFFB35A00)
    val WipFillDark = Color(0xFF4A2E0A)
    val WipInkDark = Color(0xFFFFB04D)
}

sealed interface WorkSymbolMark {
    data class Shield(val letter: String) : WorkSymbolMark
    data object Gen : WorkSymbolMark
    data object FemaleFemale : WorkSymbolMark
    data object FemaleMale : WorkSymbolMark
    data object MaleMale : WorkSymbolMark
    data object Other : WorkSymbolMark
    data object Multi : WorkSymbolMark
    data object Dash : WorkSymbolMark
    data object Exclamation : WorkSymbolMark
    data object Question : WorkSymbolMark
    data object Check : WorkSymbolMark
    data object HalfRing : WorkSymbolMark
}

/** Plain tile data so palette/state mapping is unit-testable without Compose rendering. */
data class WorkSymbolTile(val mark: WorkSymbolMark, val fill: Color, val ink: Color) {
    companion object {
        fun rating(rating: String?, dark: Boolean): WorkSymbolTile = when (rating?.trim().orEmpty()) {
            "General Audiences" -> solid(WorkSymbolMark.Shield("G"), AO3TagPalette.General)
            "Teen And Up Audiences" -> WorkSymbolTile(
                WorkSymbolMark.Shield("T"), AO3TagPalette.Teen, AO3TagPalette.TeenInk
            )
            "Mature" -> solid(WorkSymbolMark.Shield("M"), AO3TagPalette.Mature)
            "Explicit" -> solid(WorkSymbolMark.Shield("E"), AO3TagPalette.Explicit)
            else -> absent(WorkSymbolMark.Shield("?"), dark)
        }

        fun category(categories: List<String>, dark: Boolean): WorkSymbolTile {
            val recognized = categories.map { it.trim() }.filter { AO3StatusTint.category(it) != null }
            if (recognized.isEmpty()) return absent(WorkSymbolMark.Dash, dark)
            if (recognized.size > 1) return multi()
            return when (recognized.single()) {
                "F/F" -> solid(WorkSymbolMark.FemaleFemale, AO3TagPalette.FemaleFemale)
                "F/M" -> solid(WorkSymbolMark.FemaleMale, AO3TagPalette.FemaleMale)
                "M/M" -> solid(WorkSymbolMark.MaleMale, AO3TagPalette.MaleMale)
                "Gen" -> solid(WorkSymbolMark.Gen, AO3TagPalette.General)
                "Other" -> solid(
                    WorkSymbolMark.Other,
                    if (dark) AO3TagPalette.OtherOnDark else AO3TagPalette.Other
                )
                else -> multi() // The literal Multi tag.
            }
        }

        fun warnings(warnings: List<String>, dark: Boolean): WorkSymbolTile {
            if (warnings.any { it.contains("Chose Not To Use", ignoreCase = true) }) {
                return solid(WorkSymbolMark.Question, AO3TagPalette.Mature)
            }
            val real = warnings.filter {
                it.isNotBlank() &&
                    !it.contains("No Archive Warnings", ignoreCase = true) &&
                    !it.contains("Chose Not To Use", ignoreCase = true)
            }
            return if (real.isEmpty()) absent(WorkSymbolMark.Dash, dark)
            else solid(WorkSymbolMark.Exclamation, AO3TagPalette.Explicit)
        }

        fun completion(isComplete: Boolean?, dark: Boolean): WorkSymbolTile = when (isComplete) {
            true -> solid(WorkSymbolMark.Check, AO3TagPalette.General)
            false -> WorkSymbolTile(
                WorkSymbolMark.HalfRing,
                if (dark) AO3TagPalette.WipFillDark else AO3TagPalette.WipFill,
                if (dark) AO3TagPalette.WipInkDark else AO3TagPalette.WipInk
            )
            null -> absent(WorkSymbolMark.Question, dark)
        }

        private fun solid(mark: WorkSymbolMark, fill: Color) = WorkSymbolTile(mark, fill, Color.White)

        private fun absent(mark: WorkSymbolMark, dark: Boolean) = WorkSymbolTile(
            mark,
            if (dark) AO3TagPalette.AbsentFillDark else AO3TagPalette.AbsentFill,
            if (dark) AO3TagPalette.AbsentInkDark else AO3TagPalette.AbsentInk
        )

        private fun multi() = WorkSymbolTile(WorkSymbolMark.Multi, Color.Transparent, Color.Transparent)
    }
}

@Composable
fun WorkSymbolTileView(tile: WorkSymbolTile, size: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(size)
            .clip(RoundedCornerShape(size * WorkSymbolGeometry.CornerRadiusRatio))
            .background(tile.fill),
        contentAlignment = Alignment.Center
    ) {
        if (tile.mark == WorkSymbolMark.Multi) {
            MultiQuadrants(Modifier.fillMaxSize())
        } else {
            val ratio = if (tile.mark is WorkSymbolMark.Shield) {
                WorkSymbolGeometry.ShieldBoxRatio
            } else {
                WorkSymbolGeometry.GlyphBoxRatio
            }
            WorkSymbolMarkView(
                mark = tile.mark,
                tint = tile.ink,
                shieldCutout = tile.fill,
                modifier = Modifier.size(size * ratio)
            )
        }
    }
}

/** The vector mark alone, also used by the text chips. */
@Composable
fun WorkSymbolMarkView(
    mark: WorkSymbolMark,
    tint: Color,
    modifier: Modifier = Modifier,
    shieldCutout: Color = Color.Transparent
) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        when (mark) {
            is WorkSymbolMark.Shield -> {
                Canvas(Modifier.fillMaxSize()) { drawWorkSymbol(mark, tint) }
                val density = LocalDensity.current
                Text(
                    text = mark.letter,
                    color = shieldCutout,
                    fontSize = with(density) { (maxWidth * (0.36f / WorkSymbolGeometry.ShieldBoxRatio)).toSp() },
                    fontWeight = FontWeight.Black,
                    textAlign = TextAlign.Center,
                    style = CenteredWorkSymbolText,
                    modifier = Modifier.offset(y = maxHeight * WorkSymbolGeometry.ShieldBodyOffsetRatio)
                )
            }
            WorkSymbolMark.Exclamation, WorkSymbolMark.Question -> Text(
                text = if (mark == WorkSymbolMark.Exclamation) "!" else "?",
                color = tint,
                fontSize = with(LocalDensity.current) { (maxWidth * 0.88f).toSp() },
                fontWeight = FontWeight.Black,
                textAlign = TextAlign.Center,
                style = CenteredWorkSymbolText
            )
            WorkSymbolMark.Multi -> Unit
            else -> Canvas(Modifier.fillMaxSize()) { drawWorkSymbol(mark, tint) }
        }
    }
}

private object WorkSymbolGeometry {
    const val CornerRadiusRatio = 0.24f
    const val GlyphBoxRatio = 0.68f
    const val ShieldBoxRatio = 0.84f
    const val ShieldBodyOffsetRatio = (11.56f - 12f) / 24f
}

private val CenteredWorkSymbolText = TextStyle(
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.Both
    )
)

@Composable
private fun MultiQuadrants(modifier: Modifier) {
    Canvas(modifier) {
        val halfWidth = size.width / 2f
        val halfHeight = size.height / 2f
        drawRect(AO3TagPalette.General, size = androidx.compose.ui.geometry.Size(halfWidth, halfHeight))
        drawRect(
            AO3TagPalette.FemaleMale,
            topLeft = Offset(halfWidth, 0f),
            size = androidx.compose.ui.geometry.Size(halfWidth, halfHeight)
        )
        drawRect(
            AO3TagPalette.FemaleFemale,
            topLeft = Offset(0f, halfHeight),
            size = androidx.compose.ui.geometry.Size(halfWidth, halfHeight)
        )
        drawRect(
            AO3TagPalette.MaleMale,
            topLeft = Offset(halfWidth, halfHeight),
            size = androidx.compose.ui.geometry.Size(halfWidth, halfHeight)
        )
    }
}

private fun DrawScope.drawWorkSymbol(mark: WorkSymbolMark, color: Color) {
    val scale = size.minDimension / 24f
    val shift = when (mark) {
        WorkSymbolMark.FemaleFemale -> Offset(0f, 0.8f)
        WorkSymbolMark.MaleMale -> Offset(0.78f, -0.98f)
        WorkSymbolMark.Other -> Offset(0f, -0.7f)
        else -> Offset.Zero
    }
    fun point(x: Float, y: Float) = Offset((x + shift.x) * scale, (y + shift.y) * scale)
    fun stroke(width: Float, join: StrokeJoin = StrokeJoin.Round) = Stroke(
        width = width * scale,
        cap = StrokeCap.Round,
        join = join
    )
    fun polyline(vararg points: Pair<Float, Float>, width: Float = 2.2f, join: StrokeJoin = StrokeJoin.Round) {
        val path = Path().apply {
            val first = points.first()
            moveTo(point(first.first, first.second).x, point(first.first, first.second).y)
            points.drop(1).forEach { (x, y) -> lineTo(point(x, y).x, point(x, y).y) }
        }
        drawPath(path, color, style = stroke(width, join))
    }
    fun ring(x: Float, y: Float, radius: Float, width: Float = 2.2f) {
        drawCircle(color, radius * scale, point(x, y), style = stroke(width))
    }
    fun male(centerX: Float, centerY: Float, radius: Float, arrow: Float, head: Float) {
        val diagonal = 0.70710677f
        val tipX = centerX + (radius + arrow) * diagonal
        val tipY = centerY - (radius + arrow) * diagonal
        ring(centerX, centerY, radius)
        polyline(
            (centerX + radius * diagonal) to (centerY - radius * diagonal),
            tipX to tipY
        )
        polyline((tipX - head) to tipY, tipX to tipY, tipX to (tipY + head), join = StrokeJoin.Miter)
    }

    when (mark) {
        is WorkSymbolMark.Shield -> {
            val path = Path().apply {
                moveTo(point(12f, 2.6f).x, point(12f, 2.6f).y)
                lineTo(point(4.4f, 5.5f).x, point(4.4f, 5.5f).y)
                lineTo(point(4.4f, 11.5f).x, point(4.4f, 11.5f).y)
                cubicTo(
                    point(4.4f, 16.2f).x, point(4.4f, 16.2f).y,
                    point(7.6f, 20.1f).x, point(7.6f, 20.1f).y,
                    point(12f, 21.4f).x, point(12f, 21.4f).y
                )
                cubicTo(
                    point(16.4f, 20.1f).x, point(16.4f, 20.1f).y,
                    point(19.6f, 16.2f).x, point(19.6f, 16.2f).y,
                    point(19.6f, 11.5f).x, point(19.6f, 11.5f).y
                )
                lineTo(point(19.6f, 5.5f).x, point(19.6f, 5.5f).y)
                close()
            }
            drawPath(path, color)
            drawPath(path, color, style = stroke(1.4f))
        }
        WorkSymbolMark.Check -> polyline(5f to 12.5f, 9.6f to 17.1f, 19.2f to 7.4f, width = 3.4f)
        WorkSymbolMark.HalfRing -> {
            clipRect(right = size.width / 2f) { drawCircle(color, 8.2f * scale, point(12f, 12f)) }
            ring(12f, 12f, 8.2f, 2.6f)
        }
        WorkSymbolMark.Gen -> {
            ring(12f, 12f, 8f, 2.4f)
            drawCircle(color, 2.6f * scale, point(12f, 12f))
        }
        WorkSymbolMark.Dash -> polyline(6.53f to 12f, 17.47f to 12f, width = 3.88f)
        WorkSymbolMark.FemaleFemale -> {
            ring(8f, 8.4f, 4.8f)
            polyline(8f to 13.2f, 8f to 18.8f)
            ring(16f, 8.4f, 4.8f)
            polyline(16f to 13.2f, 16f to 18.8f)
            polyline(5.4f to 16f, 18.6f to 16f)
        }
        WorkSymbolMark.FemaleMale -> {
            ring(9.2f, 13.4f, 4.4f)
            polyline(9.2f to 17.8f, 9.2f to 22f)
            polyline(6.6f to 20f, 11.8f to 20f)
            male(13.9f, 8.7f, 4.4f, 3.8f, 3.4f)
        }
        WorkSymbolMark.MaleMale -> {
            male(7.6f, 11.2f, 4.8f, 4.6f, 3.6f)
            male(13f, 16.6f, 4.8f, 4.6f, 3.6f)
        }
        WorkSymbolMark.Other -> {
            polyline(3.6f to 3.6f, 5.8f to 3.6f, 5.8f to 14.4f, 3.6f to 14.4f)
            polyline(20.4f to 3.6f, 18.2f to 3.6f, 18.2f to 14.4f, 20.4f to 14.4f)
            polyline(5.8f to 9f, 18.2f to 9f)
            polyline(12f to 3.6f, 12f to 16f)
            ring(12f, 18.9f, 2.9f)
        }
        WorkSymbolMark.Multi, WorkSymbolMark.Exclamation, WorkSymbolMark.Question -> Unit
    }
}
