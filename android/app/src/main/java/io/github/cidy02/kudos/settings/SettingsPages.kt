package io.github.cidy02.kudos.settings

import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.subject.HsvColorDialog
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.toStoredHex
import io.github.cidy02.kudos.ui.theme.AppAccents
import io.github.cidy02.kudos.ui.theme.DefaultAccentHex
import io.github.cidy02.kudos.ui.theme.parseAccentColor
import kotlinx.coroutines.launch

@Composable
fun SettingsAppearancePage(
    repository: SettingsRepository, settings: KudosSettings,
    customFontRepository: io.github.cidy02.kudos.files.CustomFontRepository? = null
) {
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    var showCustomizeTheme by remember { mutableStateOf(false) }
    var showCustomWarning by remember { mutableStateOf(false) }
    var showCustomPicker by remember { mutableStateOf(false) }
    DebugShotEffect("appearance") { showCustomizeTheme = true }

    val matched = settings.reader.matchAppReaderTheme
    val themeFootnote = if (matched) {
        "Choose Light, Sepia, Dark, or OLED for Kudos and the reader."
    } else {
        "You can choose different themes for Kudos and the reader."
    }
    val appOption = ThemeChipOption.entries.firstOrNull { it.setting == settings.app.appTheme }
        ?: ThemeChipOption.Light
    val shownHex = AppAccents.pickerHex(settings.app.accentColorHex)
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
                            title = { if (it.storageValue == "oled") "OLED" else it.storageValue.replaceFirstChar { char -> char.uppercase() } },
                            contentDescription = "Reader Theme"
                        )
                    }
                }
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Customize Theme…",
                    icon = Icons.Outlined.Tune,
                    onClick = { showCustomizeTheme = true }
                )
                SubjectRowSeparator()
                TextSizeSlider(
                    value = settings.reader.readerFontPt.toFloat().coerceIn(12f, 28f),
                    onValueChangeFinished = { value ->
                        scope.launch {
                            repository.updateReaderFontPt(kotlin.math.round(value).toDouble())
                        }
                    }
                )
            }
        }
        item {
            SettingsSection(
                label = "Accent colour",
                footnote = "Delete and other destructive actions stay system red with every colour. " +
                    "Sepia keeps its warm tint."
            ) {
                AccentColourPicker(
                    accentHex = settings.app.accentColorHex,
                    onSelectNamed = { hex -> scope.launch { repository.updateAccentColor(hex) } },
                    onCustom = { showCustomWarning = true }
                )
            }
        }
    }
    if (showCustomWarning) {
        AlertDialog(
            onDismissRequest = { showCustomWarning = false },
            title = { Text("Use a Custom Colour?") },
            text = {
                Text(
                    "Kudos is designed around its six accent colours. They keep text readable in Light, " +
                        "Sepia, Dark and OLED, and stay clear of the red used for Delete. A custom colour " +
                        "may make some buttons and links harder to read."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showCustomWarning = false
                        showCustomPicker = true
                    }
                ) { Text("Choose a Colour") }
            },
            dismissButton = {
                TextButton(onClick = { showCustomWarning = false }) { Text("Keep AO3 Red") }
            }
        )
    }
    if (showCustomPicker) {
        HsvColorDialog(
            initial = parseAccentColor(shownHex),
            onDismiss = { showCustomPicker = false },
            onConfirm = { color ->
                showCustomPicker = false
                val picked = color.toStoredHex()
                if (!picked.equals(settings.app.accentColorHex, ignoreCase = true)) {
                    scope.launch { repository.updateAccentColor(picked) }
                }
            }
        )
    }
    if (showCustomizeTheme) {
        io.github.cidy02.kudos.reader.CustomizeThemeSheet(repository, customFontRepository,
            onDismiss = { showCustomizeTheme = false })
    }

}

@Composable
private fun AccentColourPicker(
    accentHex: String,
    onSelectNamed: (String) -> Unit,
    onCustom: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val shownHex = AppAccents.pickerHex(accentHex)
    val named = AppAccents.named(shownHex)
    val selectedFill = named?.fillHex
    val customHex = if (named == null) shownHex else null
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clearAndSetSemantics {},
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = named?.name ?: "Custom",
                color = tokens.primaryInk,
                fontSize = 16.sp
            )
            Spacer(Modifier.weight(1f))
            if (shownHex.equals(DefaultAccentHex, ignoreCase = true)) {
                Text(
                    text = "Default",
                    color = Color(0xFF8E8E93),
                    fontSize = 14.sp
                )
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            AppAccents.all.forEach { accent ->
                val isSelected = selectedFill == accent.fillHex
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 44.dp)
                        .semantics(mergeDescendants = true) {
                            contentDescription = accent.name
                            role = Role.Button
                            selected = isSelected
                        }
                        .clickable { onSelectNamed(accent.fillHex) },
                    contentAlignment = Alignment.Center
                ) {
                    AccentSwatch(fill = accent.fill, isSelected = isSelected)
                }
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .semantics(mergeDescendants = true) {
                        contentDescription = "Custom colour"
                        role = Role.Button
                        selected = customHex != null
                    }
                    .clickable(onClick = onCustom),
                contentAlignment = Alignment.Center
            ) {
                AccentCustomWell(selectedHex = customHex)
            }
        }
    }
}

@Composable
private fun AccentSwatch(fill: Color, isSelected: Boolean) {
    val gap = LocalKudosTokens.current.theme.cardSurface
    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
        if (isSelected) {
            Box(
                Modifier
                    .size(40.dp)
                    .border(2.dp, fill, CircleShape)
            )
            Box(
                Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(gap)
            )
        }
        Box(
            Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(fill)
        )
    }
}

private val AccentCustomWheel = listOf(
    Color(0xFFF5C400),
    Color(0xFF5FBF5F),
    Color(0xFF5A9BE0),
    Color(0xFFA57BD8),
    Color(0xFFE86AA0),
    Color(0xFFE5484D),
    Color(0xFFF5C400)
)

@Composable
private fun AccentCustomWell(selectedHex: String?) {
    val theme = LocalKudosTokens.current.theme
    val gap = theme.cardSurface
    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
        if (selectedHex != null) {
            val ringColor = parseAccentColor(selectedHex)
            Box(
                Modifier
                    .size(40.dp)
                    .border(2.dp, ringColor, CircleShape)
            )
            Box(
                Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(gap)
            )
        }
        Box(
            Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(Brush.sweepGradient(AccentCustomWheel))
        )
        Box(
            Modifier
                .size(24.dp)
                .clip(CircleShape)
                .background(gap)
        )
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = null,
            tint = if (theme.isDarkFamily) Color.White else Color(0xFF1C1C1E),
            modifier = Modifier.size(14.dp)
        )
    }
}

@Composable
fun SettingsReaderPage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    SettingsPage(title = "Reader") {
        item {
            // iOS `ReaderSettingsSection`: Layout, Two-page spread on a wide screen, Keep screen
            // awake. Bold and Justify are in Customize Theme on both apps (owner Q29, 2026-10-20);
            // here Justify did nothing with Customize off (A66 #14).
            val wide = androidx.compose.ui.platform.LocalConfiguration.current.smallestScreenWidthDp >= 600
            SettingsSection(
                label = "Reading",
                footnote = if (wide) "On a wide screen, Paged mode can show two pages side by side."
                    else "Choose whether you turn pages or scroll while reading."
            ) {
                SubjectSegmentedControl(
                    options = ReaderMode.entries,
                    selected = settings.reader.readerMode,
                    onSelect = { mode -> scope.launch { repository.updateReaderMode(mode) } },
                    title = { mode -> if (mode == ReaderMode.Scroll) "Scrolled" else "Paged" },
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                )
                SubjectRowSeparator()
                if (wide) {
                    SubjectFormRow(
                        "Two-page spread",
                        trailing = {
                            SubjectToggle(
                                checked = settings.reader.readerTwoPage,
                                enabled = settings.reader.readerMode == ReaderMode.Paged,
                                onCheckedChange = { scope.launch { repository.updateReaderTwoPage(it) } }
                            )
                        }
                    )
                    SubjectRowSeparator()
                }
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
fun SettingsDownloadsPage(
    repository: SettingsRepository, settings: KudosSettings,
    footprintScanner: LocalDataFootprintScanner? = null
) {
    val scope = rememberCoroutineScope()
    var storageUsed by remember(footprintScanner) { mutableStateOf("…") }
    LaunchedEffect(footprintScanner) {
        storageUsed = footprintScanner?.measure()?.let { LocalStorageFootprint.formatted(it.totalBytes) } ?: "—"
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
