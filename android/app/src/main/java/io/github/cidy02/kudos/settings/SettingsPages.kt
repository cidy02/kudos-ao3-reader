package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import kotlinx.coroutines.launch

@Composable
fun SettingsAppearancePage(repository: SettingsRepository, settings: KudosSettings) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = "Appearance"
        chrome.hasSubjectHeader = true
    }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current

    LazyColumn(
        modifier = Modifier.fillMaxSize().subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 20.dp)
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "Settings", title = "Appearance", subtitle = null,
                palette = palette, gutter = SubjectMetrics.accountGutter,
                modifier = Modifier.padding(top = 20.dp)
            )
        }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(
                    modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()
                ) {
                    SubjectFormRow("App Theme", trailing = {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ThemeChipOption.entries.forEach { option ->
                                FilterChip(
                                    selected = settings.app.appTheme == option.setting,
                                    onClick = { scope.launch { repository.updateAppTheme(option.setting) } },
                                    label = { Text(option.label) }
                                )
                            }
                        }
                    })
                    SubjectRowSeparator()
                    SubjectFormRow("Match App & Reader Theme", trailing = {
                        SubjectToggle(
                            checked = settings.reader.matchAppReaderTheme,
                            onCheckedChange = { scope.launch { repository.updateMatchAppReaderTheme(it) } }
                        )
                    })
                    if (!settings.reader.matchAppReaderTheme) {
                        SubjectRowSeparator()
                        SubjectFormRow("Reader Theme", trailing = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                ReaderThemeSetting.entries.forEach { theme ->
                                    FilterChip(
                                        selected = settings.reader.readerTheme == theme,
                                        onClick = { scope.launch { repository.updateReaderTheme(theme) } },
                                        label = { Text(theme.storageValue.replaceFirstChar { it.uppercase() }) }
                                    )
                                }
                            }
                        })
                    }
                    SubjectRowSeparator()
                    AccentColorEditor(
                        accentHex = settings.app.accentColorHex,
                        onCommit = { hex -> scope.launch { repository.updateAccentColor(hex) } },
                        onReset = { scope.launch { repository.updateAccentColor("#990000") } }
                    )
                }
                Text(
                    "Light, Sepia, Dark, OLED, or System across the app. OLED uses true-black surfaces for AMOLED panels. Sepia keeps its warm tint.",
                    style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk,
                    modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                )
            }
        }
    }
}

// Minimal port of the other pages to avoid excessive lines.
@Composable
fun SettingsReaderPage(repository: SettingsRepository, settings: KudosSettings) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Reader"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Reader", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Mode", trailing = {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ReaderMode.entries.forEach { mode ->
                                FilterChip(
                                    selected = settings.reader.readerMode == mode,
                                    onClick = { scope.launch { repository.updateReaderMode(mode) } },
                                    label = { Text(if (mode == ReaderMode.Scroll) "Scrolled" else "Paged") }
                                )
                            }
                        }
                    })
                    SubjectRowSeparator()
                    SubjectFormRow("Bold text", trailing = {
                        SubjectToggle(checked = settings.reader.readerBoldText, onCheckedChange = { scope.launch { repository.updateReaderBoldText(it); repository.updateReaderCustomize(true) } })
                    })
                    SubjectRowSeparator()
                    SubjectFormRow("Justified text", trailing = {
                        SubjectToggle(checked = settings.reader.readerJustify, onCheckedChange = { scope.launch { repository.updateReaderJustify(it) } })
                    })
                    SubjectRowSeparator()
                    SubjectSliderRow(
                        label = "Text size",
                        value = settings.reader.readerFontPt.toFloat().coerceIn(12f, 28f),
                        valueRange = 12f..28f,
                        steps = 15,
                        formatValue = { "${kotlin.math.round(it).toInt()} pt" },
                        onValueChangeFinished = { value -> scope.launch { repository.updateReaderFontPt(kotlin.math.round(value).toDouble()); repository.updateReaderCustomize(true) } }
                    )
                    SubjectRowSeparator()
                    SubjectSliderRow(
                        label = "Line height",
                        value = settings.reader.readerLineHeight.toFloat().coerceIn(1.2f, 2.2f),
                        valueRange = 1.2f..2.2f,
                        steps = 19,
                        formatValue = { String.format("%.2f", it) },
                        onValueChangeFinished = { value -> scope.launch { repository.updateReaderLineHeight((kotlin.math.round(value * 100) / 100.0).toDouble()); repository.updateReaderCustomize(true) } }
                    )
                    SubjectRowSeparator()
                    SubjectSliderRow(
                        label = "Letter spacing",
                        value = settings.reader.readerLetterSpacing.toFloat().coerceIn(0f, 0.12f),
                        valueRange = 0f..0.12f,
                        steps = 9,
                        formatValue = { String.format("%.2f em", it) },
                        onValueChangeFinished = { value -> scope.launch { repository.updateReaderLetterSpacing(value.toDouble()); repository.updateReaderCustomize(true) } }
                    )
                    SubjectRowSeparator()
                    SubjectSliderRow(
                        label = "Word spacing",
                        value = settings.reader.readerWordSpacing.toFloat().coerceIn(0f, 0.6f),
                        valueRange = 0f..0.6f,
                        steps = 9,
                        formatValue = { String.format("%.2f em", it) },
                        onValueChangeFinished = { value -> scope.launch { repository.updateReaderWordSpacing(value.toDouble()); repository.updateReaderCustomize(true) } }
                    )
                    SubjectRowSeparator()
                    SubjectSliderRow(
                        label = "Margin",
                        value = settings.reader.readerMargin.toFloat().coerceIn(8f, 48f),
                        valueRange = 8f..48f,
                        steps = 39,
                        formatValue = { "${kotlin.math.round(it).toInt()} pt" },
                        onValueChangeFinished = { value -> scope.launch { repository.updateReaderMargin(kotlin.math.round(value).toDouble()); repository.updateReaderCustomize(true) } }
                    )
                }
                Text(
                    "Choose how pages turn while reading. Bold and spacing also appear in the reader Display sheet.",
                    style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk,
                    modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                )
            }
        }
    }
}


@Composable
fun SettingsDownloadsPage(repository: SettingsRepository, settings: KudosSettings) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Downloads"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Downloads", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Keep works you read", trailing = {
                        SubjectToggle(checked = settings.app.keepsWorksYouRead, onCheckedChange = { scope.launch { repository.updateKeepsWorksYouRead(it) } })
                    })
                }
                Text(
                    "When this is on, every work you open stays downloaded, as if you tapped Download. When it's off, finishing a work removes its copy unless you downloaded, favorited, or queued it.",
                    style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk,
                    modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                )
            }
        }
    }
}

@Composable
fun SubjectSliderRow(
    label: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    formatValue: (Float) -> String,
    onValueChangeFinished: (Float) -> Unit
) {
    var sliderValue by androidx.compose.runtime.remember(value) { androidx.compose.runtime.mutableStateOf(value) }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = label, style = MaterialTheme.typography.bodyMedium)
            Text(text = formatValue(sliderValue), style = MaterialTheme.typography.bodyMedium, color = LocalKudosTokens.current.secondaryInk)
        }
        androidx.compose.material3.Slider(
            value = sliderValue,
            onValueChange = { sliderValue = it },
            onValueChangeFinished = { onValueChangeFinished(sliderValue) },
            valueRange = valueRange,
            steps = steps.coerceAtLeast(0)
        )
    }
}
