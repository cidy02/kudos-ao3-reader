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
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.ui.subject.DebugDestination
import io.github.cidy02.kudos.ui.subject.DebugRoutes
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
    container: KudosAppContainer,
    selections: List<io.github.cidy02.kudos.works.SelectedDocumentImport>,
    preparationFailures: List<String>
): String? {
    val imported = mutableListOf<String>()
    val failed = preparationFailures.toMutableList()
    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        for (selection in selections) {
            val item = selection.pending
            val label = item.displayName?.substringAfterLast('/')?.ifBlank { null } ?: "file"
            when (val result = container.workImporter.importLocalEpub(
                item.displayName,
                item.bytes,
                selection.downloadedAt
            )) {
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
fun KudosApp(
    container: KudosAppContainer,
    sessionTheme: KudosThemeMode? = null,
    skipOnboarding: Boolean = false,
    debugRoute: String? = null
) {
    // The catalog has to open before onboarding, or the adb extra never lands
    // on a screen. Release builds compile a stub that always returns false.
    if (BuildConfig.DEBUG) {
        if (DebugDestination(debugRoute)) return
    }
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

    val effectiveCompletedOnboarding = if (skipOnboarding) true else hasCompletedOnboarding
    val effectiveDismissedSyncFolder = if (skipOnboarding) true else hasPermanentlyDismissedSyncFolderOnboarding

    val persistedThemeMode = settings.app.appTheme.toThemeMode()
    var sessionThemeState by remember(sessionTheme) { androidx.compose.runtime.mutableStateOf(sessionTheme) }
    val themeMode = sessionThemeState ?: persistedThemeMode
    val scope = rememberCoroutineScope()
    var showBugReport by remember { androidx.compose.runtime.mutableStateOf(false) }
    // Survives recomposition but not process death, on purpose: "Not Now" means
    // "not this launch", while the checkbox means "never again" (persisted).
    var syncOnboardingDismissedThisSession by remember { androidx.compose.runtime.mutableStateOf(false) }

    // "Open with Kudos" / "Share to Kudos": MainActivity queues the incoming
    // URIs, we import them and report the outcome. Held until onboarding is
    // done so a first-launch share isn't swallowed by the Welcome screen.
    val context = LocalContext.current
    val offeredImports by io.github.cidy02.kudos.works.ExternalFileImport.pending.collectAsState()
    var pendingImports by remember {
        androidx.compose.runtime.mutableStateOf<List<io.github.cidy02.kudos.works.PendingDocumentImport>>(emptyList())
    }
    var importPreparationFailures by remember {
        androidx.compose.runtime.mutableStateOf<List<String>>(emptyList())
    }
    var importStatus by remember { androidx.compose.runtime.mutableStateOf<String?>(null) }
    androidx.compose.runtime.LaunchedEffect(offeredImports, effectiveCompletedOnboarding) {
        if (offeredImports.isEmpty() || effectiveCompletedOnboarding != true) return@LaunchedEffect
        val uris = io.github.cidy02.kudos.works.ExternalFileImport.consume()
        // consume() empties the queue, which changes this effect's key and cancels it, so
        // the preparation runs in the composition's scope rather than the effect's.
        scope.launch {
            val preparation = io.github.cidy02.kudos.works.prepareDocumentImports(context, uris)
            pendingImports = pendingImports + preparation.imports
            importPreparationFailures = importPreparationFailures + preparation.failures
            if (preparation.imports.isEmpty()) {
                importStatus = preparation.failures.joinToString("\n").ifBlank { null }
            }
        }
    }

    KudosTheme(themeMode = themeMode, accentColorHex = settings.app.accentColorHex) {
        if (pendingImports.isNotEmpty()) {
            io.github.cidy02.kudos.works.DownloadDateImportConfirmation(
                imports = pendingImports,
                onCancel = {
                    pendingImports = emptyList()
                    importPreparationFailures = emptyList()
                },
                onImport = { selections ->
                    pendingImports = emptyList()
                    scope.launch {
                        importStatus = importExternalFiles(
                            container,
                            selections,
                            importPreparationFailures
                        )
                        importPreparationFailures = emptyList()
                    }
                }
            )
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

        // App-wide shake-to-report (iOS UIWindow.motionEnded parity). Sensor
        // listener is lifecycle-bound to this composition and unregistered on leave.
        ShakeToReportEffect { showBugReport = true }

        // Restore the AO3 session at launch, as iOS ContentView does; until now only the
        // Account tab restored it, so Work detail and Comments read signed-out before then.
        androidx.compose.runtime.LaunchedEffect(Unit) { container.authRepository.restoreSession() }

        if (showBugReport) {
            androidx.compose.ui.window.Dialog(
                onDismissRequest = { showBugReport = false },
                properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
            ) {
                androidx.compose.material3.Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    BugReportScreen(onCancel = { showBugReport = false })
                }
            }
        }

        when (effectiveCompletedOnboarding) {
            null -> Box(Modifier.fillMaxSize())
            false -> WelcomeScreen(
                onContinue = {
                    scope.launch {
                        container.settingsRepository.setHasCompletedOnboarding(true)
                    }
                }
            )
            true -> {
                if (!hasConfiguredSyncFolder &&
                    !effectiveDismissedSyncFolder &&
                    !syncOnboardingDismissedThisSession
                ) {
                    SyncFolderOnboardingScreen(
                        container = container,
                        onFinished = { permanentlyDismissed ->
                            // "Not Now" must let the user through *now*, whether or
                            // not they ticked "Don't remind me again". Persisting the
                            // flag alone is not enough: with the box unticked it
                            // writes back the value the gate already had, so the
                            // screen re-showed itself forever and a first-launch user
                            // could never reach the app.
                            syncOnboardingDismissedThisSession = true
                            if (permanentlyDismissed) {
                                scope.launch {
                                    container.settingsRepository
                                        .setHasPermanentlyDismissedSyncFolderOnboarding(true)
                                }
                            }
                        }
                    )
                } else {
                    // Settings > Library > Show zero counts reaches every work card (iOS @AppStorage).
                    androidx.compose.runtime.CompositionLocalProvider(
                        io.github.cidy02.kudos.ui.components.LocalShowsZeroStats provides
                            settings.app.showsZeroStats
                    ) {
                    MainScaffold(
                        container = container,
                        themeMode = themeMode,
                        startRoute = debugRoute?.takeIf { it.startsWith(DebugRoutes.NAV_PREFIX) }
                            ?.removePrefix(DebugRoutes.NAV_PREFIX),
                        onCycleTheme = {
                            if (sessionThemeState != null) {
                                sessionThemeState = sessionThemeState?.next()
                            } else {
                                scope.launch {
                                    container.settingsRepository.updateAppTheme(themeMode.next().toAppTheme())
                                }
                            }
                        }
                    )
                    }
                }
            }
        }
    }
}
