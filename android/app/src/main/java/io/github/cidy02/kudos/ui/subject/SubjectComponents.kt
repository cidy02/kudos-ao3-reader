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
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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
    val chromeButton = 34.dp
    /** Tab-root toolbar circle. iOS draws a 44pt glass circle with a 17pt glyph. */
    val toolbarCircle = 44.dp
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
    val heightPx = with(LocalDensity.current) { washHeight.toPx() }
    val backdrop = palette.theme.cardBackdrop
    val brush = palette.wash(heightPx)
    return drawBehind {
        drawRect(backdrop)
        drawRect(brush = brush, size = Size(size.width, heightPx))
    }
}

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
    ruleSpacing: Dp = 6.dp
) {
    val tokens = LocalKudosTokens.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(ruleSpacing)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = text.uppercase(),
                color = palette.accent,
                fontSize = size,
                fontWeight = FontWeight.Bold,
                letterSpacing = (size.value * 0.11f).sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (trailingCount > 0) {
                Text(
                    text = "+$trailingCount",
                    color = tokens.secondaryInk,
                    fontSize = size,
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
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.6).sp,
            style = TextStyle(fontFeatureSettings = "tnum"),
            maxLines = if (title.any { it.isWhitespace() }) 2 else 1,
            overflow = TextOverflow.Ellipsis
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
        maxLines = 2,
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
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.gutter),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = title.uppercase(),
            color = tokens.secondaryInk,
            fontSize = labelSize,
            fontWeight = FontWeight.Bold,
            letterSpacing = (11f * 0.127f).sp,
            maxLines = 1,
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
        Spacer(Modifier.weight(1f))
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
    verticalPadding: Dp? = null
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
                color = foreground,
                fontSize = 13.sp,
                fontWeight = fontWeight ?: if (style == SubjectChipStyle.Tinted) FontWeight.Medium else FontWeight.Normal,
                style = TextStyle(fontFeatureSettings = "tnum"),
                maxLines = 1,
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
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
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
            overflow = TextOverflow.Ellipsis
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
    val percentSize = (diameter.value * 15f / SubjectMetrics.ringDiameter.value).sp
    val stateSize = (diameter.value * 8f / SubjectMetrics.ringDiameter.value).sp
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
                    letterSpacing = (diameter.value * 0.09f * 8f / SubjectMetrics.ringDiameter.value).sp,
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

/** 34dp glass circle used for back, filter, and overflow chrome. */
@Composable
fun GlassCircleButton(
    onClick: () -> Unit,
    accessibilityName: String,
    modifier: Modifier = Modifier,
    isAccented: Boolean = false,
    palette: SubjectPalette? = null,
    badge: String? = null,
    diameter: Dp = SubjectMetrics.chromeButton,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val accent = palette?.accent ?: tokens.accent
    val fill = if (isAccented) accent.withOpacity(0.30) else tokens.glassFill()
    val stroke = if (isAccented) accent.withOpacity(0.60) else tokens.glassStroke()
    val foreground = if (isAccented) palette?.accentOnFill ?: tokens.accent else tokens.primaryInk
    val glyph = 17.sp.asDp()
    Box(
        modifier
            .size(diameter)
            .semantics { contentDescription = accessibilityName }
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(fill, CircleShape)
                .border(0.5.dp, stroke, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            CompositionLocalProvider(LocalContentColor provides foreground) {
                Box(Modifier.size(glyph), contentAlignment = Alignment.Center) {
                    content()
                }
            }
        }
        if (badge != null) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 2.dp, y = (-2).dp)
                    .defaultMinSize(minWidth = 16.dp, minHeight = 16.dp)
                    .background(accent, RoundedCornerShape(percent = 50))
                    .border(1.5.dp, tokens.background, RoundedCornerShape(percent = 50))
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = badge,
                    color = tokens.background,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.Bold,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                    textAlign = TextAlign.Center,
                    maxLines = 1
                )
            }
        }
    }
}

/**
 * 44dp glass circle used for root-tab toolbar chrome (Home, Library, Account).
 * Matches iOS 44pt toolbar glass circle with 17sp glyph.
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
    GlassCircleButton(
        onClick = onClick,
        accessibilityName = accessibilityName,
        modifier = modifier,
        isAccented = isAccented,
        palette = palette,
        badge = badge,
        diameter = SubjectMetrics.toolbarCircle,
        content = content
    )
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
 * 44dp "+" in the toolbar. Glass with an accent glyph, as iOS's `ToolbarIconButton`; [prominent]
 * fills it with the accent (iOS `.glassProminent`, which iOS uses only for the queue page's Add Works).
 */
@Composable
fun ToolbarAddButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accessibilityName: String = "Add",
    palette: SubjectPalette? = null,
    prominent: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val accent = palette?.accent ?: tokens.accent
    val glyph = 17.sp.asDp()
    if (!prominent) {
        ToolbarCircleButton(onClick = onClick, accessibilityName = accessibilityName, modifier = modifier, palette = palette) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = accent, modifier = Modifier.size(glyph))
        }
        return
    }
    val fill = palette?.tint ?: tokens.accent // iOS .tint(subjectPalette.tint)
    Box(
        modifier
            .size(SubjectMetrics.toolbarCircle)
            .semantics { contentDescription = accessibilityName }
            .clip(CircleShape)
            .background(fill)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = null,
            tint = SubjectPalette.label(fill), // iOS .prominentLabel()
            modifier = Modifier.size(glyph)
        )
    }
}

/**
 * Filter control and its count badge. Active tint is the exact accent.
 * Material has no `line.3.horizontal.decrease.circle.fill`, so the active state
 * is the accent-tinted list icon plus the numeric badge.
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
    val tint = if (filtersActive) tokens.accent else tokens.primaryInk
    var menuOpen by remember { mutableStateOf(false) }
    val label = if (badgeCount > 0) "Filter, $badgeCount active" else "Filter"
    Box(modifier) {
        Box(
            Modifier
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = if (filtersActive && onClearFilters != null) {
                        { menuOpen = true }
                    } else {
                        null
                    }
                )
                .semantics { contentDescription = label }
                .padding(8.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.FilterList,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(24.dp)
            )
            if (badgeCount > 0) {
                val badge = if (badgeCount > 99) "99+" else badgeCount.toString()
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 6.dp, y = (-6).dp)
                        .defaultMinSize(minWidth = 15.dp, minHeight = 15.dp)
                        .background(tokens.accent, CircleShape)
                        .padding(horizontal = 3.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = badge,
                        color = Color.White,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        style = TextStyle(fontFeatureSettings = "tnum"),
                        maxLines = 1
                    )
                }
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
