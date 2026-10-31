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

data class WorkSymbolBackingColor(
    val red: Float,
    val green: Float,
    val blue: Float,
    val alpha: Float
) {
    val color: Color get() = Color(red = red, green = green, blue = blue, alpha = alpha)

    companion object {
        fun board(theme: io.github.cidy02.kudos.ui.subject.ReaderTheme): WorkSymbolBackingColor = when (theme) {
            io.github.cidy02.kudos.ui.subject.ReaderTheme.Sepia ->
                WorkSymbolBackingColor(120f / 255f, 92f / 255f, 56f / 255f, 0.12f)
            io.github.cidy02.kudos.ui.subject.ReaderTheme.Light ->
                WorkSymbolBackingColor(118f / 255f, 118f / 255f, 128f / 255f, 0.12f)
            io.github.cidy02.kudos.ui.subject.ReaderTheme.Dark,
            io.github.cidy02.kudos.ui.subject.ReaderTheme.Oled ->
                WorkSymbolBackingColor(118f / 255f, 118f / 255f, 128f / 255f, 0.24f)
        }
    }
}

internal object WorkSymbolGeometry {
    const val CornerRadiusRatio = 0.24f
    const val GapRatio = 0.12f
    const val BackingPaddingRatio = 0.27f
    const val BackingRadiusRatio = 0.58f
    const val GlyphBoxRatio = 0.68f
    const val ShieldBoxRatio = 0.84f
    const val ShieldBodyOffsetRatio = (11.56f - 12f) / 24f

    /** Two tiles and the gap between them. iOS `WorkStatusIconGrid.gridHeight`. */
    fun gridExtent(tileSize: Float): Float = tileSize * (2f + GapRatio)

    /** Symbols board: `round(tile × 0.27)`. */
    fun backingPadding(tileSize: Float): Float = kotlin.math.round(tileSize * BackingPaddingRatio)

    /** Symbols board: `round(tile × 0.58)`. */
    fun backingCornerRadius(tileSize: Float): Float = kotlin.math.round(tileSize * BackingRadiusRatio)

    /** Full 2×2 only. A strip stays bare even when `backed` is left on. */
    fun drawsBacking(
        arrangement: io.github.cidy02.kudos.ui.subject.HomeStatusArrangement,
        backed: Boolean
    ): Boolean = arrangement == io.github.cidy02.kudos.ui.subject.HomeStatusArrangement.Grid && backed

    /** Edge of the square a row lays out, including backing padding on both sides when backed. */
    fun outerSide(tileSize: Float, backed: Boolean = true): Float {
        val tiles = gridExtent(tileSize)
        if (!drawsBacking(io.github.cidy02.kudos.ui.subject.HomeStatusArrangement.Grid, backed)) return tiles
        return tiles + 2f * backingPadding(tileSize)
    }

    fun backingFill(theme: io.github.cidy02.kudos.ui.subject.ReaderTheme): Color =
        WorkSymbolBackingColor.board(theme).color

    /**
     * Translation, in the 24-unit drawing grid, that puts the mark's centreline
     * bounding box on (12, 12). A uniform stroke does not move that centre, so
     * this is the same centring as iOS `path(for:in:)`.
     */
    fun inkShift(mark: WorkSymbolMark): Offset {
        val pieces = markPieces(mark)
        if (pieces.isEmpty()) return Offset.Zero
        val bounds = pieces.map { it.centerline() }.reduce { a, b -> a.union(b) }
        return Offset(12f - bounds.midX, 12f - bounds.midY)
    }
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

private const val SignStroke = 2.2f
private const val Diagonal = 0.70710677f

private sealed interface MarkPiece {
    data class Poly(
        val points: List<Pair<Float, Float>>,
        val width: Float,
        val miter: Boolean = false
    ) : MarkPiece

    data class Ring(val x: Float, val y: Float, val radius: Float, val width: Float) : MarkPiece
    data class Disc(val x: Float, val y: Float, val radius: Float) : MarkPiece
    data object Shield : MarkPiece
    data class HalfRing(val radius: Float, val stroke: Float) : MarkPiece
}

private data class InkBounds(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val midX: Float get() = (left + right) / 2f
    val midY: Float get() = (top + bottom) / 2f

    fun union(other: InkBounds) = InkBounds(
        minOf(left, other.left),
        minOf(top, other.top),
        maxOf(right, other.right),
        maxOf(bottom, other.bottom)
    )
}

private fun MarkPiece.centerline(): InkBounds = when (this) {
    is MarkPiece.Poly -> InkBounds(
        points.minOf { it.first },
        points.minOf { it.second },
        points.maxOf { it.first },
        points.maxOf { it.second }
    )
    is MarkPiece.Ring -> InkBounds(x - radius, y - radius, x + radius, y + radius)
    is MarkPiece.Disc -> InkBounds(x - radius, y - radius, x + radius, y + radius)
    // Convex hull of the shield's points. The two cubics stay inside it.
    MarkPiece.Shield -> InkBounds(4.4f, 2.6f, 19.6f, 21.4f)
    is MarkPiece.HalfRing -> InkBounds(12f - radius, 12f - radius, 12f + radius, 12f + radius)
}

private fun markPieces(mark: WorkSymbolMark): List<MarkPiece> = when (mark) {
    is WorkSymbolMark.Shield -> listOf(MarkPiece.Shield)
    WorkSymbolMark.Check -> listOf(
        MarkPiece.Poly(listOf(5f to 12.5f, 9.6f to 17.1f, 19.2f to 7.4f), 3.4f)
    )
    WorkSymbolMark.HalfRing -> listOf(MarkPiece.HalfRing(8.2f, 2.6f))
    WorkSymbolMark.Gen -> listOf(
        MarkPiece.Ring(12f, 12f, 8f, 2.4f),
        MarkPiece.Disc(12f, 12f, 2.6f)
    )
    WorkSymbolMark.Dash -> listOf(MarkPiece.Poly(listOf(6.53f to 12f, 17.47f to 12f), 3.88f))
    WorkSymbolMark.FemaleFemale -> listOf(
        MarkPiece.Ring(8f, 8.4f, 4.8f, SignStroke),
        MarkPiece.Poly(listOf(8f to 13.2f, 8f to 18.8f), SignStroke),
        MarkPiece.Ring(16f, 8.4f, 4.8f, SignStroke),
        MarkPiece.Poly(listOf(16f to 13.2f, 16f to 18.8f), SignStroke),
        MarkPiece.Poly(listOf(5.4f to 16f, 18.6f to 16f), SignStroke)
    )
    WorkSymbolMark.FemaleMale -> listOf(
        MarkPiece.Ring(9.2f, 13.4f, 4.4f, SignStroke),
        MarkPiece.Poly(listOf(9.2f to 17.8f, 9.2f to 22f), SignStroke),
        MarkPiece.Poly(listOf(6.6f to 20f, 11.8f to 20f), SignStroke)
    ) + malePieces(13.9f, 8.7f, 4.4f, 3.8f, 3.4f)
    WorkSymbolMark.MaleMale -> malePieces(7.6f, 11.2f, 4.8f, 4.6f, 3.6f) +
        malePieces(13f, 16.6f, 4.8f, 4.6f, 3.6f)
    WorkSymbolMark.Other -> listOf(
        MarkPiece.Poly(listOf(3.6f to 3.6f, 5.8f to 3.6f, 5.8f to 14.4f, 3.6f to 14.4f), SignStroke),
        MarkPiece.Poly(listOf(20.4f to 3.6f, 18.2f to 3.6f, 18.2f to 14.4f, 20.4f to 14.4f), SignStroke),
        MarkPiece.Poly(listOf(5.8f to 9f, 18.2f to 9f), SignStroke),
        MarkPiece.Poly(listOf(12f to 3.6f, 12f to 16f), SignStroke),
        MarkPiece.Ring(12f, 18.9f, 2.9f, SignStroke)
    )
    WorkSymbolMark.Multi, WorkSymbolMark.Exclamation, WorkSymbolMark.Question -> emptyList()
}

/** ♂ with its arrow at 45° up-right. The head is mitred so it ends in a point. */
private fun malePieces(
    centerX: Float,
    centerY: Float,
    radius: Float,
    arrow: Float,
    head: Float
): List<MarkPiece> {
    val tipX = centerX + (radius + arrow) * Diagonal
    val tipY = centerY - (radius + arrow) * Diagonal
    return listOf(
        MarkPiece.Ring(centerX, centerY, radius, SignStroke),
        MarkPiece.Poly(
            listOf((centerX + radius * Diagonal) to (centerY - radius * Diagonal), tipX to tipY),
            SignStroke
        ),
        MarkPiece.Poly(
            listOf((tipX - head) to tipY, tipX to tipY, tipX to (tipY + head)),
            SignStroke,
            miter = true
        )
    )
}

private fun DrawScope.drawWorkSymbol(mark: WorkSymbolMark, color: Color) {
    val pieces = markPieces(mark)
    if (pieces.isEmpty()) return
    val scale = size.minDimension / 24f
    val shift = WorkSymbolGeometry.inkShift(mark)
    fun point(x: Float, y: Float) = Offset((x + shift.x) * scale, (y + shift.y) * scale)
    fun stroke(width: Float, join: StrokeJoin = StrokeJoin.Round) = Stroke(
        width = width * scale,
        cap = StrokeCap.Round,
        join = join
    )
    pieces.forEach { piece ->
        when (piece) {
            is MarkPiece.Poly -> {
                val path = Path().apply {
                    val first = piece.points.first()
                    moveTo(point(first.first, first.second).x, point(first.first, first.second).y)
                    piece.points.drop(1).forEach { (x, y) -> lineTo(point(x, y).x, point(x, y).y) }
                }
                drawPath(
                    path,
                    color,
                    style = stroke(piece.width, if (piece.miter) StrokeJoin.Miter else StrokeJoin.Round)
                )
            }
            is MarkPiece.Ring -> drawCircle(
                color,
                piece.radius * scale,
                point(piece.x, piece.y),
                style = stroke(piece.width)
            )
            is MarkPiece.Disc -> drawCircle(color, piece.radius * scale, point(piece.x, piece.y))
            MarkPiece.Shield -> {
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
            is MarkPiece.HalfRing -> {
                // Clip in the same shifted space as the ring, on the source x = 12 line.
                clipRect(right = point(12f, 12f).x) {
                    drawCircle(color, piece.radius * scale, point(12f, 12f))
                }
                drawCircle(color, piece.radius * scale, point(12f, 12f), style = stroke(piece.stroke))
            }
        }
    }
}
