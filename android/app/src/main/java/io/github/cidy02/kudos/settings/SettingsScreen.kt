package io.github.cidy02.kudos.settings

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
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
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val requested = (LocalContext.current as? Activity)?.intent?.getStringExtra("kudosSettingsPage")
    val start = requested?.takeIf { it in SettingsDebugPages } ?: "hub"

    NavHost(navController = navController, startDestination = start) {
        composable("hub") {
            SettingsHubScreen(navController, settings, authRepository)
        }
        composable("appearance") {
            SettingsAppearancePage(repository, settings)
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
            SettingsDownloadsPage(repository, settings)
        }
        composable("preservation") {
            SettingsPreservationPage(onOpenAvailabilitySweep)
        }
        composable("library") {
            SettingsLibraryPage(repository, settings)
        }
        composable("backup") {
            SettingsBackupPageWrapper(onOpenBackup, navController, repository, settings)
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
    "library", "backup", "folder_sync", "import_files", "reading_queues", "account",
    "privacy_settings", "privacy", "about"
)
