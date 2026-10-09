package io.github.cidy02.kudos.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.width
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

/**
 * The frame every Settings page shares with the hub: no bar title (the header
 * names the page), then a status-bar inset plus 56.dp, then the kicker and title.
 */
@Composable
fun SettingsPage(
    title: String,
    kicker: String = "SETTINGS",
    subtitle: String? = null,
    content: LazyListScope.() -> Unit
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }
    val palette = LocalSubjectPalette.current
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 32.dp)
    ) {
        item {
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
            SubjectHeaderBlock(
                kicker = kicker,
                title = title,
                subtitle = subtitle,
                palette = palette,
                gutter = SubjectMetrics.accountGutter
            )
        }
        content()
    }
}

/** Plain text entry on the same tokens as the note editor; no Material text-field chrome. */
@Composable
fun SubjectTextFieldRow(
    label: String,
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
    multiline: Boolean = false,
    enabled: Boolean = true,
    error: String? = null,
    autocorrect: Boolean = true,
    /** The label above the field rather than beside it; for a narrow place such as a dialog. */
    stackedLabel: Boolean = false,
    /** The writing tag field uses this row without a second visible label. */
    fieldOnly: Boolean = false,
    onSubmit: (() -> Unit)? = null,
    keyboardType: KeyboardType = KeyboardType.Text,
    leading: @Composable () -> Unit = {},
    trailing: @Composable () -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    val stacked = multiline || stackedLabel || fieldOnly || isAccessibilityFontScale()
    val style = TextStyle(color = if (enabled) tokens.primaryInk else tokens.secondaryInk,
        fontSize = 14.5.sp, lineHeight = 20.sp, textAlign = if (stacked) TextAlign.Start else TextAlign.End)
    val focus = remember { FocusRequester() }
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val hug = remember(value, placeholder, style, density) {
        // Room for the cursor after the last character.
        with(density) { measurer.measure(value.ifEmpty { placeholder }, style, softWrap = false, maxLines = 1).size.width.toDp() } + 3.dp
    }
    val input: @Composable () -> Unit = {
        // A single-line field lays its text out unbounded and scrolls, so it ignores the
        // alignment: the value sat at the left of its box while the placeholder sat at the
        // right. The field is instead as wide as its text and the box places it at the end, as
        // iOS's trailing fields; a long value still scrolls. A tap anywhere in the box reaches it.
        // The width is measured here: the field's own intrinsic width runs one edit behind and
        // cut the last character.
        Box(Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, indication = null,
            enabled = enabled) { focus.requestFocus() },
            contentAlignment = if (stacked) Alignment.CenterStart else Alignment.CenterEnd) {
            BasicTextField(value = value, onValueChange = onValueChange, enabled = enabled,
                singleLine = !multiline, minLines = if (multiline) 2 else 1, maxLines = if (multiline) 6 else 1,
                textStyle = style, cursorBrush = SolidColor(tokens.accent),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = autocorrect,
                    keyboardType = keyboardType,
                    imeAction = if (onSubmit != null) ImeAction.Search else ImeAction.Default),
                keyboardActions = if (onSubmit == null) KeyboardActions() else KeyboardActions(onAny = { onSubmit() }),
                modifier = (if (stacked) Modifier.fillMaxWidth() else Modifier.width(hug))
                    .focusRequester(focus).semantics { contentDescription = io.github.cidy02.kudos.ui.subject.spokenFormLabel(label) },
                decorationBox = { inner ->
                    Box {
                        if (value.isEmpty()) Text(placeholder, color = tokens.tertiaryInk, style = style)
                        inner()
                    }
                })
        }
    }
    Column {
        if (fieldOnly) Row(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            leading()
            Box(Modifier.weight(1f)) { input() }
            trailing()
        } else if (stacked) Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 11.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
            input()
        } else SubjectFormRow(label, trailing = { Box(Modifier.fillMaxWidth(0.55f)) { input() } })
        if (!error.isNullOrEmpty()) Text(error, color = SubjectPalette.fromHue(0.0, tokens.theme).accent,
            fontSize = 11.5.sp, lineHeight = 17.sp,
            modifier = Modifier.padding(horizontal = 13.dp).padding(bottom = 8.dp))
    }
}

/** iOS grouped-form section label: sentence case, secondary, above the panel. */
@Composable
fun SettingsGroupLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            .padding(bottom = 8.dp),
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 15.sp,
        lineHeight = 21.sp
    )
}

@Composable
fun SettingsPanel(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            // A panel spans the page whatever it holds: one with a single short line of
            // text used to shrink to that line.
            .fillMaxWidth()
            .subjectPanel(),
        content = content
    )
}

@Composable
fun SettingsFootnote(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            .padding(top = 8.dp),
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 13.sp,
        lineHeight = 18.sp
    )
}

@Composable
fun SettingsSection(
    footnote: String?,
    label: String? = null,
    top: Dp = 22.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(Modifier.padding(top = top)) {
        if (label != null) SettingsGroupLabel(label)
        SettingsPanel(content = content)
        if (footnote != null) SettingsFootnote(footnote)
    }
}

/** An accent action row: the iOS form button (destructive or tinted). */
@Composable
fun SettingsActionRow(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    contentDescription: String? = null,
    destructive: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val color = when {
        !enabled -> tokens.secondaryInk.copy(alpha = 0.45f)
        destructive -> MaterialTheme.colorScheme.error
        // The palette's accent, which is tuned to be read on each theme's page. The raw
        // accent (AO3 red by default) is about 1.8 to 1 on a dark panel: "Export Backup…"
        // and "Submit sign-up" could barely be read in Dark and OLED (audit A6).
        else -> tokens.scopePalette.accent
    }
    SettingsIconRow(
        label = label,
        color = color,
        icon = icon,
        iconTint = color,
        enabled = enabled,
        onClick = onClick,
        modifier = modifier,
        contentDescription = contentDescription
    )
}

/** A disclosure row. The icon, when present, is the accent glyph iOS draws. */
@Composable
fun SettingsLinkRow(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    value: String? = null
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(22.dp))
        }
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            color = tokens.primaryInk,
            fontSize = 16.sp
        )
        if (value != null) {
            Text(text = value, color = tokens.secondaryInk, fontSize = 16.sp)
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = tokens.tertiaryInk,
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
private fun SettingsIconRow(
    label: String,
    color: Color,
    icon: ImageVector?,
    iconTint: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier,
    contentDescription: String?
) {
    Row(
        modifier
            .fillMaxWidth()
            .semantics {
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(22.dp))
        }
        Text(text = label, color = color, fontSize = 16.sp, lineHeight = 22.sp)
    }
}

/** Single-value slider beside the settings rows, using the same tokens as FilterRangeSlider. */
@Composable
fun SubjectSliderRow(
    label: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    formatValue: (Float) -> String,
    onValueChangeFinished: (Float) -> Unit,
    accessibilityLabel: String = label
) {
    val tokens = LocalKudosTokens.current
    var sliderValue by remember(value) { mutableStateOf(value) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp)
            Text(formatValue(sliderValue), color = tokens.secondaryInk, fontSize = 15.sp, lineHeight = 21.sp)
        }
        Slider(
            value = sliderValue,
            onValueChange = { sliderValue = it },
            onValueChangeFinished = { onValueChangeFinished(sliderValue) },
            valueRange = valueRange,
            steps = steps.coerceAtLeast(0),
            colors = SliderDefaults.colors(
                thumbColor = tokens.accent,
                activeTrackColor = tokens.accent,
                inactiveTrackColor = tokens.glassFill(0.18)
            ),
            modifier = Modifier.fillMaxWidth().semantics {
                contentDescription = accessibilityLabel
                stateDescription = formatValue(sliderValue)
            }
        )
    }
}
