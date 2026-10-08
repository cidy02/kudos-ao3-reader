package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.roundToInt

/** The five colours artboard 1j offers, stored as hues so every theme paints them the same way. */
object SubjectHueSwatches {
    data class Swatch(val name: String, val hue: Double)

    val all: List<Swatch> = listOf(
        Swatch("Violet", 0.7194),
        Swatch("Mint", 0.4424),
        Swatch("Rose", 0.0),
        Swatch("Amber", 0.0663),
        Swatch("Blue", 0.5395)
    )

    fun matches(swatch: Swatch, hue: Double?): Boolean {
        hue ?: return false
        return kotlin.math.abs(hue - swatch.hue) < 0.01
    }

    fun isPreset(hue: Double?): Boolean = all.any { matches(it, hue) }
}

/** Uppercase group label used by queue and collection forms. */
@Composable
fun SubjectFieldLabel(
    text: String,
    modifier: Modifier = Modifier,
    lineHeight: TextUnit = TextUnit.Unspecified
) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 11.sp,
        lineHeight = lineHeight,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.8.sp
    )
}

/**
 * A labelled form row. [trailing] replaces the value, as a switch or a swatch does.
 * [valueMaxLines] above one lets a value the reader has to see whole wrap instead of being cut.
 */
@Composable
fun SubjectFormRow(
    label: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    showsDisclosure: Boolean = false,
    onClick: (() -> Unit)? = null,
    valueMaxLines: Int = 1,
    trailing: (@Composable () -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val stackValue = isAccessibilityFontScale() && value != null
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 13.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (stackValue) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(text = label, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                Text(
                    text = value.orEmpty(),
                    color = tokens.secondaryInk,
                    fontSize = 14.5.sp,
                    lineHeight = 20.sp,
                    maxLines = valueMaxLines,
                    overflow = TextOverflow.Ellipsis
                )
            }
        } else {
            // Beside a value the label keeps its own width and the value takes what is left.
            // The other way round, a long value took the row and left the label one letter
            // wide, a letter to a line.
            val hasValue = trailing == null && value != null
            Text(
                text = label,
                modifier = if (hasValue) Modifier else Modifier.weight(1f),
                color = tokens.primaryInk,
                fontSize = 14.5.sp,
                lineHeight = 20.sp
            )
            if (trailing != null) {
                trailing()
            } else if (value != null) {
                Text(
                    text = value,
                    modifier = Modifier.weight(1f),
                    color = tokens.secondaryInk,
                    fontSize = 14.5.sp,
                    lineHeight = 20.sp,
                    textAlign = TextAlign.End,
                    maxLines = valueMaxLines,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        if (showsDisclosure) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = tokens.tertiaryInk,
                modifier = Modifier.size(with(LocalDensity.current) { 18.sp.toDp() })
            )
        }
    }
}

/**
 * Five preset hues plus a dashed "+" that opens [HsvColorDialog].
 * A preset clears [colorHex]. The "+" stores the picked colour exactly.
 */
@Composable
fun SubjectHueSwatchRow(
    hue: Double?,
    colorHex: String?,
    onChange: (hue: Double?, colorHex: String?) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    var picking by remember { mutableStateOf(false) }
    val custom = colorHex != null || (hue != null && !SubjectHueSwatches.isPreset(hue))
    Row(
        modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SubjectHueSwatches.all.forEach { swatch ->
            val selected = colorHex == null && SubjectHueSwatches.matches(swatch, hue)
            SwatchCircle(
                color = carouselTint(tokens.theme, swatch.hue),
                stroke = SubjectPalette.fromHue(swatch.hue, tokens.theme).accent,
                selected = selected,
                label = swatch.name,
                onClick = {
                    if (selected) onChange(null, null) else onChange(swatch.hue, null)
                }
            )
        }
        if (custom && hue != null) {
            val picked = colorHex?.let(::parseStoredColor)
            SwatchCircle(
                color = picked ?: carouselTint(tokens.theme, hue),
                stroke = SubjectPalette.fromHue(hue, tokens.theme).accent,
                selected = true,
                label = "Custom colour",
                onClick = { picking = true }
            )
        } else {
            Box(
                Modifier
                    .size(34.dp)
                    .clickable { picking = true }
                    .semantics { contentDescription = "Custom colour" },
                contentAlignment = Alignment.Center
            ) {
                val dash = tokens.secondaryInk
                Box(
                    Modifier
                        .size(28.dp)
                        .drawBehind {
                            drawCircle(
                                color = dash,
                                radius = size.minDimension / 2f - 0.5.dp.toPx(),
                                style = Stroke(
                                    width = 1.dp.toPx(),
                                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.5.dp.toPx()))
                                )
                            )
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, tint = dash, modifier = Modifier.size(12.dp))
                }
            }
        }
    }
    if (picking) {
        val initial = colorHex?.let(::parseStoredColor)
            ?: hsb(hue ?: SubjectHueSwatches.all.first().hue, 0.55, 0.78)
        HsvColorDialog(
            initial = initial,
            onDismiss = { picking = false },
            onConfirm = { color ->
                picking = false
                onChange(color.hueComponent(), color.toStoredHex())
            }
        )
    }
}

@Composable
fun HsvColorDialog(
    initial: Color,
    onDismiss: () -> Unit,
    onConfirm: (Color) -> Unit
) {
    val start = initial.hsv()
    var hue by remember { mutableFloatStateOf(start.first) }
    var saturation by remember { mutableFloatStateOf(start.second) }
    var value by remember { mutableFloatStateOf(start.third) }
    val preview = hsb(hue.toDouble(), saturation.toDouble(), value.toDouble())
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Colour") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SaturationValueSquare(
                    hue = hue,
                    saturation = saturation,
                    value = value,
                    onChange = { s, v ->
                        saturation = s
                        value = v
                    }
                )
                HueSlider(hue = hue, onChange = { hue = it })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(preview)
                            .border(0.5.dp, LocalKudosTokens.current.separator, CircleShape)
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(preview.toStoredHex(), color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp)
                }
            }
        },
        confirmButton = { TextButton(onClick = { onConfirm(preview) }) { Text("Done") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun SwatchCircle(
    color: Color,
    stroke: Color,
    selected: Boolean,
    label: String,
    onClick: () -> Unit
) {
    Box(
        Modifier
            .size(34.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(color)
                .border(if (selected) 2.5.dp else 0.5.dp, stroke, CircleShape)
        )
    }
}

@Composable
private fun SaturationValueSquare(
    hue: Float,
    saturation: Float,
    value: Float,
    onChange: (Float, Float) -> Unit
) {
    val hueColor = hsb(hue.toDouble(), 1.0, 1.0)
    Canvas(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1.35f)
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(8.dp))
            .pointerInput(Unit) {
                fun apply(position: Offset) {
                    val s = (position.x / size.width).coerceIn(0f, 1f)
                    val v = (1f - position.y / size.height).coerceIn(0f, 1f)
                    onChange(s, v)
                }
                detectTapGestures { apply(it) }
                detectDragGestures { change, _ -> apply(change.position) }
            }
    ) {
        drawRect(Brush.horizontalGradient(listOf(Color.White, hueColor)))
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
        val center = Offset(saturation * size.width, (1f - value) * size.height)
        drawCircle(Color.White, radius = 8.dp.toPx(), center = center, style = Stroke(width = 2.dp.toPx()))
    }
}

@Composable
private fun HueSlider(hue: Float, onChange: (Float) -> Unit) {
    val colors = List(7) { index -> hsb(index / 6.0, 1.0, 1.0) }
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(28.dp)
            .clip(CircleShape)
            .pointerInput(Unit) {
                fun apply(x: Float) { onChange((x / size.width).coerceIn(0f, 1f)) }
                detectTapGestures { apply(it.x) }
                detectDragGestures { change, _ -> apply(change.position.x) }
            }
    ) {
        drawRect(Brush.horizontalGradient(colors))
        drawCircle(Color.White, radius = 10.dp.toPx(), center = Offset(hue * size.width, size.height / 2f), style = Stroke(width = 2.dp.toPx()))
    }
}

private fun carouselTint(theme: ReaderTheme, hue: Double): Color {
    val (saturation, brightness) = when (theme) {
        ReaderTheme.Dark, ReaderTheme.Oled -> 0.38 to 0.78
        ReaderTheme.Light -> 0.42 to 0.75
        ReaderTheme.Sepia -> 0.34 to 0.70
    }
    return hsb(hue, saturation, brightness)
}

fun parseStoredColor(hex: String): Color? {
    val raw = hex.trim().removePrefix("#")
    if (raw.length != 6 && raw.length != 8) return null
    val value = raw.toLongOrNull(16) ?: return null
    val rgb = if (raw.length == 8) value and 0xFFFFFF else value
    return Color(
        red = ((rgb shr 16) and 0xFF) / 255f,
        green = ((rgb shr 8) and 0xFF) / 255f,
        blue = (rgb and 0xFF) / 255f
    )
}

fun Color.toStoredHex(): String {
    val redByte = (red * 255f).roundToInt().coerceIn(0, 255)
    val greenByte = (green * 255f).roundToInt().coerceIn(0, 255)
    val blueByte = (blue * 255f).roundToInt().coerceIn(0, 255)
    return "#%02X%02X%02X".format(redByte, greenByte, blueByte)
}

private fun Color.hsv(): Triple<Float, Float, Float> {
    val maxChannel = max(red, max(green, blue))
    val minChannel = minOf(red, green, blue)
    val saturation = if (maxChannel == 0f) 0f else (maxChannel - minChannel) / maxChannel
    return Triple(hueComponent().toFloat(), saturation, maxChannel)
}
