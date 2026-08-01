package io.github.cidy02.kudos.settings

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
import io.github.cidy02.kudos.core.model.ReaderFontOption
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

private val AccentPresets = listOf("#990000", "#0B57D0", "#0F6B46", "#7A3E00", "#5B2C6F")

private const val FontPtMin = 12f
private const val FontPtMax = 28f
private const val LineHeightMin = 1.2f
private const val LineHeightMax = 2.2f
private const val MarginMin = 8f
private const val MarginMax = 48f

/** SAF MIME types commonly used for TrueType / OpenType fonts. */
private val FontOpenMimeTypes = arrayOf(
    "font/ttf",
    "font/otf",
    "application/x-font-ttf",
    "application/x-font-otf",
    "application/font-sfnt",
    "application/octet-stream"
)

@Composable
fun SettingsScreen(
    repository: SettingsRepository,
    customFontRepository: CustomFontRepository,
    onOpenBackup: () -> Unit
) {
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val importedFonts by customFontRepository.observeImported()
        .collectAsState(initial = emptyList())
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var fontStatus by remember { mutableStateOf<String?>(null) }
    var fontStatusIsError by remember { mutableStateOf(false) }
    var fontBusy by remember { mutableStateOf(false) }

    fun launchUpdate(block: suspend () -> Unit) {
        scope.launch { block() }
    }

    val importFontLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            fontBusy = true
            fontStatus = null
            try {
                val displayName = withContext(Dispatchers.IO) {
                    queryDisplayName(context, uri)
                }
                if (!CustomFontRepository.isSupportedFontFileName(displayName)) {
                    fontStatusIsError = true
                    fontStatus = "Only .ttf and .otf font files are supported."
                    return@launch
                }
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("Could not read the selected font file.")
                }
                val nameWithoutExt = displayName
                    ?.substringAfterLast('/')
                    ?.substringAfterLast('\\')
                    ?.substringBeforeLast('.')
                    ?.trim()
                    .orEmpty()
                val result = customFontRepository.importFont(
                    displayName = nameWithoutExt,
                    originalFileName = displayName,
                    bytes = bytes
                )
                result.fold(
                    onSuccess = { font ->
                        fontStatusIsError = false
                        fontStatus = "Imported “${font.name}”."
                    },
                    onFailure = { error ->
                        fontStatusIsError = true
                        fontStatus = error.message ?: "Could not import font."
                    }
                )
            } catch (error: Exception) {
                fontStatusIsError = true
                fontStatus = error.message ?: "Could not import font."
            } finally {
                fontBusy = false
            }
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // TopAppBar already titles this screen; keep a short subtitle only.
        item {
            Text(
                text = "Reader, privacy, and backup-compatible app preferences.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item {
            SettingsGroup(title = "Privacy") {
                SettingSwitchRow(
                    label = "Hide mature content",
                    checked = settings.privacy.hideMatureContent,
                    onCheckedChange = { launchUpdate { repository.updateHideMatureContent(it) } }
                )
                SettingChipRow(label = "Mature content mode") {
                    MatureContentMode.entries.forEach { mode ->
                        FilterChip(
                            selected = settings.privacy.matureContentMode == mode,
                            onClick = {
                                launchUpdate { repository.updateMatureContentMode(mode) }
                            },
                            label = { Text(mode.storageValue.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
                SettingSwitchRow(
                    label = "Require device reveal",
                    checked = settings.privacy.requireBiometricToReveal,
                    onCheckedChange = {
                        launchUpdate { repository.updateRequireBiometricToReveal(it) }
                    }
                )
            }
        }
        item {
            SettingsGroup(title = "App") {
                SettingChipRow(label = "App theme") {
                    AppThemeSetting.entries.forEach { theme ->
                        FilterChip(
                            selected = settings.app.appTheme == theme,
                            onClick = { launchUpdate { repository.updateAppTheme(theme) } },
                            label = { Text(theme.storageValue.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
                SettingSwitchRow(
                    label = "Confirm before delete",
                    checked = settings.app.confirmBeforeDelete,
                    onCheckedChange = {
                        launchUpdate { repository.updateConfirmBeforeDelete(it) }
                    }
                )
                AccentColorEditor(
                    accentHex = settings.app.accentColorHex,
                    onCommit = { hex -> launchUpdate { repository.updateAccentColor(hex) } }
                )
            }
        }
        item {
            SettingsGroup(title = "Reader") {
                SettingChipRow(label = "Mode") {
                    ReaderMode.entries.forEach { mode ->
                        FilterChip(
                            selected = settings.reader.readerMode == mode,
                            onClick = { launchUpdate { repository.updateReaderMode(mode) } },
                            label = { Text(mode.storageValue.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
                SettingChipRow(label = "Reader theme") {
                    ReaderThemeSetting.entries.forEach { theme ->
                        FilterChip(
                            selected = settings.reader.readerTheme == theme,
                            onClick = { launchUpdate { repository.updateReaderTheme(theme) } },
                            label = { Text(theme.storageValue.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
                SettingSwitchRow(
                    label = "Match app theme",
                    checked = settings.reader.matchAppReaderTheme,
                    onCheckedChange = {
                        launchUpdate { repository.updateMatchAppReaderTheme(it) }
                    }
                )
                SettingSwitchRow(
                    label = "Justified text",
                    checked = settings.reader.readerJustify,
                    onCheckedChange = { launchUpdate { repository.updateReaderJustify(it) } }
                )
                SettingSliderRow(
                    label = "Text size",
                    value = settings.reader.readerFontPt.toFloat().coerceIn(FontPtMin, FontPtMax),
                    valueRange = FontPtMin..FontPtMax,
                    steps = (FontPtMax - FontPtMin).toInt() - 1,
                    formatValue = { "${it.roundToInt()} pt" },
                    onValueChangeFinished = { value ->
                        launchUpdate {
                            repository.updateReaderFontPt(value.roundToInt().toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                SettingSliderRow(
                    label = "Line height",
                    value = settings.reader.readerLineHeight.toFloat()
                        .coerceIn(LineHeightMin, LineHeightMax),
                    valueRange = LineHeightMin..LineHeightMax,
                    steps = 19,
                    formatValue = { String.format("%.2f", it) },
                    onValueChangeFinished = { value ->
                        launchUpdate {
                            repository.updateReaderLineHeight(
                                (value * 100).roundToInt() / 100.0
                            )
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                SettingSliderRow(
                    label = "Margin",
                    value = settings.reader.readerMargin.toFloat().coerceIn(MarginMin, MarginMax),
                    valueRange = MarginMin..MarginMax,
                    steps = (MarginMax - MarginMin).toInt() - 1,
                    formatValue = { "${it.roundToInt()} pt" },
                    onValueChangeFinished = { value ->
                        launchUpdate {
                            repository.updateReaderMargin(value.roundToInt().toDouble())
                            repository.updateReaderCustomize(true)
                        }
                    }
                )
                ReaderFontSection(
                    selectedFontId = settings.reader.readerFontId,
                    importedFonts = importedFonts,
                    busy = fontBusy,
                    statusMessage = fontStatus,
                    statusIsError = fontStatusIsError,
                    onSelect = { fontId ->
                        launchUpdate { repository.updateReaderFontId(fontId) }
                    },
                    onImport = {
                        if (!fontBusy) importFontLauncher.launch(FontOpenMimeTypes)
                    },
                    onDelete = { font ->
                        launchUpdate {
                            fontBusy = true
                            fontStatus = null
                            try {
                                customFontRepository.deleteImported(font)
                                fontStatusIsError = false
                                fontStatus = "Removed “${font.name}”."
                            } catch (error: Exception) {
                                fontStatusIsError = true
                                fontStatus = error.message ?: "Could not delete font."
                            } finally {
                                fontBusy = false
                            }
                        }
                    }
                )
            }
        }
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("Backup and reset", style = MaterialTheme.typography.titleMedium)
                    Text(
                        text = "Settings use the same field names and defaults as the cross-platform backup contract.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(onClick = onOpenBackup, modifier = Modifier.weight(1f)) {
                            Text("Backup")
                        }
                        OutlinedButton(
                            onClick = { scope.launch { repository.resetToDefaults() } },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Reset")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ReaderFontSection(
    selectedFontId: String,
    importedFonts: List<CustomFont>,
    busy: Boolean,
    statusMessage: String?,
    statusIsError: Boolean,
    onSelect: (String) -> Unit,
    onImport: () -> Unit,
    onDelete: (CustomFont) -> Unit
) {
    val options = remember(importedFonts) { ReaderFontCatalog.options(importedFonts) }
    val importedBySelectionId = remember(importedFonts) {
        importedFonts.associateBy { it.selectionId }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = "Font", style = MaterialTheme.typography.bodyMedium)
        Text(
            text = "Built-in families plus fonts you import (.ttf / .otf). Selection is stored as " +
                "readerFontID (custom fonts use custom:<fileName>).",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        options.forEach { option ->
            FontOptionRow(
                option = option,
                selected = option.id == selectedFontId,
                enabled = !busy,
                onSelect = { onSelect(option.id) },
                onDelete = if (option.isCustom) {
                    {
                        importedBySelectionId[option.id]?.let(onDelete)
                    }
                } else {
                    null
                }
            )
        }
        OutlinedButton(
            onClick = onImport,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (busy) "Working…" else "Import font")
        }
        if (statusMessage != null) {
            Text(
                text = statusMessage,
                style = MaterialTheme.typography.bodySmall,
                color = if (statusIsError) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
    }
}

@Composable
private fun FontOptionRow(
    option: ReaderFontOption,
    selected: Boolean,
    enabled: Boolean,
    onSelect: () -> Unit,
    onDelete: (() -> Unit)?
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onSelect)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = option.name,
                style = MaterialTheme.typography.bodyMedium
            )
            if (option.isCustom) {
                Text(
                    text = "Imported",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (selected) {
            Icon(
                imageVector = Icons.Outlined.Check,
                contentDescription = "Selected",
                tint = MaterialTheme.colorScheme.primary
            )
        }
        if (onDelete != null) {
            IconButton(onClick = onDelete, enabled = enabled) {
                Icon(
                    imageVector = Icons.Outlined.Delete,
                    contentDescription = "Delete ${option.name}"
                )
            }
        }
    }
}

@Composable
private fun SettingsGroup(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun SettingSwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SettingChipRow(
    label: String,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = label, style = MaterialTheme.typography.bodyMedium)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun SettingSliderRow(
    label: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    steps: Int,
    formatValue: (Float) -> String,
    onValueChangeFinished: (Float) -> Unit
) {
    var sliderValue by remember(value) { mutableStateOf(value) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(text = label, style = MaterialTheme.typography.bodyMedium)
            Text(
                text = formatValue(sliderValue),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Slider(
            value = sliderValue,
            onValueChange = { sliderValue = it },
            onValueChangeFinished = { onValueChangeFinished(sliderValue) },
            valueRange = valueRange,
            steps = steps.coerceAtLeast(0)
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AccentColorEditor(
    accentHex: String,
    onCommit: (String) -> Unit
) {
    var draft by remember { mutableStateOf(accentHex) }
    LaunchedEffect(accentHex) {
        draft = accentHex
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = "Accent color", style = MaterialTheme.typography.bodyMedium)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            AccentPresets.forEach { preset ->
                FilterChip(
                    selected = accentHex.equals(preset, ignoreCase = true),
                    onClick = {
                        draft = preset
                        onCommit(preset)
                    },
                    label = { Text(preset) }
                )
            }
        }
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("Hex") },
            supportingText = { Text("e.g. #990000") }
        )
        OutlinedButton(
            onClick = {
                normalizeAccentHex(draft)?.let { onCommit(it) }
            },
            enabled = normalizeAccentHex(draft) != null
        ) {
            Text("Apply accent")
        }
    }
}

/** Accepts #RGB or #RRGGBB (optional #). Returns canonical #RRGGBB or null. */
private fun normalizeAccentHex(raw: String): String? {
    val trimmed = raw.trim()
    val hex = if (trimmed.startsWith("#")) trimmed.drop(1) else trimmed
    if (hex.length != 3 && hex.length != 6) return null
    if (!hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
    val expanded = if (hex.length == 3) {
        hex.map { "$it$it" }.joinToString("")
    } else {
        hex
    }
    return "#${expanded.uppercase()}"
}

private fun queryDisplayName(context: android.content.Context, uri: Uri): String? {
    val fromResolver = runCatching {
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        }
    }.getOrNull()
    return fromResolver?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment
}
