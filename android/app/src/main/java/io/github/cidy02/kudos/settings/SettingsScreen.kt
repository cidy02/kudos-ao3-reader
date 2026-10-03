package io.github.cidy02.kudos.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
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
    workAvailabilitySweep: WorkAvailabilitySweep? = null,
    onOpenAvailabilitySweep: () -> Unit = {}
) {
    val navController = rememberNavController()
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)

    NavHost(navController = navController, startDestination = "hub") {
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
            SettingsListeningPage()
        }
        composable("downloads") {
            SettingsDownloadsPage(repository, settings)
        }
        composable("preservation") {
            SettingsPreservationPage(workAvailabilitySweep, onOpenAvailabilitySweep)
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
            SettingsReadingQueuesPageWrapper(onOpenQueueStorage, navController)
        }
        composable("account") {
            SettingsAccountPage(authRepository, onLogin)
        }
        composable("privacy_settings") {
            SettingsPrivacySettingsPage(repository, settings, navController)
        }
        composable("privacy") {
            PrivacyDataScreen(workRepository, fandomCatalogCache, settings)
        }
        composable("about") {
            SettingsAboutPage(onOpenAbout, onReportBug, navController, appUpdateRepository)
        }
    }
}
