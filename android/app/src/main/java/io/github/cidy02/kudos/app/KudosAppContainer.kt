package io.github.cidy02.kudos.app

import android.content.Context
import androidx.room.Room
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.account.AO3AccountListCountsCache
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.auth.AndroidAO3CookieStore
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3PostingPseudStore
import io.github.cidy02.kudos.auth.EncryptedFileAO3SessionStore
import io.github.cidy02.kudos.auth.LiveAO3SessionValidator
import io.github.cidy02.kudos.backup.BackupRepository
import io.github.cidy02.kudos.backup.SyncRepository
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.KudosDatabaseMigrations
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.data.preferences.kudosSettingsDataStore
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.CommentCache
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import io.github.cidy02.kudos.network.ao3.comments.commentDraftDataStore
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.github.GitHubReleaseClient
import io.github.cidy02.kudos.reader.ReaderRepository
import io.github.cidy02.kudos.search.SavedSearchRepository
import io.github.cidy02.kudos.update.AppUpdateInstaller
import io.github.cidy02.kudos.update.AppUpdateNotifier
import io.github.cidy02.kudos.update.AppUpdatePreferences
import io.github.cidy02.kudos.update.AppUpdateRepository
import io.github.cidy02.kudos.update.AppVersion
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository

class KudosAppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: KudosDatabase by lazy {
        Room.databaseBuilder(
            appContext,
            KudosDatabase::class.java,
            KudosDatabase.DatabaseName
        )
            .addMigrations(
                KudosDatabaseMigrations.MIGRATION_1_2,
                KudosDatabaseMigrations.MIGRATION_2_3,
                KudosDatabaseMigrations.MIGRATION_3_4,
                KudosDatabaseMigrations.MIGRATION_4_5,
                KudosDatabaseMigrations.MIGRATION_5_6,
                KudosDatabaseMigrations.MIGRATION_6_7
            )
            .build()
    }

    val workFileStore: WorkFileStore by lazy {
        WorkFileStore(appContext.filesDir.toPath())
    }

    val fontFileStore: FontFileStore by lazy {
        FontFileStore(appContext.filesDir.toPath())
    }

    val settingsRepository: SettingsRepository by lazy {
        SettingsRepository(appContext.kudosSettingsDataStore)
    }

    /** One shared instance app-wide — see PrivacyGate's doc comment for why. */
    val privacyGate: PrivacyGate by lazy { PrivacyGate() }

    val customFontRepository: CustomFontRepository by lazy {
        CustomFontRepository(
            customFontDao = database.customFontDao(),
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository
        )
    }

    val ao3Client: OkHttpAO3Client by lazy {
        OkHttpAO3Client()
    }

    val authRepository: AO3AuthRepository by lazy {
        AO3AuthRepository(
            sessionStore = EncryptedFileAO3SessionStore(appContext),
            cookieStore = AndroidAO3CookieStore(),
            sessionValidator = LiveAO3SessionValidator(client = ao3Client)
        )
    }

    val accountListRepository: AccountListRepository by lazy {
        AccountListRepository(
            client = ao3Client,
            authRepository = authRepository,
            settingsRepository = settingsRepository,
            countsCache = accountListCountsCache
        )
    }

    val authenticatedClient: AO3AuthenticatedClient by lazy {
        DefaultAO3AuthenticatedClient(
            getClient = ao3Client,
            postClient = ao3Client,
            authRepository = authRepository
        )
    }

    val writeRepository: AO3WriteRepository by lazy {
        AO3WriteRepository(authenticatedClient)
    }

    val authorRepository: AO3AuthorRepository by lazy {
        AO3AuthorRepository(
            publicClient = ao3Client,
            authenticatedClient = authenticatedClient
        )
    }

    val preferencesRepository: AO3PreferencesRepository by lazy {
        AO3PreferencesRepository(client = authenticatedClient)
    }

    val postingPseudStore: AO3PostingPseudStore by lazy {
        AO3PostingPseudStore(appContext)
    }

    val accountListCountsCache: AO3AccountListCountsCache by lazy {
        AO3AccountListCountsCache()
    }

    val commentRepository: AO3CommentRepository by lazy {
        AO3CommentRepository(
            publicClient = ao3Client,
            authenticatedClient = authenticatedClient,
            pseudStore = postingPseudStore,
            cache = CommentCache(appContext!!)
        )
    }

    val commentDraftStore: CommentDraftStore by lazy {
        CommentDraftStore(appContext.commentDraftDataStore)
    }

    val inboxRepository: AO3InboxRepository by lazy {
        AO3InboxRepository(authenticatedClient)
    }

    val tagAutocompleteRepository: io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository by lazy {
        io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository(ao3Client)
    }

    val searchRepository: AO3SearchRepository by lazy {
        AO3SearchRepository(ao3Client)
    }

    val workRepository: WorkRepository by lazy {
        WorkRepository(database, workFileStore, tagsRepository)
    }

    val metadataRepository: AO3WorkMetadataRepository by lazy {
        AO3WorkMetadataRepository(ao3Client)
    }

    val tagsRepository: io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository by lazy {
        io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository(ao3Client)
    }

    val epubDownloader: AO3EpubDownloader by lazy {
        AO3EpubDownloader(ao3Client)
    }

    val workImporter: WorkImporter by lazy {
        WorkImporter(
            workRepository = workRepository,
            metadataRepository = metadataRepository,
            downloader = epubDownloader,
            fileStore = workFileStore
        )
    }

    val seriesRepository: AO3SeriesRepository by lazy {
        AO3SeriesRepository(client = ao3Client)
    }

    val downloadQueue: DownloadQueue by lazy {
        DownloadQueue(
            workImporter = workImporter,
            workRepository = workRepository,
            seriesRepository = seriesRepository
        )
    }

    val libraryRepository: LibraryRepository by lazy {
        LibraryRepository(workRepository, settingsRepository.settings)
    }

    val readingQueueRepository: ReadingQueueRepository by lazy {
        ReadingQueueRepository(database)
    }

    val readerRepository: ReaderRepository by lazy {
        ReaderRepository(
            workRepository = workRepository,
            fileStore = workFileStore,
            settingsProvider = { settingsRepository.snapshot() },
            customFontRepository = customFontRepository
        )
    }

    val annotationRepository: io.github.cidy02.kudos.reader.AnnotationRepository by lazy {
        io.github.cidy02.kudos.reader.AnnotationRepository(database.annotationDao())
    }

    val fandomCatalogCache: FandomCatalogCache by lazy {
        FandomCatalogCache(appContext.cacheDir.toPath())
    }

    val persistenceGate: io.github.cidy02.kudos.backup.PersistenceGate by lazy {
        io.github.cidy02.kudos.backup.PersistenceGate()
    }

    val browseRepository: AO3BrowseRepository by lazy {
        AO3BrowseRepository(client = ao3Client, cache = fandomCatalogCache)
    }

    val backupRepository: BackupRepository by lazy {
        BackupRepository(
            database = database,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository,
            persistenceGate = persistenceGate
        )
    }

    val syncRepository: SyncRepository by lazy {
        SyncRepository(
            context = appContext!!,
            settingsRepository = settingsRepository,
            backupRepository = backupRepository,
            workFileStore = workFileStore
        )
    }

    val databaseChangeTracker: io.github.cidy02.kudos.backup.DatabaseChangeTracker by lazy {
        io.github.cidy02.kudos.backup.DatabaseChangeTracker(
            database = database,
            settingsRepository = settingsRepository,
            appScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO)
        )
    }

    val savedSearchRepository: SavedSearchRepository by lazy {
        SavedSearchRepository(database.savedSearchDao())
    }

    val gitHubReleaseClient: GitHubReleaseClient by lazy {
        GitHubReleaseClient(appVersionForUserAgent = BuildConfig.VERSION_NAME)
    }

    val appUpdateInstaller: AppUpdateInstaller by lazy {
        AppUpdateInstaller(appContext)
    }

    val appUpdateNotifier: AppUpdateNotifier by lazy {
        AppUpdateNotifier(appContext)
    }

    val appUpdatePreferences: AppUpdatePreferences by lazy {
        AppUpdatePreferences(appContext.kudosSettingsDataStore)
    }

    val appUpdateRepository: AppUpdateRepository by lazy {
        AppUpdateRepository(
            releaseClient = gitHubReleaseClient,
            installer = appUpdateInstaller,
            notifier = appUpdateNotifier,
            preferences = appUpdatePreferences,
            currentVersion = AppVersion.parse(BuildConfig.VERSION_NAME)
                ?: error("BuildConfig.VERSION_NAME (${BuildConfig.VERSION_NAME}) is not a valid X.Y.Z version.")
        )
    }
}
