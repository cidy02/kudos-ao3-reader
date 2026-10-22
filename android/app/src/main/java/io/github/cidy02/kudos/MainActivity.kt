package io.github.cidy02.kudos

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.DemoLibrary
import io.github.cidy02.kudos.app.KudosApp
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.ui.subject.DebugRoutes
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.app.toAppTheme
import io.github.cidy02.kudos.works.ExternalFileImport
import java.util.Locale

// FragmentActivity (not bare ComponentActivity) so Readium's Fragment-based EPUB
// navigator can be hosted via supportFragmentManager (see ReadiumNavigatorHost).
class MainActivity : FragmentActivity() {
    private val debugRoute = mutableStateOf<String?>(null)
    private val debugRouteRequest = mutableStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super, and before the startup metadata refresh can leave the device.
        if (BuildConfig.DEBUG && DemoNetwork.isRequested(intent)) {
            DemoNetwork.activate(
                applicationContext.assets,
                signedIn = isShotIntent(intent) || intent?.getBooleanExtra(DemoNetwork.SIGNED_IN_EXTRA, false) == true
            )
        } else {
            DemoNetwork.markNotDemo()
        }
        io.github.cidy02.kudos.reader.readium.ReaderFragmentRestore.before(this)
        super.onCreate(savedInstanceState)
        io.github.cidy02.kudos.reader.readium.ReaderFragmentRestore.after(this, savedInstanceState)
        enableEdgeToEdge()
        // A restored window must start outside immersion until a resumed reader takes ownership.
        androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            .show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        // "Open with Kudos" / "Share to Kudos" — the manifest advertises these
        // mime types, so something has to actually read the incoming Intent.
        // Once: a restart hands the same Intent back, and the file was offered a second time.
        if (savedInstanceState == null) ExternalFileImport.offer(intent)
        DemoNetwork.applyCachedPagesExtra(intent)
        publishDebugRoute(intent)
        val container = (application as KudosApplication).container

        var sessionTheme: KudosThemeMode? = null
        var skipOnboarding = false

        if (BuildConfig.DEBUG) {
            val isDemoRequested = DemoNetwork.isRequested(intent)

            val themeExtra = intent?.getStringExtra("kudosTheme")
            sessionTheme = when (themeExtra?.lowercase(Locale.ROOT)) {
                "dark" -> KudosThemeMode.Dark
                "light" -> KudosThemeMode.Light
                "sepia" -> KudosThemeMode.Sepia
                "oled" -> KudosThemeMode.Oled
                else -> null
            }
            // The screenshot pairs set a theme per launch. Saving it as well lets the screens that
            // read the stored theme follow it (the reader with Match on, Settings' Appearance row),
            // as `-appTheme` does on iOS (A71: the reader stayed Light in every column).
            sessionTheme?.let { mode ->
                (application as KudosApplication).launchIo {
                    container.settingsRepository.updateAppTheme(mode.toAppTheme())
                }
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
                        DemoLibrary.seed(container, applicationContext)
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
                debugRoute = debugRoute.value,
                debugRouteRequest = debugRouteRequest.value
            )
        }
    }

    // Already-running app: a second "Open with" arrives here, not in onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ExternalFileImport.offer(intent)
        DemoNetwork.applyCachedPagesExtra(intent)
        publishDebugRoute(intent)
        if (BuildConfig.DEBUG) {
            val isDemoRequested = DemoNetwork.isRequested(intent)
            val hasThemeExtra = intent.hasExtra("kudosTheme")
            if (isDemoRequested) {
                DemoNetwork.activate(applicationContext.assets, signedIn = isShotIntent(intent))
                val container = (application as KudosApplication).container
                (application as KudosApplication).launchIo {
                    DemoLibrary.seed(container, applicationContext)
                    container.settingsRepository.setHasCompletedOnboarding(true)
                    container.settingsRepository.setHasPermanentlyDismissedSyncFolderOnboarding(true)
                }
            }
            if (hasThemeExtra) {
                recreate()
            }
        }
    }

    private fun isShotIntent(intent: Intent?): Boolean = BuildConfig.DEBUG &&
        intent?.getStringExtra(DebugRoutes.EXTRA)?.startsWith("shot:") == true

    private fun publishDebugRoute(intent: Intent?) {
        // A second request for the same preview should reopen it after dismissal.
        if (BuildConfig.DEBUG) {
            io.github.cidy02.kudos.app.DebugShotRequests.clear()
            debugRouteRequest.value++
        }
        debugRoute.value = if (BuildConfig.DEBUG) intent?.getStringExtra(DebugRoutes.EXTRA) else null
    }
}
