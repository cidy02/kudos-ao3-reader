package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.round
import kotlin.math.roundToInt

/** Spec numbers from `SubjectMetrics`. Layout sizes stay in dp; type uses sp. */
object SubjectMetrics {
    val gutter = 16.dp
    val headerGutter = 26.dp
    val panelGutter = 22.dp
    val accountGutter = 16.dp
    val kickerRuleWidth = 22.dp
    val pageRuleWidth = 26.dp
    val kickerRuleHeight = 2.5.dp
    val ringDiameter = 68.dp
    val ringStroke = 5.dp
    val rowRadius = 16.dp
    val heroRadius = 18.dp
    val chipRadius = 8.dp
    val trayRadius = 10.dp
    val defaultWashHeight = 380.dp
    val panelRadius = 14.dp
}

/** A count on a chip or section header: 999, 1K, 1.5K, 1.2M. */
fun Int.compactCount(): String {
    val negative = this < 0
    val magnitude = if (negative) -toLong() else toLong()
    val body = when {
        magnitude < 1_000L -> magnitude.toString()
        magnitude < 1_000_000L -> compactUnit(magnitude, 1_000.0, "K")
        magnitude < 1_000_000_000L -> compactUnit(magnitude, 1_000_000.0, "M")
        else -> compactUnit(magnitude, 1_000_000_000.0, "B")
    }
    return if (negative) "-$body" else body
}

private fun compactUnit(magnitude: Long, unit: Double, suffix: String): String {
    val rounded = round(magnitude / unit * 10.0) / 10.0
    val text = if (abs(rounded - rounded.toInt()) < 0.05) rounded.toInt().toString() else rounded.toString()
    return text + suffix
}

@Composable
private fun TextUnit.asDp(): Dp = with(LocalDensity.current) { toDp() }

/** iOS `DynamicTypeSize.isAccessibilitySize`: Android crosses it above 1.3x. */
@Composable
fun isAccessibilityFontScale(): Boolean = LocalDensity.current.fontScale > 1.3f

/**
 * Full-bleed subject wash, aligned to the top. The gradient is [washHeight] tall
 * (380dp on a plain list) and the rest of the screen is the page colour.
 * Compose has no squircle; corners elsewhere use [RoundedCornerShape].
 */
@Composable
fun Modifier.subjectScreenWash(
    palette: SubjectPalette,
    washHeight: Dp = SubjectMetrics.defaultWashHeight
): Modifier {
    val washes = LocalShellWashes.current
    val key = remember { Any() }
    SideEffect { washes.put(key, ShellWash(palette, washHeight)) }
    DisposableEffect(washes) { onDispose { washes.remove(key) } }
    return subjectWash(palette, washHeight)
}

/** The wash alone. The shell repaints a page's top with it, and that must not count as a page's wash. */
@Composable
fun Modifier.subjectWash(palette: SubjectPalette, washHeight: Dp): Modifier {
    val heightPx = with(LocalDensity.current) { washHeight.toPx() }
    val backdrop = palette.theme.cardBackdrop
    val brush = palette.wash(heightPx)
    return drawBehind {
        drawRect(backdrop)
        drawRect(brush = brush, size = Size(size.width, heightPx))
    }
}

/** A wash a screen has painted: what [subjectScreenWash] was given. */
data class ShellWash(val palette: SubjectPalette, val height: Dp)

/**
 * The washes on screen, oldest first, so a page's own comes before that of a sheet over it.
 * The shell reads [page] to paint its top bar in the page's wash when a list runs under it.
 */
class ShellWashes {
    private val entries = mutableStateListOf<Pair<Any, ShellWash>>()
    val page: ShellWash? get() = entries.firstOrNull()?.second

    fun put(key: Any, wash: ShellWash) {
        val index = entries.indexOfFirst { it.first === key }
        if (index < 0) entries.add(key to wash) else if (entries[index].second != wash) entries[index] = key to wash
    }

    fun remove(key: Any) {
        entries.removeAll { it.first === key }
    }
}

val LocalShellWashes = staticCompositionLocalOf { ShellWashes() }

/** Glass ground behind a form group or a figure strip. */
@Composable
fun Modifier.subjectPanel(
    cornerRadius: Dp = SubjectMetrics.panelRadius,
    isFilled: Boolean = true
): Modifier {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(cornerRadius)
    val fill = if (isFilled) tokens.glassFill(0.09) else Color.Transparent
    return this
        .background(fill, shape)
        .border(0.5.dp, tokens.glassStroke(0.13), shape)
}

/**
 * The ground for a panel shown in a `Dialog`. A panel's own fill is 9% glass, made to sit on a
 * page; in a dialog nothing is under it but the dimmed screen, which showed through (the
 * challenge form's date picker could not be read over the rows behind it).
 */
@Composable
fun Modifier.dialogGround(cornerRadius: Dp = SubjectMetrics.panelRadius): Modifier =
    background(LocalKudosTokens.current.background, RoundedCornerShape(cornerRadius))

/** Hairline under a panel row. [inset] is 14dp so the line starts under the label. */
@Composable
fun SubjectRowSeparator(
    inset: Dp = 14.dp,
    modifier: Modifier = Modifier
) {
    Box(
        modifier
            .padding(start = inset)
            .fillMaxWidth()
            .height(0.5.dp)
            .background(LocalKudosTokens.current.glassStroke(0.09))
    )
}

/** Uppercase subject label and the short rule under it. */
@Composable
fun SubjectKicker(
    text: String,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    trailingCount: Int = 0,
    size: TextUnit = 10.sp,
    ruleWidth: Dp = SubjectMetrics.kickerRuleWidth,
    ruleSpacing: Dp = 6.dp,
    maxLines: Int = 1
) {
    val tokens = LocalKudosTokens.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ruleSpacing)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = text.uppercase(),
                color = palette.accent,
                fontSize = size,
                lineHeight = (size.value * 1.4f).sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (size.value * 0.11f).sp,
                maxLines = maxLines,
                overflow = TextOverflow.Ellipsis
            )
            if (trailingCount > 0) {
                Text(
                    text = "+$trailingCount",
                    color = tokens.secondaryInk,
                    fontSize = size,
                    lineHeight = (size.value * 1.4f).sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1
                )
            }
        }
        Box(
            Modifier
                .size(width = ruleWidth, height = SubjectMetrics.kickerRuleHeight)
                .background(palette.accent, RoundedCornerShape(percent = 50))
        )
    }
}

/** Kicker, rule, 32sp title, and an optional subtitle on the wash. */
@Composable
fun SubjectHeaderBlock(
    kicker: String,
    title: String,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    kickerTrailingCount: Int = 0,
    subtitle: String? = null,
    gutter: Dp = SubjectMetrics.headerGutter,
    trailing: (@Composable () -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val accessibilityFontScale = isAccessibilityFontScale()
    val isOneWord = title.none { it.isWhitespace() }
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = gutter),
        verticalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        SubjectKicker(
            text = kicker,
            palette = palette,
            trailingCount = kickerTrailingCount,
            ruleWidth = SubjectMetrics.pageRuleWidth,
            ruleSpacing = 7.dp
        )
        Text(
            text = title,
            color = tokens.primaryInk,
            fontSize = 32.sp,
            lineHeight = 38.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.6).sp,
            style = TextStyle(fontFeatureSettings = "tnum"),
            maxLines = when {
                isOneWord -> 1
                accessibilityFontScale -> Int.MAX_VALUE
                else -> 2
            },
            overflow = TextOverflow.Ellipsis,
            // iOS's minimumScaleFactor (0.5 for one word, 0.7 otherwise). Auto-size counts up from
            // the minimum in 0.25sp steps, so the minimum must sit a whole number of steps below
            // the maximum, or the text never reaches its full size: 22.5, not 22.4.
            autoSize = TextAutoSize.StepBased(
                minFontSize = if (isOneWord) 16.sp else 22.5.sp,
                maxFontSize = 32.sp
            )
        )
        when {
            subtitle != null && trailing != null -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubtitleText(subtitle)
                Box(
                    Modifier
                        .size(4.dp)
                        .background(tokens.secondaryInk.withOpacity(0.4), CircleShape)
                )
                trailing()
            }
            subtitle != null -> SubtitleText(subtitle)
            trailing != null -> trailing()
        }
    }
}

@Composable
private fun SubtitleText(subtitle: String) {
    Text(
        text = subtitle,
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 15.5.sp,
        maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2,
        overflow = TextOverflow.Ellipsis
    )
}

/**
 * Section label, optional count, collapse chevron, and a trailing see-all chevron.
 * The hairline leader was removed on iOS; the spacer keeps the same layout job.
 */
@Composable
fun SectionRuleHeader(
    title: String,
    modifier: Modifier = Modifier,
    count: Int? = null,
    countText: String? = null,
    note: String? = null,
    isCollapsed: Boolean = false,
    onToggleCollapse: (() -> Unit)? = null,
    onSeeAll: (() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val labelSize = 11.sp
    val accessibilityFontScale = isAccessibilityFontScale()
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.gutter),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // The title and what follows it share the whole row up to See All. Beside a weighted
        // spacer the title was held to half the row, and at large text sizes "READING NOW"
        // broke onto two lines with room to spare (audit A6).
        Row(
            Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = title.uppercase(),
                color = tokens.secondaryInk,
                fontSize = labelSize,
                fontWeight = FontWeight.Bold,
                letterSpacing = (11f * 0.127f).sp,
                maxLines = if (accessibilityFontScale) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
            val figure = countText ?: count?.compactCount()
            if (figure != null) {
                Text(
                    text = figure,
                    color = tokens.tertiaryInk,
                    fontSize = labelSize,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1
                )
            }
            if (note != null) {
                Text(
                    text = "· $note",
                    color = tokens.tertiaryInk,
                    fontSize = labelSize,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (onToggleCollapse != null) {
                Icon(
                    imageVector = if (isCollapsed) {
                        Icons.AutoMirrored.Filled.KeyboardArrowRight
                    } else {
                        Icons.Filled.KeyboardArrowDown
                    },
                    contentDescription = if (isCollapsed) "Expand $title" else "Collapse $title",
                    tint = tokens.tertiaryInk,
                    modifier = Modifier
                        .size(10.sp.asDp())
                        .clickable(onClick = onToggleCollapse)
                )
            }
        }
        if (onSeeAll != null) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "See all $title",
                tint = tokens.tertiaryInk,
                modifier = Modifier
                    .size(labelSize.asDp())
                    .clickable(onClick = onSeeAll)
            )
        }
    }
}

/** Rounded glass chip. Rects state something; the pill offers a toggle; dashed invites. */
@Composable
fun SubjectChip(
    text: String,
    modifier: Modifier = Modifier,
    style: SubjectChipStyle = SubjectChipStyle.Neutral,
    leadingIcon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
    palette: SubjectPalette? = null,
    fontWeight: FontWeight? = null,
    horizontalPadding: Dp? = null,
    verticalPadding: Dp? = null,
    maxLines: Int = 1
) {
    val tokens = LocalKudosTokens.current
    val pill = style is SubjectChipStyle.Pill
    val shape = if (pill) RoundedCornerShape(percent = 50) else RoundedCornerShape(SubjectMetrics.chipRadius)
    val foreground = when (style) {
        SubjectChipStyle.Neutral -> tokens.primaryInk
        SubjectChipStyle.Tinted -> palette?.accentOnFill ?: tokens.primaryInk
        SubjectChipStyle.Dashed -> tokens.secondaryInk
        is SubjectChipStyle.Pill -> if (style.isSelected) {
            SubjectPalette.label(palette?.accent ?: tokens.accent)
        } else {
            tokens.primaryInk
        }
    }
    val decoration = when (style) {
        SubjectChipStyle.Neutral -> Modifier
            .background(tokens.glassFill(0.09), shape)
            .border(0.5.dp, tokens.glassStroke(0.14), shape)
        SubjectChipStyle.Tinted -> Modifier
            .background(palette?.chipFill ?: tokens.accent.withOpacity(0.24), shape)
            .border(0.5.dp, palette?.chipStroke ?: tokens.accent.withOpacity(0.5), shape)
        SubjectChipStyle.Dashed -> dashedChip(tokens.glassStroke(0.26))
        is SubjectChipStyle.Pill -> if (style.isSelected) {
            Modifier.background(palette?.accent ?: tokens.accent, shape)
        } else {
            Modifier.background(tokens.glassFill(), shape)
        }
    }
    CompositionLocalProvider(LocalContentColor provides foreground) {
        Row(
            modifier
                .then(decoration)
                .padding(
                    horizontal = horizontalPadding ?: if (pill) 14.dp else 11.dp,
                    vertical = verticalPadding ?: if (pill) 7.dp else 6.dp
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (leadingIcon != null) {
                Icon(
                    imageVector = leadingIcon,
                    contentDescription = null,
                    modifier = Modifier.size(11.sp.asDp()),
                    tint = foreground
                )
            }
            Text(
                text = text,
                // A wrapping chip must reserve the remove glyph's width beside its text.
                modifier = if (trailingIcon != null && maxLines > 1) Modifier.weight(1f, fill = false) else Modifier,
                color = foreground,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                fontWeight = fontWeight ?: if (style == SubjectChipStyle.Tinted) FontWeight.Medium else FontWeight.Normal,
                style = TextStyle(fontFeatureSettings = "tnum"),
                maxLines = maxLines,
                overflow = TextOverflow.Ellipsis
            )
            if (trailingIcon != null) {
                Icon(
                    imageVector = trailingIcon,
                    contentDescription = null,
                    modifier = Modifier.size(10.sp.asDp()),
                    tint = foreground.copy(alpha = foreground.alpha * 0.75f)
                )
            }
        }
    }
}

/** `SubjectChip.Style`: neutral and tinted state, dashed invites, pill toggles. */
sealed class SubjectChipStyle {
    data object Neutral : SubjectChipStyle()
    data object Tinted : SubjectChipStyle()
    data object Dashed : SubjectChipStyle()
    data class Pill(val isSelected: Boolean) : SubjectChipStyle()
}

@Composable
private fun dashedChip(color: Color): Modifier {
    val density = LocalDensity.current
    val strokePx = with(density) { 0.5.dp.toPx() }
    val dash = with(density) { 3.dp.toPx() }
    val radius = with(density) { SubjectMetrics.chipRadius.toPx() }
    return Modifier.drawBehind {
        val inset = strokePx / 2f
        drawRoundRect(
            color = color,
            topLeft = Offset(inset, inset),
            size = Size(size.width - strokePx, size.height - strokePx),
            cornerRadius = CornerRadius(radius, radius),
            style = Stroke(
                width = strokePx,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(dash, dash))
            )
        )
    }
}

/** Four-cell figure strip. One cell can be highlighted, or open somewhere. */
@Composable
fun SubjectStatStrip(
    cells: List<SubjectStatCell>,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val divider = tokens.glassStroke(0.13)
    Row(modifier.fillMaxWidth().subjectPanel()) {
        cells.forEachIndexed { index, cell ->
            StatCell(
                cell = cell,
                palette = palette,
                modifier = Modifier
                    .weight(1f)
                    .drawBehind {
                        if (index > 0) {
                            drawRect(divider, size = Size(0.5.dp.toPx(), size.height))
                        }
                    }
            )
        }
    }
}

/** `SubjectStatStrip.Cell`. */
data class SubjectStatCell(
    val value: String,
    val label: String,
    val isHighlighted: Boolean = false,
    val tint: Color? = null,
    val onClick: (() -> Unit)? = null
)

@Composable
private fun StatCell(
    cell: SubjectStatCell,
    palette: SubjectPalette,
    modifier: Modifier
) {
    val tokens = LocalKudosTokens.current
    val opens = cell.onClick != null
    val figureColor = cell.tint ?: when {
        opens -> palette.accent
        cell.isHighlighted -> palette.accentOnFill
        else -> tokens.primaryInk
    }
    val labelColor = if (opens) palette.accent else tokens.secondaryInk
    Column(
        modifier
            .then(if (cell.onClick != null) Modifier.clickable(onClick = cell.onClick) else Modifier)
            .padding(vertical = 10.dp, horizontal = 6.dp)
            .semantics { contentDescription = "${cell.value} ${cell.label}" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = cell.value,
                color = figureColor,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                style = TextStyle(fontFeatureSettings = "tnum"),
                // A date is the long one ("Jul 8, 2026"): cut to "Jul 8, 20…" at twice the text size.
                maxLines = if (isAccessibilityFontScale()) 2 else 1,
                textAlign = TextAlign.Center,
                overflow = TextOverflow.Ellipsis,
                autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = 13.sp)
            )
            if (opens) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = figureColor,
                    modifier = Modifier.size(9.sp.asDp())
                )
            }
        }
        Text(
            text = cell.label.uppercase(),
            color = labelColor,
            fontSize = 9.sp,
            letterSpacing = (9f * 0.07f).sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            autoSize = TextAutoSize.StepBased(minFontSize = 6.25.sp, maxFontSize = 9.sp)
        )
    }
}

/**
 * 68dp read-progress ring. [state] is the word under the percentage. In a slot
 * shorter than [diameter] it shrinks as a whole (ring, stroke and labels), so
 * it stays round and "READING" is never clipped.
 */
@Composable
fun WorkProgressRing(
    progress: Double,
    modifier: Modifier = Modifier,
    state: String? = null,
    diameter: Dp = SubjectMetrics.ringDiameter,
    tint: Color? = null
) {
    BoxWithConstraints(
        modifier.sizeIn(maxWidth = diameter, maxHeight = diameter).aspectRatio(1f),
        contentAlignment = Alignment.Center
    ) {
        WorkProgressRingSized(progress, state, minOf(maxWidth, maxHeight, diameter), tint)
    }
}

@Composable
private fun WorkProgressRingSized(
    progress: Double,
    state: String?,
    diameter: Dp,
    tint: Color?
) {
    val modifier: Modifier = Modifier
    val tokens = LocalKudosTokens.current
    val clamped = progress.coerceIn(0.0, 1.0)
    val percent = (clamped * 100.0).roundToInt()
    val scaledStroke = diameter * (SubjectMetrics.ringStroke.value / SubjectMetrics.ringDiameter.value)
    val stroke = if (scaledStroke < 2.5.dp) 2.5.dp else scaledStroke
    val track = Color.Black.withOpacity(if (tokens.theme.isDarkFamily) 0.30 else 0.12)
    val progressColor = tint ?: if (tokens.theme.isDarkFamily) {
        Color.White
    } else {
        tokens.primaryInk.withOpacity(0.8)
    }
    val percentSize = with(LocalDensity.current) {
        (diameter * (15f / SubjectMetrics.ringDiameter.value)).toSp()
    }
    val stateSize = with(LocalDensity.current) {
        (diameter * (8f / SubjectMetrics.ringDiameter.value)).toSp()
    }
    val stateTracking = with(LocalDensity.current) {
        (diameter * (0.09f * 8f / SubjectMetrics.ringDiameter.value)).toSp()
    }
    val spoken = when {
        state != null -> "$percent percent, $state"
        percent > 0 -> "$percent percent"
        else -> "Not started"
    }
    Box(
        modifier
            // Square even when the slot is shorter than [diameter]: a plain
            // size() let the height clamp while the width did not, and the
            // arc drew as an ellipse (owner report, 2026-10-02).
            .sizeIn(maxWidth = diameter, maxHeight = diameter)
            .aspectRatio(1f)
            .semantics {
                contentDescription = "Reading progress"
                stateDescription = spoken
            },
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val strokePx = stroke.toPx()
            val side = minOf(size.width, size.height)
            val arcSize = Size(side - strokePx, side - strokePx)
            val topLeft = Offset((size.width - side + strokePx) / 2f, (size.height - side + strokePx) / 2f)
            val arc = Stroke(width = strokePx, cap = StrokeCap.Round)
            drawArc(track, 0f, 360f, false, topLeft, arcSize, style = arc)
            if (clamped > 0.0) {
                drawArc(
                    color = progressColor,
                    startAngle = -90f,
                    sweepAngle = (clamped * 360.0).toFloat(),
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = arc
                )
            }
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(stroke + 2.dp)
        ) {
            if (percent > 0 || state != null) {
                Text(
                    text = "$percent%",
                    color = tokens.primaryInk,
                    fontSize = percentSize,
                    fontWeight = FontWeight.SemiBold,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                    maxLines = 1
                )
            }
            if (state != null) {
                Text(
                    text = state.uppercase(),
                    color = tokens.secondaryInk,
                    fontSize = stateSize,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = stateTracking,
                    maxLines = 1
                )
            }
        }
    }
}

/**
 * 22dp accent square from Account's shortcut tile (`AccountShortcutGridTile`).
 * There is no separate iOS type named AccountIconSquare; this is that square.
 */
@Composable
fun AccentIconSquare(
    icon: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    accent: Color = LocalKudosTokens.current.accent
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(6.dp)
    Box(
        modifier
            .size(22.dp)
            .background(accent.withOpacity(0.16), shape)
            .border(0.5.dp, tokens.glassStroke(0.1), shape),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = accent,
            modifier = Modifier.size(12.sp.asDp())
        )
    }
}

/**
 * A toolbar button: Material's plain icon button (48dp to touch, a ripple, no container), where
 * iOS draws a glass circle. Owner, 2026-10-04: one product on both platforms, but Android is not
 * to look like a copy of iOS. [isAccented] is Material's tonal icon button: an accent-tinted
 * container under a glyph that reads on it in every theme (the bare accent does not on Dark).
 * The name is the glass design's; it stays until the owner has seen this look.
 */
@Composable
fun ToolbarCircleButton(
    onClick: () -> Unit,
    accessibilityName: String,
    modifier: Modifier = Modifier,
    isAccented: Boolean = false,
    palette: SubjectPalette? = null,
    badge: String? = null,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val accent = palette?.accent ?: tokens.accent
    val named = modifier.semantics { contentDescription = accessibilityName }
    val glyph: @Composable () -> Unit = {
        if (badge == null) content() else BadgedBox(badge = { ToolbarBadge(badge, accent) }) { content() }
    }
    if (isAccented) {
        FilledTonalIconButton(
            onClick = onClick,
            modifier = named,
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = accent.withOpacity(AccentContainerOpacity),
                contentColor = (palette ?: LocalSubjectPalette.current).accentOnFill
            ),
            content = glyph
        )
    } else {
        IconButton(
            onClick = onClick,
            modifier = named,
            colors = IconButtonDefaults.iconButtonColors(contentColor = tokens.primaryInk),
            content = glyph
        )
    }
}

/** How strongly the accent tints a container under an on-accent glyph: toolbar buttons, the selected tab. */
const val AccentContainerOpacity = 0.24

@Composable
private fun ToolbarBadge(text: String, accent: Color) {
    Badge(containerColor = accent, contentColor = SubjectPalette.label(accent)) {
        Text(text, style = LocalTextStyle.current.copy(fontFeatureSettings = "tnum"), maxLines = 1)
    }
}

/**
 * Urgency amber matching iOS `Color.subjectAmber` (#FFA00A).
 * Used when an item in Recently Deleted expires in under a week.
 */
val SubjectAmber = Color(0xFFFFA00A)

/**
 * 28dp selection bubble matching iOS `WorkSelectionBubble`.
 * When selected: filled with [accent] and a white checkmark.
 * When unselected: transparent glass fill with a subtle stroke.
 */
@Composable
fun WorkSelectionBubble(
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    accent: Color = LocalKudosTokens.current.accent,
    palette: SubjectPalette? = null
) {
    val tokens = LocalKudosTokens.current
    val effectiveAccent = palette?.accent ?: accent
    Box(
        modifier = modifier
            .size(28.dp)
            .clip(CircleShape)
            .then(
                if (isSelected) {
                    Modifier.background(effectiveAccent)
                } else {
                    Modifier
                        .background(tokens.glassFill())
                        .border(1.25.dp, tokens.secondaryInk.copy(alpha = 0.55f), CircleShape)
                }
            ),
        contentAlignment = Alignment.Center
    ) {
        if (isSelected) {
            Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/**
 * "+" in the toolbar: a plain icon button with an accent glyph. [prominent] is Material's filled
 * icon button in the accent (iOS `.glassProminent`, which iOS uses only for the queue page's Add Works).
 */
@Composable
fun ToolbarAddButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accessibilityName: String = "Add",
    palette: SubjectPalette? = null,
    prominent: Boolean = false
) {
    if (!prominent) {
        ToolbarCircleButton(
            onClick = onClick, accessibilityName = accessibilityName, modifier = modifier,
            isAccented = true, palette = palette
        ) {
            Icon(Icons.Filled.Add, contentDescription = null)
        }
        return
    }
    val fill = palette?.tint ?: LocalKudosTokens.current.accent // iOS .tint(subjectPalette.tint)
    FilledIconButton(
        onClick = onClick,
        modifier = modifier.semantics { contentDescription = accessibilityName },
        colors = IconButtonDefaults.filledIconButtonColors(
            containerColor = fill, contentColor = SubjectPalette.label(fill) // iOS .prominentLabel()
        )
    ) {
        Icon(Icons.Filled.Add, contentDescription = null)
    }
}

/**
 * Filter control and its count badge: a plain Material icon button. Active, it is the tonal
 * one (an accent-tinted container) with the numeric badge.
 */
@Composable
fun FilterButton(
    filtersActive: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    badgeCount: Int = 0,
    onClearFilters: (() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val tint = if (filtersActive) LocalSubjectPalette.current.accentOnFill else tokens.primaryInk
    var menuOpen by remember { mutableStateOf(false) }
    val label = if (badgeCount > 0) "Filter, $badgeCount active" else "Filter"
    Box(modifier) {
        Box(
            Modifier
                // Material's icon button written out: that one has no long press, and this clears.
                .minimumInteractiveComponentSize()
                .size(40.dp)
                .clip(CircleShape)
                .background(if (filtersActive) tokens.accent.withOpacity(AccentContainerOpacity) else Color.Transparent)
                .combinedClickable(
                    role = Role.Button,
                    onClick = onClick,
                    onLongClick = if (filtersActive && onClearFilters != null) {
                        { menuOpen = true }
                    } else {
                        null
                    }
                )
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center
        ) {
            BadgedBox(badge = {
                if (badgeCount > 0) ToolbarBadge(if (badgeCount > 99) "99+" else badgeCount.toString(), tokens.accent)
            }) {
                Icon(imageVector = Icons.Filled.FilterList, contentDescription = null, tint = tint)
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text("Clear All Filters") },
                onClick = {
                    menuOpen = false
                    onClearFilters?.invoke()
                }
            )
        }
    }
}

/**
 * Horizontal segmented tab switcher: the one control in `SubjectSegmentedControl.kt`, under the
 * names its first callers used. It was a second copy, and only one of the two could be taught
 * to keep its labels whole at an accessibility text size.
 */
@Composable
fun <T> SubjectSegmentedControl(
    items: List<T>,
    selectedItem: T,
    onItemSelected: (T) -> Unit,
    labelProvider: (T) -> String,
    modifier: Modifier = Modifier
) = SubjectSegmentedControl(options = items, selected = selectedItem, onSelect = onItemSelected,
    title = labelProvider, modifier = modifier)
