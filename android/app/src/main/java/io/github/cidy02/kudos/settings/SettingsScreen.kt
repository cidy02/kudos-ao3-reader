package io.github.cidy02.kudos.settings

import android.content.Intent
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
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
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
import io.github.cidy02.kudos.support.openBugReport
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.update.AppUpdateState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
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

/**
 * Settings section map aligned with iOS Form groups (portable prefs only):
 * AO3 Account · Theme · Appearance/Reading · Library · Backup · Sync N/A · Privacy · Help.
 */
@Composable
fun SettingsScreen(
    repository: SettingsRepository,
    customFontRepository: CustomFontRepository,
    onOpenBackup: () -> Unit,
    authRepository: AO3AuthRepository? = null,
    onLogin: () -> Unit = {},
    onOpenAbout: () -> Unit = {},
    appUpdateRepository: AppUpdateRepository? = null
) {
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val importedFonts by customFontRepository.observeImported()
        .collectAsState(initial = emptyList())
    val authFlow = remember(authRepository) {
        authRepository?.state ?: flowOf(AO3AuthState.SignedOut)
    }
    val authState by authFlow.collectAsState(initial = AO3AuthState.SignedOut)
    val updateFlow = remember(appUpdateRepository) {
        appUpdateRepository?.state ?: flowOf(AppUpdateState.Idle)
    }
    val updateState by updateFlow.collectAsState(initial = AppUpdateState.Idle)
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { }
    LaunchedEffect(updateState) {
        if (updateState is AppUpdateState.ReadyToInstall &&
            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU
        ) {
            notificationPermissionLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var fontStatus by remember { mutableStateOf<String?>(null) }
    var fontStatusIsError by remember { mutableStateOf(false) }
    var fontBusy by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }

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
        // ── AO3 Account ────────────────────────────────────────────────
        item {
            SettingsGroup(title = "AO3 Account") {
                when (val auth = authState) {
                    is AO3AuthState.SignedIn -> {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.CheckCircle,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Text(
                                text = "Signed In",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = auth.username,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    scope.launch { authRepository?.logout() }
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Outlined.Logout,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error
                            )
                            Text(
                                text = "Log Out",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.error
                            )
                        }
                    }
                    AO3AuthState.Restoring, AO3AuthState.SigningIn -> {
                        Text(
                            text = "Checking AO3 session…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    is AO3AuthState.Expired, is AO3AuthState.Error, AO3AuthState.SignedOut -> {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable(onClick = onLogin)
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Person,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Log In to AO3…",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                val errorMessage = when (auth) {
                                    is AO3AuthState.Expired -> auth.message
                                    is AO3AuthState.Error -> auth.message
                                    else -> null
                                }
                                if (errorMessage != null) {
                                    Text(
                                        text = errorMessage,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    }
                }
            }
            SettingsFooter(
                "A login enables bookmarks, history, subscriptions, kudos, comments, " +
                    "and restricted works."
            )
        }

        // ── Theme ──────────────────────────────────────────────────────
        item {
            SettingsGroup(title = "Theme") {
                SettingChipRow(label = "App theme") {
                    // Light / Sepia / Dark / OLED / System. OLED maps to Dark
                    // storage (AppThemeSetting has no distinct OLED value yet).
                    ThemeChipOption.entries.forEach { option ->
                        FilterChip(
                            selected = isThemeChipSelected(settings.app.appTheme, option),
                            onClick = {
                                launchUpdate { repository.updateAppTheme(option.setting) }
                            },
                            label = { Text(option.label) }
                        )
                    }
                }
                SettingSwitchRow(
                    label = "Match App & Reader Theme",
                    checked = settings.reader.matchAppReaderTheme,
                    onCheckedChange = {
                        launchUpdate { repository.updateMatchAppReaderTheme(it) }
                    }
                )
                AccentColorEditor(
                    accentHex = settings.app.accentColorHex,
                    onCommit = { hex -> launchUpdate { repository.updateAccentColor(hex) } },
                    onReset = {
                        launchUpdate { repository.updateAccentColor("#990000") }
                    }
                )
            }
            SettingsFooter(
                "Light, Sepia, Dark, or System across the app. Dark is used for " +
                    "OLED-style dark chrome on Android. Sepia keeps its warm tint."
            )
        }

        // ── Appearance / Reading ───────────────────────────────────────
        item {
            SettingsGroup(title = "Appearance") {
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
                    label = "Justified text",
                    checked = settings.reader.readerJustify,
                    onCheckedChange = { launchUpdate { repository.updateReaderJustify(it) } }
                )
            }
        }
        item {
            SettingsGroup(title = "Text Size") {
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
            }
        }
        item {
            SettingsGroup(title = "Reading") {
                SettingChipRow(label = "Mode") {
                    ReaderMode.entries.forEach { mode ->
                        FilterChip(
                            selected = settings.reader.readerMode == mode,
                            onClick = { launchUpdate { repository.updateReaderMode(mode) } },
                            label = {
                                Text(
                                    when (mode) {
                                        ReaderMode.Scroll -> "Scrolled"
                                        ReaderMode.Paged -> "Paged"
                                    }
                                )
                            }
                        )
                    }
                }
            }
            SettingsFooter("Choose how pages turn while reading.")
        }
        item {
            SettingsGroup(title = "Font") {
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

        // ── Library ────────────────────────────────────────────────────
        item {
            SettingsGroup(title = "Library") {
                SettingSwitchRow(
                    label = "Confirm before deleting",
                    checked = settings.app.confirmBeforeDelete,
                    onCheckedChange = {
                        launchUpdate { repository.updateConfirmBeforeDelete(it) }
                    }
                )
            }
            SettingsFooter("Ask before removing a work from your Library.")
        }

        // ── Backup ─────────────────────────────────────────────────────
        item {
            SettingsGroup(title = "Backup") {
                TextButton(
                    onClick = onOpenBackup,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Export / Import Backup…")
                }
                OutlinedButton(
                    onClick = { showResetConfirm = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Reset settings to defaults")
                }
            }
            SettingsFooter(
                "Backups include library records, queues, EPUBs, tags, fonts, and app " +
                    "settings. AO3 sessions and passwords are never included."
            )
        }

        // ── Library Sync Folder (iOS iCloud — not on Android) ──────────
        item {
            SettingsGroup(title = "Library Sync Folder") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.CloudOff,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Not available on Android",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        Text(
                            text = "iOS uses an iCloud Documents folder for multi-device " +
                                "library sync. Android will use a folder picker later.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        // ── Privacy ────────────────────────────────────────────────────
        item {
            SettingsGroup(title = "Privacy") {
                SettingSwitchRow(
                    label = "Hide mature content",
                    checked = settings.privacy.hideMatureContent,
                    onCheckedChange = { launchUpdate { repository.updateHideMatureContent(it) } }
                )
                SettingChipRow(label = "When hidden") {
                    MatureContentMode.entries.forEach { mode ->
                        FilterChip(
                            selected = settings.privacy.matureContentMode == mode,
                            onClick = {
                                launchUpdate { repository.updateMatureContentMode(mode) }
                            },
                            label = {
                                Text(
                                    when (mode) {
                                        MatureContentMode.Obscure -> "Blur"
                                        MatureContentMode.Hide -> "Hide"
                                    }
                                )
                            }
                        )
                    }
                }
                SettingSwitchRow(
                    label = "Require biometric to reveal",
                    checked = settings.privacy.requireBiometricToReveal,
                    onCheckedChange = {
                        launchUpdate { repository.updateRequireBiometricToReveal(it) }
                    }
                )
            }
            SettingsFooter(
                "Mature and Explicit works can be blurred or hidden in Library, History, " +
                    "and Favorites until you reveal them."
            )
        }

        // ── Software Update ────────────────────────────────────────────
        if (appUpdateRepository != null) {
            item {
                SettingsGroup(title = "Software Update") {
                    UpdateSection(
                        state = updateState,
                        onCheckNow = { launchUpdate { appUpdateRepository.checkNow(autoDownload = true) } },
                        onInstall = { apkPath ->
                            runCatching {
                                context.startActivity(appUpdateRepository.installIntentFor(apkPath))
                            }
                        }
                    )
                }
            }
        }

        // ── Help & Project ─────────────────────────────────────────────
        item {
            SettingsGroup(title = "Help & Project") {
                SettingsLinkRow(
                    label = "About Kudos",
                    icon = Icons.Outlined.Info,
                    onClick = onOpenAbout
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsLinkRow(
                    label = "Report a Bug",
                    icon = Icons.Outlined.BugReport,
                    onClick = { openBugReport(context) }
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                SettingsLinkRow(
                    label = "Source on GitHub",
                    icon = Icons.Outlined.Code,
                    onClick = {
                        val intent = Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://github.com/cidy02/kudos-ao3-reader")
                        )
                        runCatching { context.startActivity(intent) }
                    }
                )
            }
        }
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text("Reset settings to defaults?") },
            text = {
                Text(
                    "This clears reader, theme, privacy, and other app preferences back to " +
                        "their defaults. Your Library, downloads, and AO3 session are not affected."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showResetConfirm = false
                        scope.launch { repository.resetToDefaults() }
                    }
                ) {
                    Text("Reset")
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

/** Theme chips shown in Settings. OLED maps to [AppThemeSetting.Dark]. */
private enum class ThemeChipOption(val label: String, val setting: AppThemeSetting) {
    Light("Light", AppThemeSetting.Light),
    Sepia("Sepia", AppThemeSetting.Sepia),
    Dark("Dark", AppThemeSetting.Dark),
    Oled("OLED", AppThemeSetting.Dark),
    System("System", AppThemeSetting.System)
}

/**
 * Dark and OLED both store [AppThemeSetting.Dark]. Prefer highlighting Dark so
 * only one chip looks selected; OLED remains a one-tap alias for Dark.
 */
private fun isThemeChipSelected(current: AppThemeSetting, option: ThemeChipOption): Boolean {
    return when (option) {
        ThemeChipOption.Oled -> false
        else -> current == option.setting
    }
}

@Composable
private fun UpdateSection(
    state: AppUpdateState,
    onCheckNow: () -> Unit,
    onInstall: (java.nio.file.Path) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "Kudos Android is Alpha until it reaches iOS feature parity — " +
                "expect rougher edges and more frequent updates.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        when (state) {
            AppUpdateState.Idle -> {
                Row(
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Up to date", style = MaterialTheme.typography.bodyMedium)
                    OutlinedButton(onClick = onCheckNow) { Text("Check Now") }
                }
            }
            AppUpdateState.Checking -> {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Checking GitHub for updates…", style = MaterialTheme.typography.bodyMedium)
                }
            }
            AppUpdateState.UpToDate -> {
                Row(
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Up to date", style = MaterialTheme.typography.bodyMedium)
                    OutlinedButton(onClick = onCheckNow) { Text("Check Now") }
                }
            }
            is AppUpdateState.UpdateAvailable -> {
                Text(
                    "Version ${state.match.version} is available.",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            is AppUpdateState.Downloading -> {
                Text(
                    "Downloading version ${state.match.version}…",
                    style = MaterialTheme.typography.bodyMedium
                )
                LinearProgressIndicator(
                    progress = { state.progress },
                    modifier = Modifier.fillMaxWidth()
                )
            }
            is AppUpdateState.ReadyToInstall -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "Version ${state.match.version} is ready to install.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Button(onClick = { onInstall(state.apkPath) }) { Text("Install Update") }
                }
            }
            is AppUpdateState.Failed -> {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                    OutlinedButton(onClick = onCheckNow) { Text("Try Again") }
                }
            }
        }
    }
}

@Composable
private fun SettingsFooter(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 6.dp, start = 4.dp, end = 4.dp)
    )
}

@Composable
private fun SettingsLinkRow(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.primary
        )
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
        Text(
            text = "Built-in families plus fonts you import (.ttf / .otf).",
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
    onCommit: (String) -> Unit,
    onReset: () -> Unit
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
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(
                onClick = {
                    normalizeAccentHex(draft)?.let { onCommit(it) }
                },
                enabled = normalizeAccentHex(draft) != null
            ) {
                Text("Apply accent")
            }
            TextButton(onClick = onReset) {
                Text("Reset to AO3 Red")
            }
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
