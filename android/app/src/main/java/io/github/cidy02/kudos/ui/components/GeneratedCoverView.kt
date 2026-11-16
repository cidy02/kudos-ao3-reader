package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.io.File
import java.util.Locale
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

val LocalGeneratedCoverArtLoader = staticCompositionLocalOf<GeneratedCoverArtLoader<ImageBitmap>?> { null }
val LocalWorkEpubFileResolver = staticCompositionLocalOf<(String) -> File?> { { null } }

private class PreparedArt(
    val groundRects: List<GroundPiece>,
    val motif: Path,
    val ring: Path?,
    val centre: Offset,
    val motifStyle: Stroke,
    val ringStyle: Stroke,
    val motifInk: Color,
    val ringInk: Color,
    val filled: Boolean
)

private sealed class GroundPiece {
    class Gradient(val startColor: Color, val endColor: Color, val height: Float) : GroundPiece()
    class SolidRect(val left: Float, val top: Float, val width: Float, val height: Float, val color: Color) : GroundPiece()
    class SolidPath(val path: Path, val color: Color) : GroundPiece()
}

private object PreparedArtCache {
    private const val MAX_ENTRIES = 256
    private val map = object : LinkedHashMap<String, PreparedArt>(256, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, PreparedArt>?): Boolean =
            size > MAX_ENTRIES
    }

    @Synchronized
    fun getOrPut(key: String, create: () -> PreparedArt): PreparedArt =
        map.getOrPut(key, create)
}

/**
 * A cover in its own 112-unit coordinate system. Wordless instances are decorative.
 * Port of iOS `GeneratedCoverView.swift`.
 */
@Composable
fun GeneratedCoverView(
    recipe: GeneratedCoverRecipe,
    width: Dp,
    modifier: Modifier = Modifier,
    epubFile: File? = null,
    epubWorkId: String? = null,
    height: Dp? = null,
    showsWords: Boolean = true,
    showsArt: Boolean = true,
    cornerRadius: Dp = width * 0.125f
) {
    val coverHeight = height ?: (width * 1.42f)
    val context = LocalContext.current
    val providedLoader = LocalGeneratedCoverArtLoader.current
    val cacheKey = remember(recipe, width, coverHeight) {
        artCacheKey(recipe, width.value.toDouble(), coverHeight.value.toDouble())
    }

    var loadedFile by remember { mutableStateOf<File?>(null) }
    var embeddedImage by remember { mutableStateOf<ImageBitmap?>(null) }

    LaunchedEffect(showsArt, epubFile, epubWorkId) {
        if (!showsArt || epubFile == null || epubWorkId == null) {
            loadedFile = null
            embeddedImage = null
            return@LaunchedEffect
        }
        val loader = providedLoader ?: GeneratedCoverArtLoader.forCacheDir(context.cacheDir)
        val decoded = loader.image(workId = epubWorkId, file = epubFile)
        embeddedImage = decoded
        loadedFile = epubFile
    }

    val a11yLabel = remember(recipe) {
        listOf(recipe.title, recipe.subtitle, recipe.author, recipe.fandom)
            .filter { it.isNotEmpty() }
            .joinToString(", ")
    }
    val semanticsModifier = if (showsWords) {
        Modifier.clearAndSetSemantics { contentDescription = a11yLabel }
    } else {
        Modifier.clearAndSetSemantics {}
    }

    Box(
        modifier = modifier
            .size(width = width, height = coverHeight)
            .clip(RoundedCornerShape(cornerRadius))
            .then(semanticsModifier)
    ) {
        val currentEmbedded = embeddedImage
        if (showsArt && loadedFile == epubFile && currentEmbedded != null) {
            Image(
                bitmap = currentEmbedded,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            val art = remember(cacheKey) {
                PreparedArtCache.getOrPut(cacheKey) {
                    prepareArt(recipe, width.value.toDouble(), coverHeight.value.toDouble())
                }
            }
            Canvas(modifier = Modifier.fillMaxSize()) {
                val unit = size.width / 112f
                if (unit <= 0f) return@Canvas
                scale(scaleX = unit, scaleY = unit, pivot = Offset.Zero) {
                    for (piece in art.groundRects) {
                        when (piece) {
                            is GroundPiece.Gradient -> drawRect(
                                brush = Brush.linearGradient(
                                    colors = listOf(piece.startColor, piece.endColor),
                                    start = Offset(19f, 0f),
                                    end = Offset(93f, piece.height)
                                ),
                                topLeft = Offset.Zero,
                                size = Size(112f, piece.height)
                            )
                            is GroundPiece.SolidRect -> drawRect(
                                color = piece.color,
                                topLeft = Offset(piece.left, piece.top),
                                size = Size(piece.width, piece.height)
                            )
                            is GroundPiece.SolidPath -> drawPath(
                                path = piece.path,
                                color = piece.color
                            )
                        }
                    }
                    if (showsArt) {
                        withTransform({
                            translate(left = art.centre.x, top = art.centre.y)
                            rotate(degrees = recipe.rotation.toFloat(), pivot = Offset.Zero)
                            scale(
                                scaleX = recipe.scale.toFloat(),
                                scaleY = recipe.scale.toFloat(),
                                pivot = Offset.Zero
                            )
                            translate(left = -art.centre.x, top = -art.centre.y)
                        }) {
                            if (art.filled) {
                                drawPath(art.motif, color = art.motifInk)
                            } else {
                                drawPath(art.motif, color = art.motifInk, style = art.motifStyle)
                            }
                        }
                        art.ring?.let { ring ->
                            drawPath(ring, color = art.ringInk, style = art.ringStyle)
                        }
                    }
                }
            }
            if (showsWords) {
                CoverWords(recipe = recipe, width = width)
            }
        }
    }
}

internal fun artCacheKey(recipe: GeneratedCoverRecipe, width: Double, height: Double): String =
    "$recipe|$width|$height"

@Composable
private fun CoverWords(recipe: GeneratedCoverRecipe, width: Dp) {
    val density = LocalDensity.current
    fun nonScalingSp(dpValue: Float): TextUnit = with(density) { dpValue.dp.toSp() }

    val widthVal = width.value
    val titleCount = GeneratedCoverRecipe.graphemeCount(recipe.title)
    val base = when {
        titleCount <= 12 && !recipe.title.contains(" ") -> 22f
        titleCount <= 32 -> 15f
        titleCount <= 64 -> 13f
        else -> 12f
    }
    val titleSizeDp = widthVal / 112f * if (recipe.titleStyle == 2) base * 0.8f else base
    val titleFontSize = nonScalingSp(titleSizeDp)
    val titleTracking = if (recipe.titleStyle == 2) nonScalingSp(widthVal / 112f * 0.6f) else TextUnit.Unspecified
    val alignment = if (recipe.placement == 2) Alignment.End else Alignment.Start
    val textAlign = if (recipe.placement == 2) TextAlign.End else TextAlign.Start

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(width * 0.1f),
        horizontalAlignment = alignment,
        verticalArrangement = Arrangement.spacedBy(width * 0.035f)
    ) {
        if (recipe.placement != 1) {
            FandomLabel(recipe = recipe, width = width, nonScalingSp = ::nonScalingSp)
        }
        if (recipe.placement == 0) {
            Spacer(Modifier.weight(1f))
        }
        if (recipe.placement == 2) {
            Spacer(Modifier.height(width * 0.08f))
        }
        Text(
            text = if (recipe.titleStyle == 2) recipe.title.uppercase(Locale.ROOT) else recipe.title,
            color = Color.White,
            style = TextStyle(
                fontSize = titleFontSize,
                lineHeight = titleFontSize * 1.15f,
                fontWeight = if (recipe.titleStyle == 2) FontWeight.Bold else FontWeight.SemiBold,
                fontFamily = if (recipe.titleStyle == 2) FontFamily.SansSerif else FontFamily.Serif,
                fontStyle = if (recipe.titleStyle == 1) FontStyle.Italic else FontStyle.Normal,
                letterSpacing = titleTracking,
                textAlign = textAlign,
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            ),
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth()
        )
        if (recipe.subtitle.isNotEmpty()) {
            val subtitleSize = nonScalingSp(widthVal * 0.09f)
            Text(
                text = recipe.subtitle,
                color = Color.White.copy(alpha = GeneratedCoverMath.BYLINE_OPACITY.toFloat()),
                style = TextStyle(
                    fontSize = subtitleSize,
                    lineHeight = subtitleSize * 1.15f,
                    fontFamily = FontFamily.Serif,
                    fontStyle = FontStyle.Italic,
                    textAlign = textAlign,
                    platformStyle = PlatformTextStyle(includeFontPadding = false)
                ),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth()
            )
        }
        val authorSize = nonScalingSp(widthVal * 0.09f)
        Text(
            text = recipe.author,
            color = Color.White.copy(alpha = GeneratedCoverMath.BYLINE_OPACITY.toFloat()),
            style = TextStyle(
                fontSize = authorSize,
                lineHeight = authorSize * 1.15f,
                fontFamily = FontFamily.SansSerif,
                fontStyle = FontStyle.Italic,
                textAlign = textAlign,
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth()
        )
        if (recipe.placement == 1) {
            Spacer(Modifier.weight(1f))
            FandomLabel(recipe = recipe, width = width, nonScalingSp = ::nonScalingSp)
        }
        if (recipe.placement == 2) {
            Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun FandomLabel(
    recipe: GeneratedCoverRecipe,
    width: Dp,
    nonScalingSp: (Float) -> TextUnit
) {
    val widthVal = width.value
    val fontSize = nonScalingSp(widthVal * 0.076f)
    val tracking = nonScalingSp(widthVal / 112f * 0.6f)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = recipe.fandom.uppercase(Locale.ROOT),
            color = Color.White.copy(alpha = GeneratedCoverMath.FANDOM_OPACITY.toFloat()),
            style = TextStyle(
                fontSize = fontSize,
                lineHeight = fontSize * 1.15f,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = tracking,
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        if (recipe.part > 0) {
            Spacer(Modifier.width(2.dp))
            val numeral = if (recipe.part <= 5) {
                listOf("", "I", "II", "III", "IV", "V")[recipe.part]
            } else {
                recipe.part.toString()
            }
            Text(
                text = "PART $numeral",
                color = Color.White,
                style = TextStyle(
                    fontSize = fontSize,
                    lineHeight = fontSize * 1.15f,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = tracking,
                    platformStyle = PlatformTextStyle(includeFontPadding = false)
                ),
                maxLines = 1,
                softWrap = false
            )
        }
    }
}

private fun oklchColor(lightness: Double, chroma: Double, hue: Double): Color {
    val rgb = GeneratedCoverMath.oklchToRgb(lightness, chroma, hue)
    return Color(red = rgb.r.toFloat(), green = rgb.g.toFloat(), blue = rgb.b.toFloat(), alpha = 1f)
}

private fun prepareArt(
    recipe: GeneratedCoverRecipe,
    width: Double,
    height: Double
): PreparedArt {
    val h = (height * 112.0 / max(width, 1.0)).toFloat()
    val l = recipe.lightness
    val hue = recipe.hues[0].toDouble()
    val chroma = recipe.groundChroma
    val main = oklchColor(l, chroma, hue)
    val light = oklchColor(GeneratedCoverMath.lighterGroundLightness(l), chroma + 0.005, hue + 14.0)
    val dark = oklchColor(l - 0.05, 0.08, hue - 10.0)

    val ground: List<GroundPiece> = when (recipe.ground) {
        GeneratedCoverRecipe.Ground.GRADIENT -> listOf(GroundPiece.Gradient(main, light, h))
        GeneratedCoverRecipe.Ground.SPLIT -> listOf(
            GroundPiece.SolidRect(0f, 0f, 112f, h, main),
            GroundPiece.SolidRect(0f, h * 0.58f, 112f, h * 0.42f, light)
        )
        GeneratedCoverRecipe.Ground.BAND -> listOf(
            GroundPiece.SolidRect(0f, 0f, 112f, h, main),
            GroundPiece.SolidRect(0f, h * 0.62f, 112f, h * 0.12f, dark)
        )
        GeneratedCoverRecipe.Ground.SOLID -> listOf(GroundPiece.SolidRect(0f, 0f, 112f, h, main))
        GeneratedCoverRecipe.Ground.CROSSOVER -> {
            val count = recipe.hues.size
            val extent = 112.0 + h.toDouble()
            fun pt(cut: Double, offset: Double): Offset = Offset((cut + offset).toFloat(), (-offset).toFloat())
            (0 until count).map { index ->
                val first = if (count == 2) (if (index == 0) 0.0 else 0.6) else index.toDouble() / count
                val last = if (count == 2) (if (index == 0) 0.6 else 1.0) else (index + 1).toDouble() / count
                val start = GeneratedCoverMath.crossoverCut(first, h.toDouble())
                val end = GeneratedCoverMath.crossoverCut(last, h.toDouble())
                val band = Path().apply {
                    val p0 = pt(start, extent)
                    val p1 = pt(start, -extent)
                    val p2 = pt(end, -extent)
                    val p3 = pt(end, extent)
                    moveTo(p0.x, p0.y)
                    lineTo(p1.x, p1.y)
                    lineTo(p2.x, p2.y)
                    lineTo(p3.x, p3.y)
                    close()
                }
                GroundPiece.SolidPath(band, oklchColor(l, chroma, recipe.hues[index].toDouble()))
            }
        }
    }

    val centre = Offset(
        x = if (recipe.placement == 2) 32f else 80f,
        y = h * when (recipe.placement) {
            0 -> 0.314f
            1 -> 0.742f
            else -> 0.73f
        }
    )
    val sparse = width < 64.0
    val density = doubleArrayOf(0.7, 0.95, 1.2, 1.5)[if (sparse) 0 else recipe.tier]
    val random = GeneratedCoverRecipe.Random(seed = recipe.shapeSeed)
    val motifPath = buildMotifPath(recipe.motif, centre, radius = 46.0, density = density, rng = random)

    val ring: Path? = if (recipe.hasRing) {
        val radius = (46.0 * 1.16 * recipe.scale).toFloat()
        val rect = Rect(centre.x - radius, centre.y - radius, centre.x + radius, centre.y + radius)
        Path().apply {
            if (recipe.closedRing) {
                addOval(rect)
            } else {
                val middle = atan2((h / 2f - centre.y).toDouble(), (56f - centre.x).toDouble())
                val startDeg = ((middle + 0.6) * 180.0 / PI).toFloat()
                val sweepDeg = ((2.0 * PI - 1.2) * 180.0 / PI).toFloat()
                arcTo(rect, startAngleDegrees = startDeg, sweepAngleDegrees = sweepDeg, forceMoveTo = true)
            }
        }
    } else {
        null
    }

    val filled = recipe.motif == "petals" || recipe.motif == "halftone"
    val floor = GeneratedCoverMath.strokeFloor(width)
    val motifLineWidth = (max(recipe.lineWidth, if (sparse) floor else 0.0) / recipe.scale).toFloat()
    val ringLineWidth = max(1.2, if (sparse) floor else 0.0).toFloat()
    return PreparedArt(
        groundRects = ground,
        motif = motifPath,
        ring = ring,
        centre = centre,
        motifStyle = Stroke(width = motifLineWidth, cap = StrokeCap.Round, join = StrokeJoin.Round),
        ringStyle = Stroke(width = ringLineWidth, cap = StrokeCap.Round),
        motifInk = Color.White.copy(alpha = (recipe.opacity * if (filled) 0.8 else 1.0).toFloat()),
        ringInk = Color.White.copy(alpha = recipe.opacity.toFloat()),
        filled = filled
    )
}

private fun buildMotifPath(
    kind: String,
    centre: Offset,
    radius: Double,
    density: Double,
    rng: GeneratedCoverRecipe.Random
): Path {
    val cx = centre.x.toDouble()
    val cy = centre.y.toDouble()
    val r = radius
    val path = Path()

    fun ellipse(x: Double, y: Double, rx: Double, ry: Double) {
        path.addOval(Rect((x - rx).toFloat(), (y - ry).toFloat(), (x + rx).toFloat(), (y + ry).toFloat()))
    }

    fun count(low: Int, high: Int, minimum: Int = 3): Int =
        max(minimum, GeneratedCoverRecipe.roundAwayFromZero(rng.integer(low, high).toDouble() * density).toInt())

    when (kind) {
        "sprig" -> {
            val bx = cx - r * 0.12
            val by = cy + r * 0.95
            val ex = cx + r * 0.10
            val ey = cy - r * 0.85
            val c1x = cx - r * 0.28
            val c1y = cy + r * 0.25
            val c2x = cx + r * 0.24
            val c2y = cy - r * 0.25
            path.moveTo(bx.toFloat(), by.toFloat())
            path.cubicTo(c1x.toFloat(), c1y.toFloat(), c2x.toFloat(), c2y.toFloat(), ex.toFloat(), ey.toFloat())
            val n = max(3, GeneratedCoverRecipe.roundAwayFromZero(rng.integer(5, 7).toDouble() * density * 0.8).toInt())
            for (i in 0 until n) {
                val t = (i + 1).toDouble() / (n + 1).toDouble()
                val u = 1.0 - t
                val x = u.pow(3) * bx + 3.0 * u * u * t * c1x + 3.0 * u * t * t * c2x + t.pow(3) * ex
                val y = u.pow(3) * by + 3.0 * u * u * t * c1y + 3.0 * u * t * t * c2y + t.pow(3) * ey
                val side = if (i % 2 == 0) 1.0 else -1.0
                val len = r * rng.between(0.32, 0.48)
                path.moveTo(x.toFloat(), y.toFloat())
                path.quadraticTo(
                    (x + side * len * 0.25).toFloat(), (y - len * 0.75).toFloat(),
                    (x + side * len).toFloat(), (y - len * 0.55).toFloat()
                )
                path.quadraticTo(
                    (x + side * len * 0.75).toFloat(), (y - len * 0.1).toFloat(),
                    x.toFloat(), y.toFloat()
                )
            }
        }
        "orbit" -> {
            val n = max(3, GeneratedCoverRecipe.roundAwayFromZero(rng.integer(6, 8).toDouble() * density * 0.8).toInt()) * 2
            for (i in 0 until n / 2) {
                val a = i.toDouble() * 2.0 * PI / n.toDouble()
                path.moveTo((cx + cos(a) * r).toFloat(), (cy + sin(a) * r).toFloat())
                path.lineTo((cx - cos(a) * r).toFloat(), (cy - sin(a) * r).toFloat())
            }
            ellipse(cx, cy, r * 0.62, r * 0.62)
        }
        "rings" -> {
            val base = rng.between(0.0, 2.0 * PI)
            val n = max(2, GeneratedCoverRecipe.roundAwayFromZero(5.0 * density * 0.8).toInt())
            for (i in 0 until n) {
                val rr = r * (i + 1).toDouble() / n.toDouble()
                val shift = (r - rr) * 0.45
                ellipse(
                    cx + cos(base + i.toDouble() * 0.35) * shift,
                    cy + sin(base + i.toDouble() * 0.35) * shift,
                    rr,
                    rr
                )
            }
        }
        "moire" -> {
            val offset = r * rng.between(0.18, 0.32)
            val angle = rng.next() * 2.0 * PI
            val n = max(2, GeneratedCoverRecipe.roundAwayFromZero(3.5 * density).toInt())
            for (group in 0 until 2) {
                for (i in 1..n) {
                    val rr = r * i.toDouble() / n.toDouble() * 1.1
                    ellipse(
                        cx + group.toDouble() * cos(angle) * offset,
                        cy + group.toDouble() * sin(angle) * offset,
                        rr,
                        rr
                    )
                }
            }
        }
        "sigil" -> {
            for (i in 0..8) {
                val angle = ((i * 3) % 8).toDouble() * PI / 4.0 - PI / 2.0
                val px = (cx + cos(angle) * r * 0.78).toFloat()
                val py = (cy + sin(angle) * r * 0.78).toFloat()
                if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
            ellipse(cx, cy, r * 0.22, r * 0.22)
        }
        "contours" -> {
            val phase = rng.between(0.0, 2.0 * PI)
            val levels = max(2, GeneratedCoverRecipe.roundAwayFromZero(5.0 * density * 0.8).toInt())
            for (level in 1..levels) {
                val base = r * 0.85 * level.toDouble() / levels.toDouble()
                for (step in 0..48) {
                    val a = step.toDouble() / 48.0 * 2.0 * PI
                    val rr = base * (1.0 + 0.14 * sin(3.0 * a + phase) + 0.08 * cos(5.0 * a - phase))
                    val px = (cx + cos(a) * rr).toFloat()
                    val py = (cy + sin(a) * rr * 0.78).toFloat()
                    if (step == 0) path.moveTo(px, py) else path.lineTo(px, py)
                }
            }
        }
        "guilloche" -> {
            val fa = rng.integer(3, 5)
            val phase = rng.between(0.2, 1.4)
            for (step in 0..180) {
                val t = step.toDouble() / 180.0 * 2.0 * PI
                val px = (cx + sin(fa.toDouble() * t + phase) * r * 0.65).toFloat()
                val py = (cy + sin((fa + 1).toDouble() * t) * r * 0.65).toFloat()
                if (step == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
        }
        "waves" -> {
            val n = count(3, 5)
            val amp = r * rng.between(0.08, 0.16)
            val freq = rng.between(1.5, 3.0)
            for (i in 0 until n) {
                val y = cy - r + i.toDouble() * 2.0 * r / (n - 1).toDouble()
                for (step in 0..40) {
                    val t = step.toDouble() / 40.0
                    val px = (cx - r * 1.3 + t * 2.6 * r).toFloat()
                    val py = (y + sin(t * 2.0 * PI * freq + i.toDouble() * 0.6) * amp).toFloat()
                    if (step == 0) path.moveTo(px, py) else path.lineTo(px, py)
                }
            }
        }
        "halftone" -> {
            val step = r * rng.between(0.2, 0.28) / density
            val limit = r * 1.25
            var y = -limit
            while (y <= limit) {
                var x = -limit
                while (x <= limit) {
                    val size = step * 0.45 * (1.0 - hypot(x, y) / limit)
                    if (size > 0.6) ellipse(cx + x, cy + y, size, size)
                    x += step
                }
                y += step
            }
        }
        "truchet" -> {
            val n = max(2, GeneratedCoverRecipe.roundAwayFromZero(4.0 * density).toInt())
            val side = r * 2.5 / n.toDouble()
            val half = side / 2.0
            for (y in 0 until n) {
                for (x in 0 until n) {
                    val px = cx - r * 1.25 + x.toDouble() * side
                    val py = cy - r * 1.25 + y.toDouble() * side
                    val flip = rng.next() < 0.5
                    path.moveTo((px + half).toFloat(), py.toFloat())
                    val c1x = if (flip) px else px + side
                    val c1y = py
                    path.arcTo(
                        Rect((c1x - half).toFloat(), (c1y - half).toFloat(), (c1x + half).toFloat(), (c1y + half).toFloat()),
                        startAngleDegrees = if (flip) 0f else 180f,
                        sweepAngleDegrees = if (flip) 90f else -90f,
                        forceMoveTo = false
                    )
                    path.moveTo((if (flip) px + side else px).toFloat(), (py + half).toFloat())
                    val c2x = if (flip) px + side else px
                    val c2y = py + side
                    path.arcTo(
                        Rect((c2x - half).toFloat(), (c2y - half).toFloat(), (c2x + half).toFloat(), (c2y + half).toFloat()),
                        startAngleDegrees = -90f,
                        sweepAngleDegrees = if (flip) -90f else 90f,
                        forceMoveTo = false
                    )
                }
            }
        }
        "rosette" -> {
            val petals = rng.integer(3, 7)
            val outer = r * 0.8
            val inner = outer / petals.toDouble()
            val distance = inner * rng.between(0.8, 1.6)
            for (step in 0..360) {
                val t = step.toDouble() / 360.0 * 2.0 * PI
                val px = (cx + (outer - inner) * cos(t) + distance * cos((petals - 1).toDouble() * t)).toFloat()
                val py = (cy + (outer - inner) * sin(t) - distance * sin((petals - 1).toDouble() * t)).toFloat()
                if (step == 0) path.moveTo(px, py) else path.lineTo(px, py)
            }
        }
        "sunburst" -> {
            val n = count(7, 10, minimum = 5)
            for (i in 0 until n) {
                val a = i.toDouble() / n.toDouble() * 2.0 * PI
                path.moveTo((cx + cos(a) * r * 0.25).toFloat(), (cy + sin(a) * r * 0.25).toFloat())
                path.lineTo((cx + cos(a) * r * 1.4).toFloat(), (cy + sin(a) * r * 1.4).toFloat())
            }
        }
        "constellation" -> {
            val n = count(5, 7, minimum = 4)
            val stars = (0 until n).map {
                val a = rng.next() * 2.0 * PI
                val rad = r * (0.25 + rng.next() * 0.9)
                Triple(a, cx + cos(a) * rad, cy + sin(a) * rad)
            }.sortedBy { it.first }
            stars.forEachIndexed { index, star ->
                if (index == 0) path.moveTo(star.second.toFloat(), star.third.toFloat())
                else path.lineTo(star.second.toFloat(), star.third.toFloat())
            }
            for (star in stars) {
                ellipse(star.second, star.third, 1.8, 1.8)
            }
        }
        "chevrons" -> {
            val n = count(3, 5)
            for (i in 0 until n) {
                val y = cy - r * 0.9 + i.toDouble() * r * 0.32
                path.moveTo((cx - r).toFloat(), (y + r * 0.3).toFloat())
                path.lineTo(cx.toFloat(), (y - r * 0.05).toFloat())
                path.lineTo((cx + r).toFloat(), (y + r * 0.3).toFloat())
            }
        }
        "squares" -> {
            val step = rng.between(6.0, 12.0) * PI / 180.0
            val n = max(2, GeneratedCoverRecipe.roundAwayFromZero(4.0 * density).toInt())
            for (i in 0 until n) {
                val side = r * (1.1 - i.toDouble() * 0.15)
                val angle = i.toDouble() * step
                for (corner in 0 until 4) {
                    val a = angle + PI / 4.0 + corner.toDouble() * PI / 2.0
                    val px = (cx + cos(a) * side).toFloat()
                    val py = (cy + sin(a) * side).toFloat()
                    if (corner == 0) path.moveTo(px, py) else path.lineTo(px, py)
                }
                path.close()
            }
        }
        "petals" -> {
            val n = count(4, 6)
            for (i in 0 until n) {
                val a = i.toDouble() / n.toDouble() * 2.0 * PI
                path.moveTo(centre.x, centre.y)
                path.quadraticTo(
                    (cx + cos(a - 0.32) * r * 0.72).toFloat(), (cy + sin(a - 0.32) * r * 0.72).toFloat(),
                    (cx + cos(a) * r).toFloat(), (cy + sin(a) * r).toFloat()
                )
                path.quadraticTo(
                    (cx + cos(a + 0.32) * r * 0.72).toFloat(), (cy + sin(a + 0.32) * r * 0.72).toFloat(),
                    centre.x, centre.y
                )
            }
        }
    }
    return path
}
