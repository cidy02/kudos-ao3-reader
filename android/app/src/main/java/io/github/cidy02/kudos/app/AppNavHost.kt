package io.github.cidy02.kudos.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import io.github.cidy02.kudos.account.AccountScreen
import io.github.cidy02.kudos.backup.BackupScreen
import io.github.cidy02.kudos.browse.BrowseScreen
import io.github.cidy02.kudos.home.HomeScreen
import io.github.cidy02.kudos.library.LibraryScreen
import io.github.cidy02.kudos.reader.ReaderScreen
import io.github.cidy02.kudos.reader.ReaderViewModel
import io.github.cidy02.kudos.search.SearchScreen
import io.github.cidy02.kudos.settings.SettingsScreen
import io.github.cidy02.kudos.works.WorkDetailScreen
import io.github.cidy02.kudos.works.WorkDetailSource

@Composable
fun AppNavHost(
    container: KudosAppContainer,
    navController: NavHostController,
    modifier: Modifier = Modifier
) {
    var selectedWorkSource by remember { mutableStateOf<WorkDetailSource?>(null) }
    var readerWorkId by remember { mutableStateOf<String?>(null) }

    NavHost(
        navController = navController,
        startDestination = Routes.Home,
        modifier = modifier
    ) {
        composable(Routes.Home) {
            HomeScreen(
                onOpenWork = {
                    selectedWorkSource = null
                    navController.navigate(Routes.WorkDetail)
                },
                onOpenLibrary = { navController.navigate(Routes.Library) }
            )
        }
        composable(Routes.Library) {
            LibraryScreen(
                repository = container.libraryRepository,
                onOpenWork = { workId ->
                    selectedWorkSource = WorkDetailSource.LocalWork(workId)
                    navController.navigate(Routes.WorkDetail)
                }
            )
        }
        composable(Routes.Browse) {
            BrowseScreen(
                onOpenSearch = { navController.navigate(Routes.Search) },
                onOpenWork = {
                    selectedWorkSource = null
                    navController.navigate(Routes.WorkDetail)
                }
            )
        }
        composable(Routes.Account) {
            AccountScreen(
                onOpenBackup = { navController.navigate(Routes.Backup) },
                onOpenSettings = { navController.navigate(Routes.Settings) }
            )
        }
        composable(Routes.Search) {
            SearchScreen(
                onOpenWork = { work ->
                    selectedWorkSource = WorkDetailSource.RemoteSummary(work)
                    navController.navigate(Routes.WorkDetail)
                }
            )
        }
        composable(Routes.WorkDetail) {
            WorkDetailScreen(
                source = selectedWorkSource,
                workRepository = container.workRepository,
                workImporter = container.workImporter,
                onOpenReader = { workId ->
                    readerWorkId = workId
                    navController.navigate(Routes.Reader)
                }
            )
        }
        composable(Routes.Reader) {
            val workId = readerWorkId
            if (workId == null) {
                navController.popBackStack()
            } else {
                val readerViewModel: ReaderViewModel = viewModel(
                    key = workId,
                    factory = ReaderViewModel.factory(container.readerRepository, workId)
                )
                ReaderScreen(
                    viewModel = readerViewModel,
                    onBack = { navController.popBackStack() },
                    onOpenWorkDetail = { workId ->
                        // Deep-link hydration from a raw work id is deferred (see HANDOFF),
                        // but keep the route native so the later parser can fill it in.
                        selectedWorkSource = WorkDetailSource.Ao3WorkId(workId)
                        navController.navigate(Routes.WorkDetail) {
                            popUpTo(Routes.Reader) { inclusive = true }
                        }
                    }
                )
            }
        }
        composable(Routes.Settings) {
            SettingsScreen(onOpenBackup = { navController.navigate(Routes.Backup) })
        }
        composable(Routes.Backup) {
            BackupScreen()
        }
    }
}
