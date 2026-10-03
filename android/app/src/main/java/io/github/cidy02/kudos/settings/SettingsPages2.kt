package io.github.cidy02.kudos.settings

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material.icons.outlined.Delete
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
import androidx.navigation.NavController
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.update.AppUpdateState
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.network.ao3.AO3Error
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

@Composable
fun SettingsLibraryPage(
    repository: SettingsRepository,
    settings: KudosSettings
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Library"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Library", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Confirm before deleting", trailing = {
                        SubjectToggle(checked = settings.app.confirmBeforeDelete, onCheckedChange = { scope.launch { repository.updateConfirmBeforeDelete(it) } })
                    })
                }
                Text("Ask before removing a work from your Library. Imported EPUBs appear as saved works without an AO3 link.", style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
            }
        }
    }
}

@Composable
fun SettingsImportPage(
    workImporter: WorkImporter?
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Import"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current

    var epubBusy by remember { mutableStateOf(false) }
    var epubStatus by remember { mutableStateOf<String?>(null) }
    var epubStatusIsError by remember { mutableStateOf(false) }

    val importEpubLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments()
    ) { uris: List<Uri> ->
        if (uris.isEmpty() || workImporter == null) return@rememberLauncherForActivityResult
        scope.launch {
            epubBusy = true
            epubStatus = null
            try {
                val successes = mutableListOf<String>()
                val failures = mutableListOf<String>()
                for (uri in uris) {
                    val displayName = withContext(Dispatchers.IO) {
                        io.github.cidy02.kudos.works.ExternalFileImport.displayNameFor(context, uri)
                    }
                    val label = displayName?.substringAfterLast('/')?.substringAfterLast('\\')?.ifBlank { null } ?: "file"
                    try {
                        val bytes = withContext(Dispatchers.IO) {
                            context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Could not read the selected file.")
                        }
                        when (val result = workImporter.importLocalEpub(displayName, bytes)) {
                            is WorkImportResult.Success -> successes += "“${result.work.title}”"
                            is WorkImportResult.Failure -> {
                                val message = when (val err = result.error) {
                                    is AO3Error.Validation -> err.message
                                    else -> err.toString()
                                }
                                failures += "$label: $message"
                            }
                        }
                    } catch (e: Exception) {
                        failures += "$label: ${e.message ?: "Could not import."}"
                    }
                }
                epubStatusIsError = failures.isNotEmpty() && successes.isEmpty()
                epubStatus = if (successes.isNotEmpty()) "Imported ${successes.size} files" else if (failures.isNotEmpty()) failures.joinToString("\n") else "Nothing imported."
            } catch (error: Exception) {
                epubStatusIsError = true
                epubStatus = error.message ?: "Could not import EPUB."
            } finally {
                epubBusy = false
            }
        }
    }

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Import", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        
        if (workImporter != null) {
            item {
                Column(modifier = Modifier.padding(top = 18.dp)) {
                    Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                        SubjectFormRow(if (epubBusy) "Importing…" else "Import EPUB", onClick = { if (!epubBusy) importEpubLauncher.launch(EpubOpenMimeTypes) })
                    }
                    if (epubStatus != null) {
                        Text(epubStatus!!, color = if (epubStatusIsError) MaterialTheme.colorScheme.error else tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                    } else {
                        Text("Add your own .epub files to the Library (not downloaded from AO3).", style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsPreservationPage(
    workAvailabilitySweep: WorkAvailabilitySweep?,
    onOpenAvailabilitySweep: () -> Unit
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Preservation"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Preservation", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }

        if (workAvailabilitySweep != null) {
            item {
                var sweepBusy by remember { mutableStateOf(false) }
                var sweepStatus by remember { mutableStateOf<String?>(null) }
                Column(modifier = Modifier.padding(top = 18.dp)) {
                    Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                        SubjectFormRow(if (sweepBusy) "Sweeping…" else "Run Availability Sweep", onClick = {
                            if (!sweepBusy) {
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
                        })
                        SubjectRowSeparator()
                        SubjectFormRow("Unavailable Works", showsDisclosure = true, onClick = onOpenAvailabilitySweep)
                    }
                    if (sweepStatus != null) {
                        Text(sweepStatus!!, color = tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                    } else {
                        Text("Check library for deleted/hidden works on AO3.", style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsListeningPage() {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Listening"; chrome.hasSubjectHeader = true }
    val palette = LocalSubjectPalette.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Listening", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    // ponytail: no voice/speed settings on Android yet (iOS SettingsListeningPage); add with the TTS settings port.
                    SubjectFormRow("Start Read Aloud from the reader's More menu.")
                }
            }
        }
    }
}

@Composable
fun SettingsAccountPage(authRepository: AO3AuthRepository?, onLogin: () -> Unit) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "AO3 Account"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val authState by (authRepository?.state ?: flowOf(AO3AuthState.SignedOut)).collectAsState(initial = AO3AuthState.SignedOut)

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "AO3 Account", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    when (authState) {
                        is AO3AuthState.SignedIn -> {
                            SubjectFormRow("Signed In", value = (authState as AO3AuthState.SignedIn).username)
                            SubjectRowSeparator()
                            SubjectFormRow("Log Out", onClick = { scope.launch { authRepository?.logout() } })
                        }
                        AO3AuthState.Restoring, AO3AuthState.SigningIn -> {
                            SubjectFormRow("Checking AO3 session…")
                        }
                        else -> {
                            SubjectFormRow("Log In to AO3…", onClick = onLogin)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsPrivacySettingsPage(repository: SettingsRepository, settings: KudosSettings, navController: NavController) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Privacy"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Privacy", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Hide mature content", trailing = {
                        SubjectToggle(checked = settings.privacy.hideMatureContent, onCheckedChange = { scope.launch { repository.updateHideMatureContent(it) } })
                    })
                    if (settings.privacy.hideMatureContent) {
                        SubjectRowSeparator()
                        SubjectFormRow("When hidden", trailing = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                MatureContentMode.entries.forEach { mode ->
                                    FilterChip(
                                        selected = settings.privacy.matureContentMode == mode,
                                        onClick = { scope.launch { repository.updateMatureContentMode(mode) } },
                                        label = { Text(if (mode == MatureContentMode.Hide) "Hide" else "Blur") }
                                    )
                                }
                            }
                        })
                    }
                    SubjectRowSeparator()
                    SubjectFormRow("Require biometric to reveal", trailing = {
                        SubjectToggle(checked = settings.privacy.requireBiometricToReveal, onCheckedChange = { scope.launch { repository.updateRequireBiometricToReveal(it) } })
                    })
                    SubjectRowSeparator()
                    SubjectFormRow("Privacy & Local Data", showsDisclosure = true, onClick = { navController.navigate("privacy") })
                }
            }
        }
    }
}

@Composable
fun SettingsAboutPage(onOpenAbout: () -> Unit, onReportBug: () -> Unit, navController: NavController, appUpdateRepository: AppUpdateRepository?) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "About"; chrome.hasSubjectHeader = true }
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val updateState by (appUpdateRepository?.state ?: kotlinx.coroutines.flow.flowOf(AppUpdateState.Idle)).collectAsState(initial = AppUpdateState.Idle)

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "About", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Version", value = io.github.cidy02.kudos.BuildConfig.VERSION_NAME)
                    SubjectRowSeparator()
                    SubjectFormRow("Privacy and local data", showsDisclosure = true, onClick = { navController.navigate("privacy") })
                    SubjectRowSeparator()
                    SubjectFormRow("About Kudos", onClick = onOpenAbout)
                    SubjectRowSeparator()
                    SubjectFormRow("Report a Bug", onClick = onReportBug)
                    SubjectRowSeparator()
                    SubjectFormRow("Source on GitHub", onClick = {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader"))
                        runCatching { context.startActivity(intent) }
                    })
                }
            }
        }

        if (appUpdateRepository != null) {
            item {
                Column(modifier = Modifier.padding(top = 18.dp)) {
                    io.github.cidy02.kudos.ui.subject.SectionRuleHeader("Software Update")
                    Column(modifier = Modifier.padding(top = 8.dp).padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                        when (updateState) {
                            AppUpdateState.Idle, AppUpdateState.UpToDate -> {
                                SubjectFormRow("Status", value = "Up to date", onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } })
                                SubjectRowSeparator()
                                SubjectFormRow("Check Now", onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } })
                            }
                            AppUpdateState.Checking -> {
                                SubjectFormRow("Checking GitHub for updates…")
                            }
                            is AppUpdateState.UpdateAvailable -> {
                                SubjectFormRow("Version ${(updateState as AppUpdateState.UpdateAvailable).match.version} is available")
                            }
                            is AppUpdateState.Downloading -> {
                                SubjectFormRow("Downloading version ${(updateState as AppUpdateState.Downloading).match.version}…")
                            }
                            is AppUpdateState.ReadyToInstall -> {
                                val apkPath = (updateState as AppUpdateState.ReadyToInstall).apkPath
                                SubjectFormRow("Install Update", onClick = {
                                    runCatching { context.startActivity(appUpdateRepository.installIntentFor(apkPath)) }
                                })
                            }
                            is AppUpdateState.Failed -> {
                                SubjectFormRow("Status", value = (updateState as AppUpdateState.Failed).message)
                                SubjectRowSeparator()
                                SubjectFormRow("Try Again", onClick = { scope.launch { appUpdateRepository.checkNow(autoDownload = true) } })
                            }
                        }
                    }
                    Text(
                        "Kudos Android is Alpha until it reaches iOS feature parity — expect rougher edges and more frequent updates.",
                        style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                    )
                }
            }
        }
    }
}

@Composable
fun SettingsBackupPageWrapper(onOpenBackup: () -> Unit, navController: NavController, repository: SettingsRepository, settings: KudosSettings) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Backup"; chrome.hasSubjectHeader = true }
    val palette = LocalSubjectPalette.current
    val scope = rememberCoroutineScope()
    var showResetConfirm by remember { mutableStateOf(false) }

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Backup", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Export / Import Backup…", showsDisclosure = true, onClick = onOpenBackup)
                    SubjectRowSeparator()
                    SubjectFormRow("Reset settings to defaults", showsDisclosure = true, onClick = { showResetConfirm = true })
                }
            }
        }
    }

    io.github.cidy02.kudos.ui.components.DestructiveConfirmation(
        show = showResetConfirm,
        title = "Reset settings to defaults?",
        text = "This clears reader, theme, privacy, and other app preferences back to their defaults. Your Library, downloads, and AO3 session are not affected.",
        confirmText = "Reset",
        confirmBeforeDelete = true, // Always confirm reset
        onConfirm = {
            showResetConfirm = false
            scope.launch { repository.resetToDefaults() }
        },
        onDismissRequest = { showResetConfirm = false }
    )
}

@Composable
fun SettingsReadingQueuesPageWrapper(onOpenQueues: () -> Unit, navController: NavController) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Reading Queues"; chrome.hasSubjectHeader = true }
    val palette = LocalSubjectPalette.current

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Reading Queues", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Queue Storage", showsDisclosure = true, onClick = onOpenQueues)
                }
            }
        }
    }
}

@Composable
fun SettingsFontPage(repository: SettingsRepository, settings: KudosSettings, customFontRepository: CustomFontRepository) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Font"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current

    val importedFonts by customFontRepository.observeImported().collectAsState(initial = emptyList())
    val options = remember(importedFonts) { io.github.cidy02.kudos.core.model.ReaderFontCatalog.options(importedFonts) }

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
                        val nameWithoutExt = displayName?.substringAfterLast('/')?.substringAfterLast('\\')?.substringBeforeLast('.')?.trim().orEmpty()
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
                fontStatus = if (successes.isNotEmpty()) "Imported ${successes.size} fonts" else if (failures.isNotEmpty()) failures.joinToString("\n") else "Nothing imported."
            } catch (error: Exception) {
                fontStatusIsError = true
                fontStatus = error.message ?: "Could not import font."
            } finally {
                fontBusy = false
            }
        }
    }

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Font", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    options.forEachIndexed { index, option ->
                        if (index > 0) SubjectRowSeparator()
                        SubjectFormRow(
                            label = option.name + (if (option.isCustom) " (Imported)" else ""),
                            trailing = {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (settings.reader.readerFontId == option.id) {
                                        Icon(imageVector = Icons.Outlined.CheckCircle, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
                                    }
                                    if (option.isCustom) {
                                        androidx.compose.material3.IconButton(
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
                                            Icon(imageVector = Icons.Outlined.Delete, contentDescription = "Delete ${option.name}")
                                        }
                                    }
                                }
                            },
                            onClick = { scope.launch { repository.updateReaderFontId(option.id) } }
                        )
                    }
                }
                Text("Built-in families plus fonts you import (.ttf / .otf).", style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
            }
        }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow(if (fontBusy) "Working…" else "Import font (.ttf / .otf)", onClick = { if (!fontBusy) importFontLauncher.launch(arrayOf("font/ttf", "font/otf", "application/x-font-ttf", "application/x-font-otf", "application/font-sfnt", "application/octet-stream")) })
                }
                if (fontStatus != null) {
                    Text(fontStatus!!, color = if (fontStatusIsError) MaterialTheme.colorScheme.error else tokens.secondaryInk, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                }
            }
        }
    }
}

enum class ThemeChipOption(val label: String, val setting: AppThemeSetting) {
    Light("Light", AppThemeSetting.Light),
    Sepia("Sepia", AppThemeSetting.Sepia),
    Dark("Dark", AppThemeSetting.Dark),
    Oled("OLED", AppThemeSetting.Oled),
    System("System", AppThemeSetting.System)
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun AccentColorEditor(accentHex: String, onCommit: (String) -> Unit, onReset: () -> Unit) {
    var draft by remember { mutableStateOf(accentHex) }
    LaunchedEffect(accentHex) {
        draft = accentHex
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp)) {
        Text(text = "Accent color", style = MaterialTheme.typography.bodyMedium)
        androidx.compose.foundation.layout.FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            val presets = listOf("#990000", "#0B57D0", "#0F6B46", "#7A3E00", "#5B2C6F")
            presets.forEach { preset ->
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
        androidx.compose.material3.OutlinedTextField(
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
            androidx.compose.material3.TextButton(onClick = onReset) {
                Text("Reset to AO3 Red")
            }
        }
    }
}

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

@Composable
fun SettingsFolderSyncPage(repository: SettingsRepository, settings: KudosSettings) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) { chrome.customTitle = "Folder Sync"; chrome.hasSubjectHeader = true }
    val scope = rememberCoroutineScope()
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val syncRepository = (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)?.container?.syncRepository
    var lastSyncFolded by remember { mutableStateOf(0) }
    var syncBusy by remember { mutableStateOf(false) }

    val syncFolderLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri != null) {
            scope.launch { syncRepository?.connect(uri) }
        }
    }

    LazyColumn(modifier = Modifier.fillMaxSize().subjectScreenWash(palette), contentPadding = PaddingValues(bottom = 20.dp)) {
        item { SubjectHeaderBlock(kicker = "Settings", title = "Folder Sync", palette = palette, gutter = SubjectMetrics.accountGutter, modifier = Modifier.padding(top = 20.dp)) }
        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
                    SubjectFormRow("Enable folder sync", trailing = {
                        SubjectToggle(checked = settings.sync.isEnabled, onCheckedChange = { enabled ->
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
                        })
                    })
                    SubjectRowSeparator()
                    SubjectFormRow(
                        if (settings.sync.folderUri == null) "Select sync folder" else "Change sync folder",
                        onClick = { syncFolderLauncher.launch(null) }
                    )
                    
                    if (settings.sync.isEnabled && settings.sync.folderUri != null) {
                        SubjectRowSeparator()
                        SubjectFormRow(if (syncBusy) "Working…" else "Sync Now", onClick = {
                            if (!syncBusy) {
                                syncBusy = true
                                scope.launch {
                                    val result = syncRepository?.runSync()
                                    lastSyncFolded = (result as? io.github.cidy02.kudos.backup.SyncResult.Success)?.foldedConflicts ?: 0
                                    syncBusy = false
                                }
                            }
                        })
                    }
                }
                
                if (settings.sync.isEnabled && settings.sync.folderUri != null) {
                    if (lastSyncFolded > 0) {
                        Text(
                            text = if (lastSyncFolded == 1) "Merged 1 conflicting copy from another device." else "Merged $lastSyncFolded conflicting copies from other devices.",
                            style = MaterialTheme.typography.labelSmall,
                            color = tokens.secondaryInk,
                            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)
                        )
                    }
                }
            }
        }
    }
}
