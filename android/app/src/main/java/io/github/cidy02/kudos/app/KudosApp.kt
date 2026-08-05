package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.onboarding.WelcomeScreen
import io.github.cidy02.kudos.onboarding.SyncFolderOnboardingScreen
import io.github.cidy02.kudos.support.ShakeToReportEffect
import io.github.cidy02.kudos.account.BugReportScreen
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// Settings' persisted 4-option app theme and the quick-toggle palette icon in
// MainScaffold both need to read and write the *same* value — previously the
// icon only mutated local Compose state (reset on every process start) and the
// Settings picker wrote a DataStore key nothing ever read back.
private fun AppThemeSetting.toThemeMode(): KudosThemeMode = when (this) {
    AppThemeSetting.System -> KudosThemeMode.System
    AppThemeSetting.Light -> KudosThemeMode.Light
    AppThemeSetting.Dark -> KudosThemeMode.Dark
    AppThemeSetting.Oled -> KudosThemeMode.Oled
    AppThemeSetting.Sepia -> KudosThemeMode.Sepia
}

private fun KudosThemeMode.toAppTheme(): AppThemeSetting = when (this) {
    KudosThemeMode.System -> AppThemeSetting.System
    KudosThemeMode.Light -> AppThemeSetting.Light
    KudosThemeMode.Dark -> AppThemeSetting.Dark
    KudosThemeMode.Oled -> AppThemeSetting.Oled
    KudosThemeMode.Sepia -> AppThemeSetting.Sepia
}

/**
 * Reads each shared/opened URI and hands it to [io.github.cidy02.kudos.works.WorkImporter],
 * returning a one-line summary. Failures are per-file so one bad attachment
 * doesn't sink the rest of a multi-file share.
 */
private suspend fun importExternalFiles(
    context: android.content.Context,
    container: KudosAppContainer,
    uris: List<android.net.Uri>
): String? {
    if (uris.isEmpty()) return null
    val imported = mutableListOf<String>()
    val failed = mutableListOf<String>()
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        for (uri in uris) {
            val displayName = io.github.cidy02.kudos.works.ExternalFileImport.displayNameFor(context, uri)
            val label = displayName?.substringAfterLast('/')?.ifBlank { null } ?: "file"
            val bytes = runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull()
            if (bytes == null) {
                failed += "$label: couldn't be read"
                continue
            }
            when (val result = container.workImporter.importLocalEpub(displayName, bytes)) {
                is io.github.cidy02.kudos.works.WorkImportResult.Success ->
                    imported += "“${result.work.title}”"
                is io.github.cidy02.kudos.works.WorkImportResult.Failure -> {
                    val message = (result.error as? io.github.cidy02.kudos.network.ao3.AO3Error.Validation)
                        ?.message ?: "couldn't be imported"
                    failed += "$label: $message"
                }
            }
        }
    }
    return buildString {
        if (imported.isNotEmpty()) {
            append("Added ${imported.size} to your Library: ${imported.joinToString(", ")}.")
        }
        if (failed.isNotEmpty()) {
            if (isNotEmpty()) append("\n\n")
            append(failed.joinToString("\n"))
        }
    }.ifBlank { null }
}

@Composable
fun KudosApp(container: KudosAppContainer) {
    val settings by container.settingsRepository.settings
        .collectAsState(initial = KudosSettings())
    // Keep PrivacyGate's biometric flag in lockstep with Settings (iOS UserDefaults).
    androidx.compose.runtime.SideEffect {
        container.privacyGate.requireBiometricToReveal =
            settings.privacy.requireBiometricToReveal
    }
    // null until DataStore emits — avoids flashing Welcome at returning users.
    val hasCompletedOnboarding by remember(container.settingsRepository) {
        container.settingsRepository.hasCompletedOnboarding.map<Boolean, Boolean?> { completed -> completed }
    }.collectAsState(initial = null)

    val hasConfiguredSyncFolder by remember(container.settingsRepository) {
        container.settingsRepository.hasConfiguredSyncFolder
    }.collectAsState(initial = false)

    val hasPermanentlyDismissedSyncFolderOnboarding by remember(container.settingsRepository) {
        container.settingsRepository.hasPermanentlyDismissedSyncFolderOnboarding
    }.collectAsState(initial = false)

    val themeMode = settings.app.appTheme.toThemeMode()
    val scope = rememberCoroutineScope()
    var showBugReport by remember { androidx.compose.runtime.mutableStateOf(false) }

    // "Open with Kudos" / "Share to Kudos": MainActivity queues the incoming
    // URIs, we import them and report the outcome. Held until onboarding is
    // done so a first-launch share isn't swallowed by the Welcome screen.
    val context = LocalContext.current
    val pendingImports by io.github.cidy02.kudos.works.ExternalFileImport.pending.collectAsState()
    var importStatus by remember { androidx.compose.runtime.mutableStateOf<String?>(null) }
    androidx.compose.runtime.LaunchedEffect(pendingImports, hasCompletedOnboarding) {
        if (pendingImports.isEmpty() || hasCompletedOnboarding != true) return@LaunchedEffect
        val uris = io.github.cidy02.kudos.works.ExternalFileImport.consume()
        importStatus = importExternalFiles(context, container, uris)
    }

    if (importStatus != null) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { importStatus = null },
            title = { androidx.compose.material3.Text("Import") },
            text = { androidx.compose.material3.Text(importStatus.orEmpty()) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { importStatus = null }) {
                    androidx.compose.material3.Text("OK")
                }
            }
        )
    }

    KudosTheme(themeMode = themeMode, accentColorHex = settings.app.accentColorHex) {
        // App-wide shake-to-report (iOS UIWindow.motionEnded parity). Sensor
        // listener is lifecycle-bound to this composition and unregistered on leave.
        ShakeToReportEffect { showBugReport = true }

        if (showBugReport) {
            androidx.compose.ui.window.Dialog(
                onDismissRequest = { showBugReport = false },
                properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
            ) {
                androidx.compose.material3.Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    BugReportScreen(onBack = { showBugReport = false })
                }
            }
        }

        when (hasCompletedOnboarding) {
            null -> Box(Modifier.fillMaxSize())
            false -> WelcomeScreen(
                onContinue = {
                    scope.launch {
                        container.settingsRepository.setHasCompletedOnboarding(true)
                    }
                }
            )
            true -> {
                if (!hasConfiguredSyncFolder && !hasPermanentlyDismissedSyncFolderOnboarding) {
                    SyncFolderOnboardingScreen(
                        container = container,
                        onFinished = { permanentlyDismissed ->
                            scope.launch {
                                container.settingsRepository.setHasPermanentlyDismissedSyncFolderOnboarding(permanentlyDismissed)
                            }
                        }
                    )
                } else {
                    MainScaffold(
                        container = container,
                        themeMode = themeMode,
                        onCycleTheme = {
                            scope.launch {
                                container.settingsRepository.updateAppTheme(themeMode.next().toAppTheme())
                            }
                        }
                    )
                }
            }
        }
    }
}
