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
import io.github.cidy02.kudos.home.HomeScreen
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
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
    var selectedWorkSource by remember { mutableStateOf<WorkDetailSource?>(null) }
    var readerWorkId by remember { mutableStateOf<String?>(null) }
    var selectedAccountListType by remember { mutableStateOf<AccountListType?>(null) }
    var selectedCommentTarget by remember { mutableStateOf<AO3CommentTarget?>(null) }
    var selectedBrowseCategory by remember { mutableStateOf<AO3MediaCategory?>(null) }
    var selectedBrowseFandom by remember { mutableStateOf<AO3Fandom?>(null) }
    var webFallbackUrl by remember { mutableStateOf<String?>(null) }
    var selectedQueueId by remember { mutableStateOf<String?>(null) }
    var selectedCollectionId by remember { mutableStateOf<String?>(null) }
    var selectedAuthorName by remember { mutableStateOf<String?>(null) }

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
                    selectedWorkSource = WorkDetailSource.LocalWork(workId)
                    navController.navigate(Routes.WorkDetail)
                },
                onOpenReader = { workId ->
                    readerWorkId = workId
                    navController.navigate(Routes.Reader)
                },
                onOpenRemoteWork = { summary ->
                    selectedWorkSource = WorkDetailSource.RemoteSummary(summary)
                    navController.navigate(Routes.WorkDetail)
                },
                onOpenSubscriptionsList = {
                    selectedAccountListType = AccountListType.Subscriptions
                    navController.navigate(Routes.AccountList)
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
                    selectedWorkSource = WorkDetailSource.LocalWork(workId)
                    navController.navigate(Routes.WorkDetail)
                },
                onOpenReader = { workId ->
                    readerWorkId = workId
                    navController.navigate(Routes.Reader)
                },
                onOpenRecentlyDeleted = { navController.navigate(Routes.RecentlyDeleted) },
                onOpenReadingQueues = { navController.navigate(Routes.ReadingQueues) },
                onOpenReadingStatistics = { navController.navigate(Routes.ReadingStatistics) },
                onOpenCollections = { navController.navigate(Routes.Collections) },
                onOpenQueue = { queueId ->
                    selectedQueueId = queueId
                    navController.navigate(Routes.QueueDetail)
                },
                onOpenCollection = { collectionId ->
                    selectedCollectionId = collectionId
                    navController.navigate(Routes.CollectionDetail)
                },
                onOpenComments = { workId ->
                    selectedCommentTarget = AO3CommentTarget.Work(workId)
                    navController.navigate(Routes.Comments)
                }
            )
        }
        composable(Routes.Collections) {
            CollectionsScreen(
                workRepository = container.workRepository,
                onOpenCollection = { collectionId ->
                    selectedCollectionId = collectionId
                    navController.navigate(Routes.CollectionDetail)
                }
            )
        }
        composable(Routes.CollectionDetail) {
            val collectionId = selectedCollectionId
            if (collectionId == null) {
                navController.popBackStack()
            } else {
                CollectionDetailScreen(
                    collectionId = collectionId,
                    workRepository = container.workRepository,
                    settingsRepository = container.settingsRepository,
                    privacyGate = container.privacyGate,
                    onOpenWork = { workId ->
                        selectedWorkSource = WorkDetailSource.LocalWork(workId)
                        navController.navigate(Routes.WorkDetail)
                    },
                    onOpenReader = { workId ->
                        readerWorkId = workId
                        navController.navigate(Routes.Reader)
                    },
                    onCollectionDeleted = {
                        selectedCollectionId = null
                        navController.popBackStack()
                    }
                )
            }
        }
        composable(Routes.ReadingQueues) {
            ReadingQueuesScreen(
                repository = container.readingQueueRepository,
                onOpenQueue = { queueId ->
                    selectedQueueId = queueId
                    navController.navigate(Routes.QueueDetail)
                }
            )
        }
        composable(Routes.QueueDetail) {
            val queueId = selectedQueueId
            if (queueId == null) {
                navController.popBackStack()
            } else {
                QueueDetailScreen(
                    queueId = queueId,
                    repository = container.readingQueueRepository,
                    onOpenWork = { workId ->
                        selectedWorkSource = WorkDetailSource.LocalWork(workId)
                        navController.navigate(Routes.WorkDetail)
                    }
                )
            }
        }
        composable(Routes.Browse) {
            BrowseScreen(
                repository = container.browseRepository,
                workRepository = container.workRepository,
                onOpenCategory = { category ->
                    selectedBrowseCategory = category
                    navController.navigate(Routes.BrowseFandoms)
                },
                onOpenFandom = { fandomName ->
                    selectedBrowseFandom = AO3Fandom(name = fandomName)
                    navController.navigate(Routes.BrowseWorks)
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
                    }
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
                    }
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
                listRepository = container.accountListRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenList = { type ->
                    selectedAccountListType = type
                    navController.navigate(Routes.AccountList)
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
                    webFallbackUrl = url
                    navController.navigate(Routes.WebFallback)
                },
                onOpenWork = { work ->
                    selectedWorkSource = WorkDetailSource.RemoteSummary(work)
                    navController.navigate(Routes.WorkDetail)
                },
                onOpenCollection = { collection ->
                    selectedAccountListType = AccountListType.Collection(
                        name = collection.name,
                        displayTitle = collection.title
                    )
                    navController.navigate(Routes.AccountList)
                },
                inboxRepository = container.inboxRepository,
                commentRepository = container.commentRepository,
                onOpenWorkComments = { workId ->
                    // Deliberate simplification: chapter-position rows still open the
                    // work's general thread (Android has no chapter-id resolution from
                    // Inbox subject labels yet — same gap as Comments chapter routing).
                    selectedCommentTarget = AO3CommentTarget.Work(workId)
                    navController.navigate(Routes.Comments)
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
                    selectedAccountListType = type
                    navController.navigate(Routes.AccountList)
                },
                onOpenAO3Collections = { navController.navigate(Routes.AO3Collections) }
            )
        }
        composable(Routes.LocalHistory) {
            LocalLibraryListsScreen(
                kind = LocalLibraryListKind.History,
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
        composable(Routes.LocalFavorites) {
            LocalLibraryListsScreen(
                kind = LocalLibraryListKind.Favorites,
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
                    selectedAccountListType = AccountListType.Collection(
                        name = collection.name,
                        displayTitle = collection.title
                    )
                    navController.navigate(Routes.AccountList)
                }
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
                },
                savedSearchRepository = container.savedSearchRepository,
                workRepository = container.workRepository
            )
        }
        composable(Routes.WorkDetail) {
            WorkDetailScreen(
                source = selectedWorkSource,
                workRepository = container.workRepository,
                workImporter = container.workImporter,
                downloadQueue = container.downloadQueue,
                writeRepository = container.writeRepository,
                readingQueueRepository = container.readingQueueRepository,
                metadataRepository = container.metadataRepository,
                onLogin = { navController.navigate(Routes.AccountLogin) },
                onOpenComments = { workId ->
                    selectedCommentTarget = AO3CommentTarget.Work(workId)
                    navController.navigate(Routes.Comments)
                },
                onOpenReader = { workId ->
                    readerWorkId = workId
                    navController.navigate(Routes.Reader)
                },
                onOpenAuthor = { authorName ->
                    selectedAuthorName = authorName
                    navController.navigate(Routes.AuthorWorks)
                }
            )
        }
        composable(Routes.AuthorWorks) {
            val authorName = selectedAuthorName
            if (authorName.isNullOrBlank()) {
                navController.popBackStack()
            } else {
                AuthorWorksScreen(
                    authorName = authorName,
                    workRepository = container.workRepository,
                    onOpenWork = { work ->
                        selectedWorkSource = WorkDetailSource.RemoteSummary(work)
                        navController.navigate(Routes.WorkDetail)
                    }
                )
            }
        }
        composable(Routes.Reader) {
            val workId = readerWorkId
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
            val commentsAuthState by container.authRepository.state.collectAsState(
                initial = AO3AuthState.Restoring
            )
            CommentsScreen(
                target = selectedCommentTarget,
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
                appUpdateRepository = container.appUpdateRepository
            )
        }
        composable(Routes.Backup) {
            BackupScreen(repository = container.backupRepository)
        }
    }
}
