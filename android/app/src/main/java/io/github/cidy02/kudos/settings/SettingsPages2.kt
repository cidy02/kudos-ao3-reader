package io.github.cidy02.kudos.settings

import android.content.Intent
import android.graphics.Color as AndroidColor
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NoteAdd
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.navigation.NavController
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.KudosApplication
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.backup.PairingCard
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.backup.TombstoneTrustStore
import io.github.cidy02.kudos.backup.TrustedDevice
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.update.AppUpdateState
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.works.WorkImporter
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val EpubOpenMimeTypes = arrayOf(
    "application/epub+zip",
    "application/pdf",
    "text/html",
    "text/plain",
    "application/octet-stream"
)

private val AccentPresets = listOf("#990000", "#0B57D0", "#0F6B46", "#7A3E00", "#5B2C6F")

@Composable
fun SettingsLibraryPage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    SettingsPage(title = "Library") {
        item {
            SettingsSection(
                footnote = "Confirm before deleting asks before a swipe removes a work from your Library. " +
                    "Show zero counts keeps empty stats on work cards; turn it off to hide them."
            ) {
                SubjectFormRow(
                    "Confirm before deleting",
                    trailing = {
                        SubjectToggle(
                            checked = settings.app.confirmBeforeDelete,
                            onCheckedChange = { scope.launch { repository.updateConfirmBeforeDelete(it) } }
                        )
                    }
                )
            }
        }
    }
}

@Composable
fun SettingsImportPage(workImporter: WorkImporter?) {
    // T-353: imports go through the app's one import path (ExternalFileImport ->
    // KudosApp), which confirms each file's detected download date, as iOS's
    // SettingsImportPage does through DownloadDateImportConfirmation.
    val importEpubLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        io.github.cidy02.kudos.works.ExternalFileImport.offer(uris)
    }

    SettingsPage(title = "Import") {
        item {
            Column(Modifier.padding(top = 22.dp)) {
                SettingsPanel {
                    SettingsActionRow(
                        label = "Import Files",
                        icon = Icons.Outlined.NoteAdd,
                        enabled = workImporter != null,
                        onClick = { importEpubLauncher.launch(EpubOpenMimeTypes) }
                    )
                }
                SettingsFootnote(
                    "Import downloaded works, web pages, text files, or zipped chapters into your " +
                        "Library. Kudos prepares supported files for reading, keeps the original, " +
                        "and stores both so you can read offline."
                )
            }
        }
    }
}

@Composable
fun SettingsPreservationPage(
    workAvailabilitySweep: WorkAvailabilitySweep?,
    onOpenAvailabilitySweep: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    var sweepBusy by remember { mutableStateOf(false) }
    var sweepStatus by remember { mutableStateOf<String?>(null) }

    SettingsPage(title = "Preservation") {
        item {
            Column(Modifier.padding(top = 22.dp)) {
                SettingsPanel {
                    SettingsActionRow(
                        label = if (sweepBusy) "Sweeping…" else "Check Availability…",
                        icon = Icons.Outlined.Sync,
                        enabled = !sweepBusy,
                        contentDescription = "Check library for deleted/hidden works on AO3.",
                        onClick = {
                            if (workAvailabilitySweep == null) {
                                onOpenAvailabilitySweep()
                            } else if (!sweepBusy) {
                                sweepBusy = true
                                sweepStatus = null
                                scope.launch {
                                    try {
                                        val summary = workAvailabilitySweep.sweep()
                                        sweepStatus = "Sweep complete: ${summary.checked} checked, ${summary.nowUnavailable} unavailable."
                                    } catch (e: Exception) {
                                        sweepStatus = "Sweep failed: ${e.message}"
                                    } finally {
                                        sweepBusy = false
                                    }
                                }
                            }
                        }
                    )
                    SubjectRowSeparator()
                    SubjectFormRow(
                        "Unavailable Works",
                        showsDisclosure = true,
                        onClick = onOpenAvailabilitySweep
                    )
                }
                if (sweepStatus != null) {
                    Text(
                        text = sweepStatus!!,
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                    )
                }
                SettingsFootnote(
                    "Checks which saved works are still on AO3 and marks missing ones as the " +
                        "last copy you have. Kudos checks one work at a time and waits between " +
                        "checks, so start it when you have time."
                )
            }
        }
    }
}

@Composable
fun SettingsListeningPage() {
    SettingsPage(title = "Listening") {
        item {
            SettingsSection(
                footnote = "Voice, speed, and the Kokoro voice pack are chosen in the reader. " +
                    "This page does not change them yet."
            ) {
                SubjectFormRow("Start Read Aloud from the reader's More menu.")
            }
        }
    }
}

@Composable
fun SettingsAccountPage(authRepository: AO3AuthRepository?, onLogin: () -> Unit) {
    val scope = rememberCoroutineScope()
    val authState by (authRepository?.state ?: flowOf(AO3AuthState.SignedOut))
        .collectAsState(initial = AO3AuthState.SignedOut)
    SettingsPage(title = "AO3 Account") {
        item {
            SettingsSection(
                footnote = "Sign in to use your AO3 bookmarks, history, subscriptions, kudos, " +
                    "comments, and restricted works in Kudos."
            ) {
                when (authState) {
                    is AO3AuthState.SignedIn -> {
                        SubjectFormRow("Signed In", value = (authState as AO3AuthState.SignedIn).username)
                        SubjectRowSeparator()
                        SettingsActionRow(
                            label = "Log Out",
                            icon = Icons.AutoMirrored.Outlined.Logout,
                            onClick = { scope.launch { authRepository?.logout() } }
                        )
                    }
                    AO3AuthState.Restoring, AO3AuthState.SigningIn -> {
                        SubjectFormRow("Checking AO3 session…")
                    }
                    else -> {
                        SettingsActionRow(
                            label = "Log In to AO3…",
                            icon = Icons.Outlined.Info,
                            onClick = onLogin
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsPrivacySettingsPage(
    repository: SettingsRepository,
    settings: KudosSettings,
    navController: NavController
) {
    val scope = rememberCoroutineScope()
    val hide = settings.privacy.hideMatureContent
    val footnote = when {
        !hide -> "You see Mature and Explicit works normally."
        settings.privacy.matureContentMode == MatureContentMode.Hide ->
            "Kudos hides Mature and Explicit works from your Library, History, and " +
                "Favorites until you reveal them."
        else ->
            "Kudos blurs Mature and Explicit works in your Library, History, and " +
                "Favorites until you tap to reveal them."
    }
    SettingsPage(title = "Privacy") {
        item {
            SettingsSection(footnote = footnote) {
                SubjectFormRow(
                    "Hide mature content",
                    trailing = {
                        SubjectToggle(
                            checked = hide,
                            onCheckedChange = { scope.launch { repository.updateHideMatureContent(it) } }
                        )
                    }
                )
                if (hide) {
                    SubjectRowSeparator()
                    SubjectSegmentedControl(
                        options = MatureContentMode.entries,
                        selected = settings.privacy.matureContentMode,
                        onSelect = { mode -> scope.launch { repository.updateMatureContentMode(mode) } },
                        title = { mode -> if (mode == MatureContentMode.Hide) "Hide" else "Blur" },
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp)
                    )
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label = "Require biometric to reveal",
                        trailing = {
                            SubjectToggle(
                                checked = settings.privacy.requireBiometricToReveal,
                                onCheckedChange = { scope.launch { repository.updateRequireBiometricToReveal(it) } },
                                contentDescription = "Require biometric to reveal"
                            )
                        }
                    )
                }
                SubjectRowSeparator()
                SettingsLinkRow(
                    label = "Privacy & Local Data",
                    icon = Icons.Outlined.PanTool,
                    onClick = { navController.navigate("privacy") }
                )
            }
        }
    }
}

@Composable
fun SettingsAboutPage(
    onOpenAbout: () -> Unit,
    onReportBug: () -> Unit,
    navController: NavController,
    appUpdateRepository: AppUpdateRepository?
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val updateState by (appUpdateRepository?.state ?: flowOf(AppUpdateState.Idle))
        .collectAsState(initial = AppUpdateState.Idle)

    SettingsPage(title = "About") {
        item {
            SettingsSection(
                footnote = "These settings only change Kudos. Change anything AO3 stores about your " +
                    "account in AO3 Preferences. Your accent colour from Appearance also colours " +
                    "this tab."
            ) {
                SubjectFormRow("Version", value = BuildConfig.VERSION_NAME)
                SubjectRowSeparator()
                SettingsLinkRow(
                    label = "Privacy and local data",
                    icon = Icons.Outlined.PanTool,
                    onClick = { navController.navigate("privacy") }
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "About Kudos",
                    icon = Icons.Outlined.Info,
                    onClick = onOpenAbout
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Report a Bug",
                    icon = Icons.Outlined.BugReport,
                    onClick = onReportBug
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Source on GitHub",
                    icon = Icons.Outlined.Code,
                    onClick = {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader"))
                        runCatching { context.startActivity(intent) }
                    }
                )
            }
        }
        if (appUpdateRepository != null) {
            item {
                Column(Modifier.padding(top = 22.dp)) {
                    SectionRuleHeader("Software Update")
                    SettingsPanel(Modifier.padding(top = 10.dp)) {
                        when (val state = updateState) {
                            AppUpdateState.Idle, AppUpdateState.UpToDate -> {
                                SubjectFormRow(
                                    "Status",
                                    value = "Up to date",
                                    onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } }
                                )
                                SubjectRowSeparator()
                                SubjectFormRow(
                                    "Check Now",
                                    onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } }
                                )
                            }
                            AppUpdateState.Checking -> SubjectFormRow("Checking GitHub for updates…")
                            is AppUpdateState.UpdateAvailable ->
                                SubjectFormRow("Version ${state.match.version} is available")
                            is AppUpdateState.Downloading ->
                                SubjectFormRow("Downloading version ${state.match.version}…")
                            is AppUpdateState.ReadyToInstall -> {
                                SubjectFormRow(
                                    "Install Update",
                                    onClick = {
                                        runCatching {
                                            context.startActivity(appUpdateRepository.installIntentFor(state.apkPath))
                                        }
                                    }
                                )
                            }
                            is AppUpdateState.Failed -> {
                                SubjectFormRow("Status", value = state.message)
                                SubjectRowSeparator()
                                SubjectFormRow(
                                    "Try Again",
                                    onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } }
                                )
                            }
                        }
                    }
                    Text(
                        text = "Kudos Android is Alpha until it reaches iOS feature parity — expect rougher edges and more frequent updates.",
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun SettingsBackupPageWrapper(
    onOpenBackup: () -> Unit,
    navController: NavController,
    repository: SettingsRepository,
    settings: KudosSettings
) {
    val scope = rememberCoroutineScope()
    var showResetConfirm by remember { mutableStateOf(false) }
    SettingsPage(title = "Backup") {
        item {
            SettingsSection(
                footnote = "Your backup file includes your Library, Reading Queues, downloaded copies, " +
                    "User Tags, saved links, custom fonts, imported original files, and app " +
                    "settings. Importing adds anything you don't have without removing what is " +
                    "already here. Your AO3 sign-in and password are never included."
            ) {
                SettingsActionRow(
                    label = "Export Backup…",
                    icon = Icons.Outlined.FileUpload,
                    onClick = onOpenBackup
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Import Backup…",
                    icon = Icons.Outlined.FileDownload,
                    onClick = onOpenBackup
                )
            }
        }
        item {
            Column(Modifier.padding(top = 22.dp)) {
                SettingsPanel {
                    SettingsActionRow(
                        label = "Reset settings to defaults",
                        onClick = { showResetConfirm = true }
                    )
                }
            }
        }
    }
    DestructiveConfirmation(
        show = showResetConfirm,
        title = "Reset settings to defaults?",
        text = "This clears reader, theme, privacy, and other app preferences back to their defaults. Your Library, downloads, and AO3 session are not affected.",
        confirmText = "Reset",
        confirmBeforeDelete = true,
        onConfirm = {
            showResetConfirm = false
            scope.launch { repository.resetToDefaults() }
        },
        onDismissRequest = { showResetConfirm = false }
    )
}

@Composable
fun SettingsReadingQueuesPageWrapper(
    onOpenQueues: () -> Unit,
    navController: NavController,
    repository: SettingsRepository,
    settings: KudosSettings
) {
    val scope = rememberCoroutineScope()
    val enabled = settings.app.autoPreserveSmallSeriesOnSaveForLater
    val limit = settings.app.autoPreserveSeriesWorkThreshold.coerceIn(2, 25)
    SettingsPage(title = "Reading Queues") {
        item {
            SettingsSection(
                footnote = "Saved for Later keeps a downloaded copy. When you save a series, Kudos " +
                    "asks before downloading each work unless this option is on and the series " +
                    "is within your limit."
            ) {
                SettingsLinkRow(
                    label = "Queue Storage",
                    icon = Icons.Outlined.Storage,
                    onClick = onOpenQueues
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    "Auto-preserve small series",
                    trailing = {
                        SubjectToggle(
                            checked = enabled,
                            onCheckedChange = { scope.launch { repository.updateAutoPreserveSmallSeries(it) } }
                        )
                    }
                )
                SubjectRowSeparator()
                SubjectFormRow(
                    label = "Series limit: $limit",
                    trailing = {
                        SeriesLimitStepper(
                            value = limit,
                            enabled = enabled,
                            onChange = { scope.launch { repository.updateAutoPreserveSeriesThreshold(it) } }
                        )
                    }
                )
            }
        }
    }
}

@Composable
fun SettingsFontPage(
    repository: SettingsRepository,
    settings: KudosSettings,
    customFontRepository: CustomFontRepository
) {
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val importedFonts by customFontRepository.observeImported().collectAsState(initial = emptyList())
    val options = remember(importedFonts) {
        io.github.cidy02.kudos.core.model.ReaderFontCatalog.options(importedFonts)
    }
    var fontBusy by remember { mutableStateOf(false) }
    var fontStatus by remember { mutableStateOf<String?>(null) }
    var fontStatusIsError by remember { mutableStateOf(false) }

    val importFontLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            fontBusy = true
            fontStatus = null
            try {
                val successes = mutableListOf<String>()
                val failures = mutableListOf<String>()
                for (uri in uris) {
                    val displayName = withContext(Dispatchers.IO) {
                        io.github.cidy02.kudos.works.ExternalFileImport.displayNameFor(context, uri)
                    }
                    val label = displayName?.substringAfterLast('/')?.substringAfterLast('\\')?.ifBlank { null } ?: "file"
                    if (!CustomFontRepository.isSupportedFontFileName(displayName)) {
                        failures += "$label: Only .ttf and .otf font files are supported."
                        continue
                    }
                    try {
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
                            onSuccess = { font -> successes += "“${font.name}”" },
                            onFailure = { error -> failures += "$label: ${error.message ?: "Could not import font."}" }
                        )
                    } catch (error: Exception) {
                        failures += "$label: ${error.message ?: "Could not import font."}"
                    }
                }
                fontStatusIsError = failures.isNotEmpty() && successes.isEmpty()
                fontStatus = if (successes.isNotEmpty()) {
                    "Imported ${successes.size} fonts"
                } else if (failures.isNotEmpty()) {
                    failures.joinToString("\n")
                } else {
                    "Nothing imported."
                }
            } catch (error: Exception) {
                fontStatusIsError = true
                fontStatus = error.message ?: "Could not import font."
            } finally {
                fontBusy = false
            }
        }
    }

    SettingsPage(title = "Font") {
        item {
            Column(Modifier.padding(top = 22.dp)) {
                SettingsGroupLabel("Font")
                SettingsPanel {
                    options.forEachIndexed { index, option ->
                        if (index > 0) SubjectRowSeparator()
                        SubjectFormRow(
                            label = option.name,
                            onClick = { scope.launch { repository.updateReaderFontId(option.id) } },
                            trailing = {
                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    if (settings.reader.readerFontId == option.id) {
                                        Icon(
                                            imageVector = Icons.Filled.Check,
                                            contentDescription = "Selected",
                                            tint = tokens.accent,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                    if (option.isCustom) {
                                        IconButton(
                                            onClick = {
                                                scope.launch {
                                                    val fontToDelete = importedFonts.find { it.selectionId == option.id }
                                                    if (fontToDelete != null) {
                                                        fontBusy = true
                                                        fontStatus = null
                                                        try {
                                                            customFontRepository.deleteImported(fontToDelete)
                                                            fontStatusIsError = false
                                                            fontStatus = "Removed “${fontToDelete.name}”."
                                                        } catch (error: Exception) {
                                                            fontStatusIsError = true
                                                            fontStatus = error.message ?: "Could not delete font."
                                                        } finally {
                                                            fontBusy = false
                                                        }
                                                    }
                                                }
                                            },
                                            enabled = !fontBusy
                                        ) {
                                            Icon(
                                                imageVector = Icons.Outlined.Delete,
                                                contentDescription = "Delete ${option.name}",
                                                tint = tokens.secondaryInk
                                            )
                                        }
                                    }
                                }
                            }
                        )
                    }
                    SubjectRowSeparator()
                    SettingsActionRow(
                        label = if (fontBusy) "Working…" else "Add Font…",
                        icon = Icons.Outlined.Add,
                        enabled = !fontBusy,
                        contentDescription = "Import font (.ttf / .otf)",
                        onClick = {
                            importFontLauncher.launch(
                                arrayOf(
                                    "font/ttf",
                                    "font/otf",
                                    "application/x-font-ttf",
                                    "application/x-font-otf",
                                    "application/font-sfnt",
                                    "application/octet-stream"
                                )
                            )
                        }
                    )
                }
                if (fontStatus != null) {
                    Text(
                        text = fontStatus!!,
                        color = if (fontStatusIsError) MaterialTheme.colorScheme.error else tokens.secondaryInk,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                    )
                } else {
                    SettingsFootnote("Built-in families plus fonts you import (.ttf / .otf).")
                }
            }
        }
    }
}

@Composable
fun SettingsFolderSyncPage(repository: SettingsRepository, settings: KudosSettings) {
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val container = (context.applicationContext as? KudosApplication)?.container
    val syncRepository = container?.syncRepository
    var lastSyncFolded by remember { mutableStateOf(0) }
    var syncBusy by remember { mutableStateOf(false) }
    var showPairing by remember { mutableStateOf(false) }
    var trustedDevices by remember { mutableStateOf<List<TrustedDevice>>(emptyList()) }
    val deviceKey = remember(context) {
        runCatching {
            TombstoneSigning.initialize(context)
            TombstoneSigning.publicKeyHex()
        }.getOrNull()
    }
    LaunchedEffect(Unit) {
        trustedDevices = runCatching { TombstoneTrustStore(repository).trustedDevices() }.getOrDefault(emptyList())
    }

    val syncFolderLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            scope.launch { syncRepository?.connect(uri) }
        }
    }
    val connected = settings.sync.isEnabled && settings.sync.folderUri != null
    val folderLabel = settings.sync.folderUri?.let(::syncFolderName)

    SettingsPage(title = "Sync Folder") {
        item {
            SettingsSection(
                label = "Deletion signing",
                footnote = "Kudos checks that deletions came from one of your devices. Devices using the " +
                    "same Apple account are trusted automatically; for a different account, scan " +
                    "its QR code or share its pairing code. A backup file can never mark a device " +
                    "as trusted."
            ) {
                Column(Modifier.padding(horizontal = 13.dp, vertical = 12.dp)) {
                    Text("This device", color = tokens.primaryInk, fontSize = 16.sp)
                    Text(
                        text = deviceKey ?: "Unavailable",
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
                SubjectRowSeparator()
                if (trustedDevices.isEmpty()) {
                    Text(
                        text = "No other devices paired yet.",
                        color = tokens.secondaryInk,
                        fontSize = 15.sp,
                        modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp)
                    )
                } else {
                    trustedDevices.forEachIndexed { index, device ->
                        if (index > 0) SubjectRowSeparator()
                        SubjectFormRow(
                            label = device.label.ifBlank { "Paired device" },
                            value = device.publicKeyHex.take(8)
                        )
                    }
                }
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Pair a Device",
                    enabled = container != null,
                    onClick = { showPairing = true }
                )
            }
        }
        item {
            Column(Modifier.padding(top = 22.dp)) {
                SettingsPanel {
                    SubjectFormRow(
                        label = "Enable folder sync",
                        trailing = {
                            SubjectToggle(
                                checked = settings.sync.isEnabled,
                                onCheckedChange = { enabled ->
                                    scope.launch {
                                        if (enabled) {
                                            if (settings.sync.folderUri != null) {
                                                syncRepository?.connect(Uri.parse(settings.sync.folderUri))
                                            } else {
                                                syncFolderLauncher.launch(null)
                                            }
                                        } else {
                                            syncRepository?.disconnect()
                                        }
                                    }
                                }
                            )
                        }
                    )
                    SubjectRowSeparator()
                    SettingsActionRow(
                        label = if (settings.sync.folderUri == null) "Choose Sync Folder" else "Change Folder",
                        contentDescription = if (settings.sync.folderUri == null) {
                            "Select sync folder"
                        } else {
                            "Change sync folder"
                        },
                        onClick = { syncFolderLauncher.launch(null) }
                    )
                    if (folderLabel != null) {
                        SubjectRowSeparator()
                        SubjectFormRow("Folder", value = folderLabel)
                    }
                    if (connected) {
                        SubjectRowSeparator()
                        SettingsActionRow(
                            label = if (syncBusy) "Working…" else "Sync Now",
                            icon = Icons.Outlined.Sync,
                            enabled = !syncBusy,
                            onClick = {
                                syncBusy = true
                                scope.launch {
                                    val result = syncRepository?.runSync()
                                    lastSyncFolded = (result as? io.github.cidy02.kudos.backup.SyncResult.Success)?.foldedConflicts ?: 0
                                    syncBusy = false
                                }
                            }
                        )
                    }
                    settings.sync.lastSyncAt?.let { instant ->
                        SubjectRowSeparator()
                        SubjectFormRow("Last Synced", value = formatSyncInstant(instant))
                    }
                }
                if (connected && lastSyncFolded > 0) {
                    Text(
                        text = if (lastSyncFolded == 1) {
                            "Merged 1 conflicting copy from another device."
                        } else {
                            "Merged $lastSyncFolded conflicting copies from other devices."
                        },
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                    )
                }
                SettingsFootnote(
                    "Kudos stores your library data, including reading history, in the folder you " +
                        "choose using the same kind of file as a backup. If the folder is in iCloud " +
                        "Drive, Apple shares changes through your personal iCloud account; changes may " +
                        "not appear immediately, and Kudos still works offline. Turning off Auto Sync " +
                        "stops automatic updates, but Sync Now still works."
                )
            }
        }
    }

    if (showPairing && container != null) {
        Dialog(onDismissRequest = { showPairing = false }) {
            PairingCard(
                settingsRepository = container.settingsRepository,
                database = container.database,
                workRepository = container.workRepository
            )
        }
    }
}

@Composable
private fun SeriesLimitStepper(value: Int, enabled: Boolean, onChange: (Int) -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier
            .alpha(if (enabled) 1f else 0.4f)
            .clip(RoundedCornerShape(8.dp))
            .background(tokens.glassFill(0.16))
    ) {
        StepButton(label = "−", enabled = enabled && value > 2) { onChange(value - 1) }
        Box(
            Modifier
                .padding(vertical = 6.dp)
                .size(width = 0.5.dp, height = 18.dp)
                .background(tokens.glassStroke(0.25))
        )
        StepButton(label = "+", enabled = enabled && value < 25) { onChange(value + 1) }
    }
}

@Composable
private fun StepButton(label: String, enabled: Boolean, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Box(
        Modifier
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            color = if (enabled) tokens.primaryInk else tokens.tertiaryInk,
            fontSize = 18.sp
        )
    }
}

@Composable
fun AccentColorWell(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(28.dp)) {
        val stroke = 2.5.dp.toPx()
        val radius = size.minDimension / 2f
        drawCircle(
            brush = Brush.sweepGradient(
                listOf(Color.Red, Color.Yellow, Color.Green, Color.Cyan, Color.Blue, Color.Magenta, Color.Red)
            ),
            radius = radius - stroke / 2f,
            style = Stroke(width = stroke)
        )
        drawCircle(color = color, radius = radius - stroke - 1.5.dp.toPx())
    }
}

@Composable
fun AccentCustomizeBlock(accentHex: String, onCommit: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    var draft by remember { mutableStateOf(accentHex) }
    LaunchedEffect(accentHex) { draft = accentHex }
    Column(
        modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            AccentPresets.forEach { preset ->
                val selected = accentHex.equals(preset, ignoreCase = true)
                Box(
                    Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(accentColorOrFallback(preset))
                        .border(
                            width = if (selected) 2.dp else 0.5.dp,
                            color = if (selected) tokens.primaryInk else tokens.glassStroke(0.4),
                            shape = CircleShape
                        )
                        .clickable {
                            draft = preset
                            onCommit(preset)
                        }
                        .semantics { contentDescription = preset }
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
            onClick = { normalizeAccentHex(draft)?.let(onCommit) },
            enabled = normalizeAccentHex(draft) != null
        ) {
            Text("Apply accent")
        }
    }
}

internal fun accentColorOrFallback(hex: String): Color {
    val parsed = runCatching { AndroidColor.parseColor(if (hex.startsWith("#")) hex else "#$hex") }.getOrNull()
        ?: AndroidColor.parseColor("#990000")
    return Color(parsed)
}

enum class ThemeChipOption(val label: String, val setting: AppThemeSetting) {
    Light("Light", AppThemeSetting.Light),
    Sepia("Sepia", AppThemeSetting.Sepia),
    Dark("Dark", AppThemeSetting.Dark),
    Oled("OLED", AppThemeSetting.Oled),
    System("System", AppThemeSetting.System)
}

private fun normalizeAccentHex(raw: String): String? {
    val trimmed = raw.trim()
    val hex = if (trimmed.startsWith("#")) trimmed.drop(1) else trimmed
    if (hex.length != 3 && hex.length != 6) return null
    if (!hex.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
    val expanded = if (hex.length == 3) hex.map { "$it$it" }.joinToString("") else hex
    return "#${expanded.uppercase()}"
}

private fun syncFolderName(uri: String): String {
    val last = Uri.parse(uri).lastPathSegment?.substringAfter(':')?.substringAfterLast('/')
    return last?.takeIf { it.isNotBlank() } ?: "Selected folder"
}

private fun formatSyncInstant(instant: java.time.Instant): String {
    val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a")
    return formatter.format(instant.atZone(ZoneId.systemDefault()))
}
