package io.github.cidy02.kudos

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.DemoLibrary
import io.github.cidy02.kudos.app.KudosApp
import io.github.cidy02.kudos.ui.subject.DebugRoutes
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.ExternalFileImport
import java.util.Locale

// FragmentActivity (not bare ComponentActivity) so Readium's Fragment-based EPUB
// navigator can be hosted via supportFragmentManager (see ReadiumNavigatorHost).
class MainActivity : FragmentActivity() {
    private val debugRoute = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // "Open with Kudos" / "Share to Kudos" — the manifest advertises these
        // mime types, so something has to actually read the incoming Intent.
        ExternalFileImport.offer(intent)
        publishDebugRoute(intent)
        val container = (application as KudosApplication).container

        var sessionTheme: KudosThemeMode? = null
        var skipOnboarding = false

        if (BuildConfig.DEBUG) {
            val isDemoRequested = intent?.getBooleanExtra("kudosDemoLibrary", false) == true ||
                intent?.getStringExtra("kudosDemoLibrary").equals("true", ignoreCase = true)

            val themeExtra = intent?.getStringExtra("kudosTheme")
            sessionTheme = when (themeExtra?.lowercase(Locale.ROOT)) {
                "dark" -> KudosThemeMode.Dark
                "light" -> KudosThemeMode.Light
                "sepia" -> KudosThemeMode.Sepia
                "oled" -> KudosThemeMode.Oled
                else -> null
            }

            val onboardingExtra = intent?.getBooleanExtra("hasCompletedOnboarding", false) == true ||
                intent?.getStringExtra("hasCompletedOnboarding").equals("true", ignoreCase = true) ||
                intent?.getStringExtra("hasCompletedOnboarding").equals("YES", ignoreCase = true)

            val syncOnboardingExtra = intent?.getBooleanExtra("hasPermanentlyDismissedSyncFolderOnboarding", false) == true ||
                intent?.getStringExtra("hasPermanentlyDismissedSyncFolderOnboarding").equals("true", ignoreCase = true) ||
                intent?.getStringExtra("hasPermanentlyDismissedSyncFolderOnboarding").equals("YES", ignoreCase = true)

            if (isDemoRequested || onboardingExtra || syncOnboardingExtra) {
                skipOnboarding = true
            }

            if (isDemoRequested || onboardingExtra || syncOnboardingExtra) {
                (application as KudosApplication).launchIo {
                    if (isDemoRequested) {
                        DemoLibrary.seed(container)
                    }
                    if (isDemoRequested || onboardingExtra) {
                        container.settingsRepository.setHasCompletedOnboarding(true)
                    }
                    if (isDemoRequested || syncOnboardingExtra) {
                        container.settingsRepository.setHasPermanentlyDismissedSyncFolderOnboarding(true)
                    }
                }
            }
        }

        setContent {
            KudosApp(
                container = container,
                sessionTheme = sessionTheme,
                skipOnboarding = skipOnboarding,
                debugRoute = debugRoute.value
            )
        }
    }

    // Already-running app: a second "Open with" arrives here, not in onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ExternalFileImport.offer(intent)
        publishDebugRoute(intent)
        if (BuildConfig.DEBUG) {
            val isDemoRequested = intent.getBooleanExtra("kudosDemoLibrary", false) ||
                intent.getStringExtra("kudosDemoLibrary").equals("true", ignoreCase = true)
            val hasThemeExtra = intent.hasExtra("kudosTheme")
            if (isDemoRequested) {
                val container = (application as KudosApplication).container
                (application as KudosApplication).launchIo {
                    DemoLibrary.seed(container)
                    container.settingsRepository.setHasCompletedOnboarding(true)
                    container.settingsRepository.setHasPermanentlyDismissedSyncFolderOnboarding(true)
                }
            }
            if (hasThemeExtra) {
                recreate()
            }
        }
    }

    private fun publishDebugRoute(intent: Intent?) {
        debugRoute.value = if (BuildConfig.DEBUG) intent?.getStringExtra(DebugRoutes.EXTRA) else null
    }
}
