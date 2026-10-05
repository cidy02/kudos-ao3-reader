package io.github.cidy02.kudos.search

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** iOS FilterRangeSlider: open edges clear the bound, typed bounds expand the domain. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilterRangeSlider(
    from: String, to: String, defaultMaximum: Long, onChange: (String, String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    var dragMaximum by remember { mutableStateOf<Long?>(null) }
    val startInteraction = remember { MutableInteractionSource() }
    val endInteraction = remember { MutableInteractionSource() }
    val startDragging by startInteraction.collectIsDraggedAsState()
    val endDragging by endInteraction.collectIsDraggedAsState()
    LaunchedEffect(startDragging, endDragging) {
        if (!startDragging && !endDragging) dragMaximum = null
    }
    val maximum = dragMaximum ?: FilterRangeValues.expandedMaximum(defaultMaximum,
        listOfNotNull(FilterRangeValues.integer(from), FilterRangeValues.integer(to)))
    val lower = (FilterRangeValues.integer(from) ?: 0).coerceIn(0, maximum)
    val upper = (FilterRangeValues.integer(to) ?: maximum).coerceIn(lower, maximum)
    Column(Modifier.padding(horizontal = 13.dp, vertical = 4.dp)) {
        RangeSlider(
            value = lower.toFloat()..upper.toFloat(),
            onValueChange = { range ->
                dragMaximum = maximum
                val nextLower = range.start.toLong().coerceIn(0, maximum)
                val nextUpper = range.endInclusive.toLong().coerceIn(nextLower, maximum)
                onChange(
                    if (range.start == lower.toFloat()) from
                    else if (nextLower == 0L) "" else nextLower.toString(),
                    if (range.endInclusive == upper.toFloat()) to
                    else if (range.endInclusive >= maximum.toFloat()) "" else nextUpper.toString()
                )
            },
            onValueChangeFinished = { dragMaximum = null },
            valueRange = 0f..maximum.toFloat(),
            startInteractionSource = startInteraction,
            endInteractionSource = endInteraction,
            startThumb = { RangeThumb("From", from) },
            endThumb = { RangeThumb("To", to) },
            track = { state ->
                Canvas(Modifier.fillMaxWidth().height(4.dp)) {
                    val y = size.height / 2
                    drawLine(tokens.glassFill(0.18), Offset(0f, y), Offset(size.width, y),
                        strokeWidth = size.height, cap = StrokeCap.Round)
                    if (from.isNotBlank() || to.isNotBlank()) {
                        val start = state.activeRangeStart / maximum.toFloat() * size.width
                        val end = state.activeRangeEnd / maximum.toFloat() * size.width
                        drawLine(tokens.accent, Offset(start, y), Offset(end, y),
                            strokeWidth = size.height, cap = StrokeCap.Round)
                    }
                }
            },
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = tokens.accent, inactiveTrackColor = tokens.glassFill(0.18)
            ),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Range" }
        )
        if (isAccessibilityFontScale()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RangeBoundField("From", from, Modifier.fillMaxWidth()) { onChange(it, to) }
                RangeBoundField("To", to, Modifier.fillMaxWidth()) { onChange(from, it) }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                RangeBoundField("From", from, Modifier.weight(1f)) { onChange(it, to) }
                RangeBoundField("To", to, Modifier.weight(1f)) { onChange(from, it) }
            }
        }
    }
}

@Composable
private fun RangeThumb(title: String, value: String) {
    Box(Modifier.size(22.dp).shadow(2.dp, CircleShape).background(Color.White, CircleShape)
        .semantics { contentDescription = title; stateDescription = value.ifEmpty { "Any" } })
}

@Composable
private fun RangeBoundField(title: String, value: String, modifier: Modifier, onChange: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(modifier.subjectPanel(cornerRadius = 8.dp).padding(horizontal = 11.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = tokens.secondaryInk, fontSize = 12.sp)
        BasicTextField(
            value, { onChange(FilterRangeValues.digitsOnly(it)) }, singleLine = true,
            cursorBrush = SolidColor(tokens.accent),
            textStyle = TextStyle(color = tokens.primaryInk, fontSize = 14.sp, fontFeatureSettings = "tnum"),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.weight(1f).semantics { contentDescription = title },
            decorationBox = { inner ->
                Box {
                    if (value.isEmpty()) Text("Any", color = tokens.secondaryInk, fontSize = 14.sp)
                    inner()
                }
            }
        )
    }
}

/** Pure equivalents of iOS FilterRangeSlider's numeric helpers, saturating at Long.maxValue. */
internal object FilterRangeValues {
    fun digitsOnly(text: String): String = text.filter { it in '0'..'9' }
    fun integer(text: String): Long? = digitsOnly(text).toLongOrNull()

    fun expandedMaximum(defaultMaximum: Long, values: List<Long>): Long {
        val peak = values.maxOrNull() ?: return defaultMaximum
        if (peak <= defaultMaximum) return defaultMaximum
        val target = kotlin.math.ceil(peak.toDouble() * 1.25).toLong()
        return listOf(1_000L, 2_000L, 5_000L, 10_000L, 20_000L, 50_000L, 100_000L,
            200_000L, 500_000L, 1_000_000L, 2_000_000L, 5_000_000L, 10_000_000L,
            20_000_000L, 50_000_000L).firstOrNull { it >= target } ?: target
    }
}
