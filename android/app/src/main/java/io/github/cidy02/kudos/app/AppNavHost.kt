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
import io.github.cidy02.kudos.account.AccountListScreen
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.account.AccountScreen
import io.github.cidy02.kudos.auth.AO3WebLoginScreen
import io.github.cidy02.kudos.backup.BackupScreen
import io.github.cidy02.kudos.browse.BrowseScreen
import io.github.cidy02.kudos.browse.FandomListScreen
import io.github.cidy02.kudos.browse.FandomWorksScreen
import io.github.cidy02.kudos.comments.CommentsScreen
import io.github.cidy02.kudos.home.HomeScreen
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.web.AO3WebViewFallbackScreen
import io.github.cidy02.kudos.library.LibraryScreen
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
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
    var selectedAccountListType by remember { mutableStateOf<AccountListType?>(null) }
    var selectedCommentTarget by remember { mutableStateOf<AO3CommentTarget?>(null) }
    var selectedBrowseCategory by remember { mutableStateOf<AO3MediaCategory?>(null) }
    var selectedBrowseFandom by remember { mutableStateOf<AO3Fandom?>(null) }
    var webFallbackUrl by remember { mutableStateOf<String?>(null) }

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
                },
                onOpenReader = { workId ->
                    readerWorkId = workId
                    navController.navigate(Routes.Reader)
                }
            )
        }
        composable(Routes.Browse) {
            BrowseScreen(
                repository = container.browseRepository,
                onOpenCategory = { category ->
                    selectedBrowseCategory = category
                    navController.navigate(Routes.BrowseFandoms)
                },
                onOpenWebFallback = { url ->
                    webFallbackUrl = url
                    navController.navigate(Routes.WebFallback)
                }
            )
        }
        composable(Routes.BrowseFandoms) {
            val category = selectedBrowseCategory
            if (category == null) {
                navController.popBackStack()
            } else {
                FandomListScreen(
                    category = category,
                    repository = container.browseRepository,
                    onOpenFandom = { fandom ->
                        selectedBrowseFandom = fandom
                        navController.navigate(Routes.BrowseWorks)
                    },
                    onOpenWebFallback = { url ->
                        webFallbackUrl = url
                        navController.navigate(Routes.WebFallback)
                    },
                    onBack = { navController.popBackStack() }
                )
            }
        }
        composable(Routes.BrowseWorks) {
            val fandom = selectedBrowseFandom
            if (fandom == null) {
                navController.popBackStack()
            } else {
                FandomWorksScreen(
                    fandomName = fandom.name,
                    workRepository = container.workRepository,
                    repository = container.browseRepository,
                    onOpenWork = { work ->
                        selectedWorkSource = WorkDetailSource.RemoteSummary(work)
                        navController.navigate(Routes.WorkDetail)
                    },
                    onBack = { navController.popBackStack() }
                )
            }
        }
        composable(Routes.WebFallback) {
            val url = webFallbackUrl
            if (url == null) {
                navController.popBackStack()
            } else {
                AO3WebViewFallbackScreen(
                    url = url,
                    onBack = { navController.popBackStack() }
                )
            }
        }
        composable(Routes.Account) {
            AccountScreen(
                authRepository = container.authRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenList = { type ->
                    selectedAccountListType = type
                    navController.navigate(Routes.AccountList)
                },
                onOpenBackup = { navController.navigate(Routes.Backup) },
                onOpenSettings = { navController.navigate(Routes.Settings) }
            )
        }
        composable(Routes.AccountLogin) {
            AO3WebLoginScreen(
                authRepository = container.authRepository,
                onLoginComplete = { navController.popBackStack(Routes.Account, inclusive = false) },
                onCancel = { navController.popBackStack() }
            )
        }
        composable(Routes.AccountList) {
            val type = selectedAccountListType
            if (type == null) {
                navController.popBackStack()
            } else {
                AccountListScreen(
                    type = type,
                    repository = container.accountListRepository,
                    onLogin = { navController.navigate(Routes.AccountLogin) },
                    onOpenWork = { work ->
                        selectedWorkSource = WorkDetailSource.RemoteSummary(work)
                        navController.navigate(Routes.WorkDetail)
                    }
                )
            }
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
                writeRepository = container.writeRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenComments = { workId ->
                    selectedCommentTarget = AO3CommentTarget.Work(workId)
                    navController.navigate(Routes.Comments)
                },
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
                    onOpenComments = { workId ->
                        selectedCommentTarget = AO3CommentTarget.Work(workId)
                        navController.navigate(Routes.Comments)
                    },
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
        composable(Routes.Comments) {
            CommentsScreen(
                target = selectedCommentTarget,
                repository = container.commentRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) }
            )
        }
        composable(Routes.Settings) {
            SettingsScreen(onOpenBackup = { navController.navigate(Routes.Backup) })
        }
        composable(Routes.Backup) {
            BackupScreen()
        }
    }
}
