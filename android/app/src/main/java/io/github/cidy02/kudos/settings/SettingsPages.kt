package io.github.cidy02.kudos.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun SettingsAppearancePage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    var showCustomize by remember { mutableStateOf(false) }
    val matched = settings.reader.matchAppReaderTheme
    val themeFootnote = (if (matched) {
        "Choose Light, Sepia, Dark, or OLED for Kudos and the reader."
    } else {
        "You can choose different themes for Kudos and the reader."
    }) + " Your accent colour appears in Light, Dark, and OLED; Sepia keeps its warm tint."
    val appOption = ThemeChipOption.entries.firstOrNull { it.setting == settings.app.appTheme }
        ?: ThemeChipOption.Light
    val alreadyAo3Red = settings.app.accentColorHex.equals("#990000", ignoreCase = true)

    SettingsPage(title = "Appearance") {
        item {
            SettingsSection(label = "Theme", footnote = themeFootnote) {
                SubjectSegmentedControl(
                    options = ThemeChipOption.entries,
                    selected = appOption,
                    onSelect = { option -> scope.launch { repository.updateAppTheme(option.setting) } },
                    title = { it.label },
                    contentDescription = "App Theme",
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    "Match App & Reader Theme",
                    trailing = {
                        SubjectToggle(
                            checked = matched,
                            onCheckedChange = { scope.launch { repository.updateMatchAppReaderTheme(it) } }
                        )
                    }
                )
                if (!matched) {
                    SubjectRowSeparator()
                    Column(Modifier.padding(horizontal = 13.dp, vertical = 10.dp)) {
                        Text(
                            text = "Reader Theme",
                            color = tokens.secondaryInk,
                            fontSize = 13.sp,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                        SubjectSegmentedControl(
                            options = ReaderThemeSetting.entries,
                            selected = settings.reader.readerTheme,
                            onSelect = { theme -> scope.launch { repository.updateReaderTheme(theme) } },
                            title = { it.storageValue.replaceFirstChar { char -> char.uppercase() } },
                            contentDescription = "Reader Theme"
                        )
                    }
                }
                SubjectRowSeparator()
                SubjectFormRow(
                    label = "Accent Color",
                    onClick = { showCustomize = !showCustomize },
                    trailing = { AccentColorWell(color = accentColorOrFallback(settings.app.accentColorHex)) }
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Reset to AO3 Red",
                    enabled = !alreadyAo3Red,
                    onClick = { scope.launch { repository.updateAccentColor("#990000") } }
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Customize Theme…",
                    icon = Icons.Outlined.Tune,
                    onClick = { showCustomize = !showCustomize }
                )
                if (showCustomize) {
                    AccentCustomizeBlock(
                        accentHex = settings.app.accentColorHex,
                        onCommit = { hex -> scope.launch { repository.updateAccentColor(hex) } }
                    )
                }
                SubjectRowSeparator()
                TextSizeSlider(
                    value = settings.reader.readerFontPt.toFloat().coerceIn(12f, 28f),
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderFontPt(kotlin.math.round(value).toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
            }
        }
        item {
            SettingsSection(
                footnote = "Line height, letter spacing, word spacing, and margin also appear in the reader Display sheet."
            ) {
                SubjectSliderRow(
                    label = "Line height",
                    value = settings.reader.readerLineHeight.toFloat().coerceIn(1.2f, 2.2f),
                    valueRange = 1.2f..2.2f,
                    steps = 19,
                    formatValue = { String.format("%.2f", it) },
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderLineHeight((kotlin.math.round(value * 100) / 100.0))
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Letter spacing",
                    value = settings.reader.readerLetterSpacing.toFloat().coerceIn(0f, 0.12f),
                    valueRange = 0f..0.12f,
                    steps = 9,
                    formatValue = { String.format("%.2f em", it) },
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderLetterSpacing(value.toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Word spacing",
                    value = settings.reader.readerWordSpacing.toFloat().coerceIn(0f, 0.6f),
                    valueRange = 0f..0.6f,
                    steps = 9,
                    formatValue = { String.format("%.2f em", it) },
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderWordSpacing(value.toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Margin",
                    value = settings.reader.readerMargin.toFloat().coerceIn(8f, 48f),
                    valueRange = 8f..48f,
                    steps = 39,
                    formatValue = { "${kotlin.math.round(it).toInt()} pt" },
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderMargin(kotlin.math.round(value).toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
            }
        }
    }
}

@Composable
fun SettingsReaderPage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    SettingsPage(title = "Reader") {
        item {
            SettingsSection(
                label = "Reading",
                footnote = "Choose whether you turn pages or scroll while reading."
            ) {
                SubjectSegmentedControl(
                    options = ReaderMode.entries,
                    selected = settings.reader.readerMode,
                    onSelect = { mode -> scope.launch { repository.updateReaderMode(mode) } },
                    title = { mode -> if (mode == ReaderMode.Scroll) "Scrolled" else "Paged" },
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    "Bold text",
                    trailing = {
                        SubjectToggle(
                            checked = settings.reader.readerBoldText,
                            onCheckedChange = {
                                scope.launch {
                                    repository.updateReaderBoldText(it)
                                    repository.updateReaderCustomize(true)
                                }
                            }
                        )
                    }
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    "Justified text",
                    trailing = {
                        SubjectToggle(
                            checked = settings.reader.readerJustify,
                            onCheckedChange = { scope.launch { repository.updateReaderJustify(it) } }
                        )
                    }
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    "Keep screen awake",
                    trailing = {
                        SubjectToggle(
                            checked = settings.reader.keepScreenAwake,
                            onCheckedChange = { scope.launch { repository.updateKeepScreenAwake(it) } }
                        )
                    }
                )
            }
        }
    }
}

@Composable
fun SettingsDownloadsPage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var storageUsed by remember { mutableStateOf("…") }
    LaunchedEffect(Unit) {
        val bytes = withContext(Dispatchers.IO) {
            context.filesDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        }
        storageUsed = Formatter.formatFileSize(context, bytes)
    }
    SettingsPage(title = "Downloads") {
        item {
            SettingsSection(
                footnote = "When this is on, every work you open stays downloaded, as if you tapped " +
                    "Download. When it's off, finishing a work removes its copy unless you " +
                    "downloaded, favorited, or queued it. It stays in your history, and you " +
                    "can download it again."
            ) {
                SubjectFormRow(
                    "Keep works you read",
                    trailing = {
                        SubjectToggle(
                            checked = settings.app.keepsWorksYouRead,
                            onCheckedChange = { scope.launch { repository.updateKeepsWorksYouRead(it) } }
                        )
                    }
                )
            }
        }
        item {
            SettingsSection(
                footnote = "When you subscribe to a work already in your Library, Kudos downloads it " +
                    "if no copy is stored. Privacy and Local Data shows what uses space and " +
                    "lets you remove individual downloads."
            ) {
                SubjectFormRow(
                    "Download on subscribe",
                    trailing = {
                        SubjectToggle(
                            checked = settings.app.downloadOnSubscribe,
                            onCheckedChange = { scope.launch { repository.updateDownloadOnSubscribe(it) } }
                        )
                    }
                )
                SubjectRowSeparator()
                SubjectFormRow("Storage used", value = storageUsed)
            }
        }
    }
}

/** iOS `TextSizeSlider`: a small A, the slider, a large A. Settings sets points; the reader's sheet, percent. */
@Composable
internal fun TextSizeSlider(
    value: Float,
    valueRange: ClosedFloatingPointRange<Float> = 12f..28f,
    steps: Int = 15,
    unit: String = " pt",
    onValueChange: (Float) -> Unit = {},
    onValueChangeFinished: (Float) -> Unit
) {
    val tokens = LocalKudosTokens.current
    var sliderValue by remember(value) { mutableStateOf(value) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 13.dp, vertical = 4.dp)
            .semantics { contentDescription = "Text size, ${kotlin.math.round(sliderValue).toInt()}$unit" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(text = "A", color = tokens.secondaryInk, fontSize = 13.sp)
        Slider(
            value = sliderValue,
            onValueChange = {
                sliderValue = it
                onValueChange(it)
            },
            onValueChangeFinished = { onValueChangeFinished(sliderValue) },
            valueRange = valueRange,
            steps = steps,
            modifier = Modifier.weight(1f),
            colors = accentSliderColors()
        )
        Text(text = "A", color = tokens.primaryInk, fontSize = 22.sp)
    }
}

@Composable
private fun accentSliderColors() = SliderDefaults.colors(
    thumbColor = Color.White,
    activeTrackColor = LocalKudosTokens.current.accent,
    inactiveTrackColor = LocalKudosTokens.current.glassFill(0.28)
)
