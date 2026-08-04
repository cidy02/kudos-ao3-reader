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
    val themeMode = settings.app.appTheme.toThemeMode()
    val scope = rememberCoroutineScope()
    var showBugReport by remember { androidx.compose.runtime.mutableStateOf(false) }

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
            true -> MainScaffold(
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
