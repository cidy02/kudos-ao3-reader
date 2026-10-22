package io.github.cidy02.kudos.settings

import io.github.cidy02.kudos.app.DebugShotEffect
import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository

@Composable
fun SettingsScreen(
    onOpenQueueStorage: () -> Unit = {},
    repository: SettingsRepository,
    customFontRepository: CustomFontRepository,
    onOpenBackup: () -> Unit,
    onReportBug: () -> Unit = {},
    authRepository: AO3AuthRepository? = null,
    onLogin: () -> Unit = {},
    onOpenAbout: () -> Unit = {},
    appUpdateRepository: AppUpdateRepository? = null,
    workImporter: WorkImporter? = null,
    fandomCatalogCache: FandomCatalogCache? = null,
    workRepository: WorkRepository? = null,
    onOpenAvailabilitySweep: () -> Unit = {},
    footprintScanner: LocalDataFootprintScanner? = null
) {
    val navController = rememberNavController()
    DebugShotEffect("settings") { name ->
        navController.navigate(when (name) {
            "privacydata" -> "privacy"
            "customizetheme" -> "appearance"
            "pairing", "revokedevice" -> "folder_sync"
            else -> "listening"
        })
    }

    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val requested = (LocalContext.current as? Activity)?.intent?.getStringExtra("kudosSettingsPage")
    val start = requested?.takeIf { it in SettingsDebugPages } ?: "hub"

    // To the shell this is one route; its pages are in here. The shell hides the top row when a
    // page is scrolled and keeps that by route, so a page opened from the scrolled list of
    // settings had no back button until it was dragged down. Each page is named to the shell,
    // which then keeps each one's own (`PushedShellChrome.scrollKey`).
    val page by navController.currentBackStackEntryAsState()
    // Every page here draws its own header. `null` (3dh) was re-applied each time this
    // screen recomposed, after the hub had said otherwise, so Settings first opened under a
    // plain top bar ("Settings" and a theme button) over an empty band.
    io.github.cidy02.kudos.app.ProvidePushedShellChrome(hasSubjectHeader = true, scrollKey = page?.destination?.route)

    NavHost(navController = navController, startDestination = start) {
        composable("hub") {
            val importedFonts by remember(customFontRepository) { customFontRepository.observeImported() }
                .collectAsState(initial = emptyList())
            SettingsHubScreen(navController, settings, authRepository,
                fontName = io.github.cidy02.kudos.core.model.ReaderFontCatalog.name(settings.reader.readerFontId, importedFonts),
                onOpenBackup = onOpenBackup)
        }
        composable("appearance") {
            SettingsAppearancePage(repository, settings, customFontRepository)
        }
        composable("font") {
            SettingsFontPage(repository, settings, customFontRepository)
        }
        composable("reader") {
            SettingsReaderPage(repository, settings)
        }
        composable("listening") {
            SettingsListeningPage(repository)
        }
        composable("downloads") {
            SettingsDownloadsPage(repository, settings, footprintScanner)
        }
        composable("preservation") {
            SettingsPreservationPage(onOpenAvailabilitySweep)
        }
        composable("library") {
            SettingsLibraryPage(repository, settings)
        }
        composable("folder_sync") {
            SettingsFolderSyncPage(repository, settings)
        }
        composable("import_files") {
            SettingsImportPage(workImporter)
        }
        composable("reading_queues") {
            SettingsReadingQueuesPageWrapper(onOpenQueueStorage, navController, repository, settings)
        }
        composable("account") {
            SettingsAccountPage(authRepository, onLogin)
        }
        composable("privacy_settings") {
            SettingsPrivacySettingsPage(repository, settings, navController)
        }
        composable("privacy") {
            PrivacyDataScreen(workRepository, fandomCatalogCache, settings, authRepository, footprintScanner)
        }
        composable("about") {
            SettingsAboutPage(onOpenAbout, onReportBug, navController, appUpdateRepository)
        }
    }
}

private val SettingsDebugPages = setOf(
    "hub", "appearance", "font", "reader", "listening", "downloads", "preservation",
    "library", "folder_sync", "import_files", "reading_queues", "account",
    "privacy_settings", "privacy", "about"
)
