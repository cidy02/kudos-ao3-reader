package io.github.cidy02.kudos.app

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import io.github.cidy02.kudos.account.AccountScreen
import io.github.cidy02.kudos.backup.BackupScreen
import io.github.cidy02.kudos.browse.BrowseScreen
import io.github.cidy02.kudos.home.HomeScreen
import io.github.cidy02.kudos.library.LibraryScreen
import io.github.cidy02.kudos.reader.ReaderPlaceholderScreen
import io.github.cidy02.kudos.search.SearchScreen
import io.github.cidy02.kudos.settings.SettingsScreen
import io.github.cidy02.kudos.works.WorkDetailScreen

@Composable
fun AppNavHost(
    navController: NavHostController,
    modifier: Modifier = Modifier
) {
    NavHost(
        navController = navController,
        startDestination = Routes.Home,
        modifier = modifier
    ) {
        composable(Routes.Home) {
            HomeScreen(
                onOpenWork = { navController.navigate(Routes.WorkDetail) },
                onOpenLibrary = { navController.navigate(Routes.Library) }
            )
        }
        composable(Routes.Library) {
            LibraryScreen(
                onOpenWork = { navController.navigate(Routes.WorkDetail) },
                onOpenReader = { navController.navigate(Routes.Reader) }
            )
        }
        composable(Routes.Browse) {
            BrowseScreen(
                onOpenSearch = { navController.navigate(Routes.Search) },
                onOpenWork = { navController.navigate(Routes.WorkDetail) }
            )
        }
        composable(Routes.Account) {
            AccountScreen(
                onOpenBackup = { navController.navigate(Routes.Backup) },
                onOpenSettings = { navController.navigate(Routes.Settings) }
            )
        }
        composable(Routes.Search) {
            SearchScreen(onOpenWork = { navController.navigate(Routes.WorkDetail) })
        }
        composable(Routes.WorkDetail) {
            WorkDetailScreen(onOpenReader = { navController.navigate(Routes.Reader) })
        }
        composable(Routes.Reader) {
            ReaderPlaceholderScreen(onBack = { navController.popBackStack() })
        }
        composable(Routes.Settings) {
            SettingsScreen(onOpenBackup = { navController.navigate(Routes.Backup) })
        }
        composable(Routes.Backup) {
            BackupScreen()
        }
    }
}
