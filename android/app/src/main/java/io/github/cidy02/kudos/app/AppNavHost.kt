package io.github.cidy02.kudos.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.compose.runtime.collectAsState
import io.github.cidy02.kudos.account.AO3CollectionsScreen
import io.github.cidy02.kudos.account.AO3DashboardScreen
import io.github.cidy02.kudos.account.AboutScreen
import io.github.cidy02.kudos.account.AccountListScreen
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.account.AccountScreen
import io.github.cidy02.kudos.account.LocalLibraryListKind
import io.github.cidy02.kudos.account.LocalLibraryListsScreen
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.AO3WebLoginScreen
import io.github.cidy02.kudos.auth.usernameOrNull
import io.github.cidy02.kudos.author.AuthorWorksScreen
import io.github.cidy02.kudos.backup.BackupScreen
import io.github.cidy02.kudos.browse.BrowseScreen
import io.github.cidy02.kudos.browse.FandomListScreen
import io.github.cidy02.kudos.browse.FandomWorksScreen
import io.github.cidy02.kudos.comments.CommentsScreen
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.home.HomeScreen
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.web.AO3WebViewFallbackScreen
import io.github.cidy02.kudos.library.CollectionDetailScreen
import io.github.cidy02.kudos.library.CollectionsScreen
import io.github.cidy02.kudos.library.LibraryScreen
import io.github.cidy02.kudos.library.RecentlyDeletedScreen
import io.github.cidy02.kudos.library.QueueDetailScreen
import io.github.cidy02.kudos.library.ReadingQueuesScreen
import io.github.cidy02.kudos.library.ReadingStatisticsScreen
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
    // The only state left here (T-90): a small id-keyed cache so opening Work
    // Detail from a search/browse/account-list result still shows instantly
    // from the AO3WorkSummary already in hand, without carrying the full
    // object through the route itself. Keyed by AO3 work id, so unlike the
    // single shared vars this replaced, two different works never collide -
    // an older back-stack entry's lookup by its own id is unaffected by a
    // newer entry adding a different id. A miss (evicted, or reached another
    // way) just falls back to the same AO3 fetch WorkDetailSource.Ao3WorkId
    // already does.
    val remoteSummaryCache = remember { mutableMapOf<Long, AO3WorkSummary>() }

    fun navigateToWorkDetail(source: WorkDetailSource) {
        if (source is WorkDetailSource.RemoteSummary) {
            remoteSummaryCache[source.summary.id] = source.summary
        }
        navController.navigate(Routes.workDetail(NavArgCodecs.encodeWorkDetailSource(source)))
    }

    fun resolveWorkDetailSource(encoded: String): WorkDetailSource? {
        val decoded = NavArgCodecs.decodeWorkDetailSource(encoded) ?: return null
        if (decoded is WorkDetailSource.Ao3WorkId) {
            remoteSummaryCache[decoded.workId]?.let { return WorkDetailSource.RemoteSummary(it) }
        }
        return decoded
    }

    NavHost(
        navController = navController,
        startDestination = Routes.Home,
        modifier = modifier
    ) {
        composable(Routes.Home) {
            HomeScreen(
                libraryRepository = container.libraryRepository,
                workRepository = container.workRepository,
                metadataRepository = container.metadataRepository,
                authRepository = container.authRepository,
                accountListRepository = container.accountListRepository,
                privacyGate = container.privacyGate,
                onOpenWork = { workId ->
                    navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                },
                onOpenReader = { workId ->
                    navController.navigate(Routes.reader(workId))
                },
                onOpenRemoteWork = { summary ->
                    navigateToWorkDetail(WorkDetailSource.RemoteSummary(summary))
                },
                onOpenSubscriptionsList = {
                    navController.navigate(
                        Routes.accountList(
                            NavArgCodecs.encodeAccountListType(AccountListType.Subscriptions)
                        )
                    )
                },
                onOpenLibrary = { navController.navigate(Routes.Library) },
                onOpenBrowse = { navController.navigate(Routes.Browse) }
            )
        }
        composable(Routes.Library) {
            LibraryScreen(
                repository = container.libraryRepository,
                workRepository = container.workRepository,
                settingsRepository = container.settingsRepository,
                queueRepository = container.readingQueueRepository,
                privacyGate = container.privacyGate,
                onOpenWork = { workId ->
                    navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                },
                onOpenReader = { workId ->
                    navController.navigate(Routes.reader(workId))
                },
                onOpenRecentlyDeleted = { navController.navigate(Routes.RecentlyDeleted) },
                onOpenReadingQueues = { navController.navigate(Routes.ReadingQueues) },
                onOpenReadingStatistics = { navController.navigate(Routes.ReadingStatistics) },
                onOpenCollections = { navController.navigate(Routes.Collections) },
                onOpenQueue = { queueId ->
                    navController.navigate(Routes.queueDetail(queueId))
                },
                onOpenCollection = { collectionId ->
                    navController.navigate(Routes.collectionDetail(collectionId))
                },
                onOpenComments = { workId ->
                    navController.navigate(Routes.comments(workId))
                }
            )
        }
        composable(Routes.Collections) {
            CollectionsScreen(
                workRepository = container.workRepository,
                onOpenCollection = { collectionId ->
                    navController.navigate(Routes.collectionDetail(collectionId))
                }
            )
        }
        composable(
            Routes.CollectionDetail,
            arguments = listOf(Routes.navArgOf("collectionId"))
        ) { backStackEntry ->
            val collectionId = Routes.routeArg(backStackEntry, "collectionId")
            if (collectionId == null) {
                navController.popBackStack()
            } else {
                CollectionDetailScreen(
                    collectionId = collectionId,
                    workRepository = container.workRepository,
                    settingsRepository = container.settingsRepository,
                    privacyGate = container.privacyGate,
                    onOpenWork = { workId ->
                        navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                    },
                    onOpenReader = { workId ->
                        navController.navigate(Routes.reader(workId))
                    },
                    onCollectionDeleted = { navController.popBackStack() }
                )
            }
        }
        composable(Routes.ReadingQueues) {
            ReadingQueuesScreen(
                repository = container.readingQueueRepository,
                onOpenQueue = { queueId ->
                    navController.navigate(Routes.queueDetail(queueId))
                }
            )
        }
        composable(
            Routes.QueueDetail,
            arguments = listOf(Routes.navArgOf("queueId"))
        ) { backStackEntry ->
            val queueId = Routes.routeArg(backStackEntry, "queueId")
            if (queueId == null) {
                navController.popBackStack()
            } else {
                QueueDetailScreen(
                    queueId = queueId,
                    repository = container.readingQueueRepository,
                    onOpenWork = { workId ->
                        navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                    }
                )
            }
        }
        composable(Routes.Browse) {
            BrowseScreen(
                repository = container.browseRepository,
                workRepository = container.workRepository,
                onOpenCategory = { category ->
                    navController.navigate(Routes.browseFandoms(category.name, category.fandomsPath))
                },
                onOpenFandom = { fandomName ->
                    navController.navigate(Routes.browseWorks(fandomName))
                },
                onOpenWebFallback = { url ->
                    navController.navigate(Routes.webFallback(url))
                }
            )
        }
        composable(
            Routes.BrowseFandoms,
            arguments = listOf(
                Routes.navArgOf("categoryName"),
                Routes.navArgOf("categoryFandomsPath")
            )
        ) { backStackEntry ->
            val name = Routes.routeArg(backStackEntry, "categoryName")
            val fandomsPath = Routes.routeArg(backStackEntry, "categoryFandomsPath")
            if (name == null || fandomsPath == null) {
                navController.popBackStack()
            } else {
                FandomListScreen(
                    category = AO3MediaCategory(name = name, fandomsPath = fandomsPath),
                    repository = container.browseRepository,
                    onOpenFandom = { fandom ->
                        navController.navigate(Routes.browseWorks(fandom.name))
                    },
                    onOpenWebFallback = { url ->
                        navController.navigate(Routes.webFallback(url))
                    }
                )
            }
        }
        composable(
            Routes.BrowseWorks,
            arguments = listOf(Routes.navArgOf("fandomName"))
        ) { backStackEntry ->
            val fandomName = Routes.routeArg(backStackEntry, "fandomName")
            if (fandomName.isNullOrBlank()) {
                navController.popBackStack()
            } else {
                FandomWorksScreen(
                    fandomName = fandomName,
                    workRepository = container.workRepository,
                    repository = container.browseRepository,
                    onOpenWork = { work ->
                        navigateToWorkDetail(WorkDetailSource.RemoteSummary(work))
                    }
                )
            }
        }
        composable(
            Routes.WebFallback,
            arguments = listOf(Routes.navArgOf("url"))
        ) { backStackEntry ->
            val url = Routes.routeArg(backStackEntry, "url")
            if (url == null) {
                navController.popBackStack()
            } else {
                val settings by container.settingsRepository.settings.collectAsState(
                    initial = KudosSettings.Defaults
                )
                AO3WebViewFallbackScreen(
                    url = url,
                    appTheme = settings.app.appTheme,
                    onBack = { navController.popBackStack() }
                )
            }
        }
        composable(Routes.Account) {
            AccountScreen(
                authRepository = container.authRepository,
                listRepository = container.accountListRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenList = { type ->
                    navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))
                },
                onOpenBackup = { navController.navigate(Routes.Backup) },
                onOpenSettings = { navController.navigate(Routes.Settings) },
                onOpenCollections = { navController.navigate(Routes.Collections) },
                onOpenAO3Collections = { navController.navigate(Routes.AO3Collections) },
                onOpenDashboard = { navController.navigate(Routes.AO3Dashboard) },
                onOpenLocalHistory = { navController.navigate(Routes.LocalHistory) },
                onOpenLocalFavorites = { navController.navigate(Routes.LocalFavorites) },
                onOpenAbout = { navController.navigate(Routes.About) },
                onOpenPrivacy = { navController.navigate(Routes.Settings) },
                onOpenWeb = { url ->
                    navController.navigate(Routes.webFallback(url))
                },
                onOpenWork = { work ->
                    navigateToWorkDetail(WorkDetailSource.RemoteSummary(work))
                },
                onOpenCollection = { collection ->
                    val type = AccountListType.Collection(
                        name = collection.name,
                        displayTitle = collection.title
                    )
                    navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))
                },
                inboxRepository = container.inboxRepository,
                commentRepository = container.commentRepository,
                onOpenWorkComments = { workId ->
                    // Deliberate simplification: chapter-position rows still open the
                    // work's general thread (Android has no chapter-id resolution from
                    // Inbox subject labels yet — same gap as Comments chapter routing).
                    navController.navigate(Routes.comments(workId))
                }
            )
        }
        composable(Routes.AO3Dashboard) {
            val authState by container.authRepository.state.collectAsState(
                initial = AO3AuthState.Restoring
            )
            val username = (authState as? AO3AuthState.SignedIn)?.username
            AO3DashboardScreen(
                username = username,
                onOpenList = { type ->
                    navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))
                },
                onOpenAO3Collections = { navController.navigate(Routes.AO3Collections) }
            )
        }
        composable(Routes.LocalHistory) {
            LocalLibraryListsScreen(
                kind = LocalLibraryListKind.History,
                repository = container.libraryRepository,
                onOpenWork = { workId ->
                    navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                },
                onOpenReader = { workId ->
                    navController.navigate(Routes.reader(workId))
                }
            )
        }
        composable(Routes.LocalFavorites) {
            LocalLibraryListsScreen(
                kind = LocalLibraryListKind.Favorites,
                repository = container.libraryRepository,
                onOpenWork = { workId ->
                    navigateToWorkDetail(WorkDetailSource.LocalWork(workId))
                },
                onOpenReader = { workId ->
                    navController.navigate(Routes.reader(workId))
                }
            )
        }
        composable(Routes.About) {
            AboutScreen()
        }
        composable(Routes.AccountLogin) {
            AO3WebLoginScreen(
                authRepository = container.authRepository,
                onLoginComplete = { navController.popBackStack(Routes.Account, inclusive = false) },
                onCancel = { navController.popBackStack() }
            )
        }
        composable(Routes.AO3Collections) {
            AO3CollectionsScreen(
                repository = container.accountListRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenCollection = { collection ->
                    val type = AccountListType.Collection(
                        name = collection.name,
                        displayTitle = collection.title
                    )
                    navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))
                }
            )
        }
        composable(
            Routes.AccountList,
            arguments = listOf(Routes.navArgOf("listType"))
        ) { backStackEntry ->
            val type = Routes.routeArg(backStackEntry, "listType")
                ?.let(NavArgCodecs::decodeAccountListType)
            if (type == null) {
                navController.popBackStack()
            } else {
                AccountListScreen(
                    type = type,
                    repository = container.accountListRepository,
                    onLogin = { navController.navigate(Routes.AccountLogin) },
                    onOpenWork = { work ->
                        navigateToWorkDetail(WorkDetailSource.RemoteSummary(work))
                    }
                )
            }
        }
        composable(Routes.Search) {
            SearchScreen(
                onOpenWork = { work ->
                    navigateToWorkDetail(WorkDetailSource.RemoteSummary(work))
                },
                savedSearchRepository = container.savedSearchRepository,
                workRepository = container.workRepository
            )
        }
        composable(
            Routes.WorkDetail,
            arguments = listOf(Routes.navArgOf("workSource"))
        ) { backStackEntry ->
            val source = Routes.routeArg(backStackEntry, "workSource")
                ?.let(::resolveWorkDetailSource)
            WorkDetailScreen(
                source = source,
                workRepository = container.workRepository,
                workImporter = container.workImporter,
                downloadQueue = container.downloadQueue,
                writeRepository = container.writeRepository,
                readingQueueRepository = container.readingQueueRepository,
                metadataRepository = container.metadataRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenComments = { workId ->
                    navController.navigate(Routes.comments(workId))
                },
                onOpenReader = { workId ->
                    navController.navigate(Routes.reader(workId))
                },
                onOpenAuthor = { authorName ->
                    navController.navigate(Routes.authorWorks(authorName))
                }
            )
        }
        composable(
            Routes.AuthorWorks,
            arguments = listOf(Routes.navArgOf("authorName"))
        ) { backStackEntry ->
            val authorName = Routes.routeArg(backStackEntry, "authorName")
            if (authorName.isNullOrBlank()) {
                navController.popBackStack()
            } else {
                AuthorWorksScreen(
                    authorName = authorName,
                    workRepository = container.workRepository,
                    onOpenWork = { work ->
                        navigateToWorkDetail(WorkDetailSource.RemoteSummary(work))
                    }
                )
            }
        }
        composable(
            Routes.Reader,
            arguments = listOf(Routes.navArgOf("workId"))
        ) { backStackEntry ->
            val workId = Routes.routeArg(backStackEntry, "workId")
            if (workId == null) {
                navController.popBackStack()
            } else {
                val readerViewModel: ReaderViewModel = viewModel(
                    key = workId,
                    factory = ReaderViewModel.factory(
                        container.readerRepository,
                        container.settingsRepository,
                        workId
                    )
                )
                ReaderScreen(
                    viewModel = readerViewModel,
                    onBack = { navController.popBackStack() },
                    onOpenComments = { commentsWorkId ->
                        navController.navigate(Routes.comments(commentsWorkId))
                    },
                    onOpenWorkDetail = { ao3WorkId ->
                        // Deep-link hydration from a raw work id is deferred (see HANDOFF),
                        // but keep the route native so the later parser can fill it in.
                        navController.navigate(
                            Routes.workDetail(
                                NavArgCodecs.encodeWorkDetailSource(WorkDetailSource.Ao3WorkId(ao3WorkId))
                            )
                        ) {
                            popUpTo(Routes.Reader) { inclusive = true }
                        }
                    }
                )
            }
        }
        composable(
            Routes.Comments,
            arguments = listOf(Routes.navArgOf("commentWorkId"))
        ) { backStackEntry ->
            val workId = Routes.routeArg(backStackEntry, "commentWorkId")?.toLongOrNull()
            val commentsAuthState by container.authRepository.state.collectAsState(
                initial = AO3AuthState.Restoring
            )
            CommentsScreen(
                target = workId?.let { AO3CommentTarget.Work(it) },
                repository = container.commentRepository,
                currentUsername = commentsAuthState.usernameOrNull,
                onLogin = { navController.navigate(Routes.AccountLogin) }
            )
        }

        composable(Routes.RecentlyDeleted) {
            RecentlyDeletedScreen(
                workRepository = container.workRepository
            )
        }

        composable(Routes.ReadingStatistics) {
            ReadingStatisticsScreen(
                libraryRepository = container.libraryRepository,
                settingsRepository = container.settingsRepository,
                privacyGate = container.privacyGate
            )
        }

        composable(Routes.Settings) {
            SettingsScreen(
                repository = container.settingsRepository,
                customFontRepository = container.customFontRepository,
                authRepository = container.authRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenAbout = { navController.navigate(Routes.About) },
                onOpenBackup = { navController.navigate(Routes.Backup) },
                appUpdateRepository = container.appUpdateRepository,
                workImporter = container.workImporter,
                fandomCatalogCache = container.fandomCatalogCache,
                workRepository = container.workRepository
            )
        }
        composable(Routes.Backup) {
            BackupScreen(repository = container.backupRepository)
        }
    }
}
