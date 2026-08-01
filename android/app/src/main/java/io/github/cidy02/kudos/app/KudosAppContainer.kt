package io.github.cidy02.kudos.app

import android.content.Context
import androidx.room.Room
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.auth.AndroidAO3CookieStore
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.FileAO3SessionStore
import io.github.cidy02.kudos.auth.LiveAO3SessionValidator
import io.github.cidy02.kudos.backup.BackupRepository
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.KudosDatabaseMigrations
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.data.preferences.kudosSettingsDataStore
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import io.github.cidy02.kudos.reader.ReaderRepository
import io.github.cidy02.kudos.search.SavedSearchRepository
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
            .addMigrations(KudosDatabaseMigrations.MIGRATION_1_2)
            .build()
    }

    val workFileStore: WorkFileStore by lazy {
        WorkFileStore(appContext.filesDir.toPath())
    }

    val fontFileStore: FontFileStore by lazy {
        FontFileStore(appContext.filesDir.toPath())
    }

    val ao3Client: OkHttpAO3Client by lazy {
        OkHttpAO3Client()
    }

    val authRepository: AO3AuthRepository by lazy {
        AO3AuthRepository(
            sessionStore = FileAO3SessionStore(appContext),
            cookieStore = AndroidAO3CookieStore(),
            sessionValidator = LiveAO3SessionValidator(client = ao3Client)
        )
    }

    val accountListRepository: AccountListRepository by lazy {
        AccountListRepository(
            client = ao3Client,
            authRepository = authRepository
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

    val commentRepository: AO3CommentRepository by lazy {
        AO3CommentRepository(
            publicClient = ao3Client,
            authenticatedClient = authenticatedClient
        )
    }

    val workRepository: WorkRepository by lazy {
        WorkRepository(database, workFileStore)
    }

    val metadataRepository: AO3WorkMetadataRepository by lazy {
        AO3WorkMetadataRepository(ao3Client)
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

    val downloadQueue: DownloadQueue by lazy {
        DownloadQueue(
            workImporter = workImporter,
            workRepository = workRepository
        )
    }

    val settingsRepository: SettingsRepository by lazy {
        SettingsRepository(appContext.kudosSettingsDataStore)
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
            settingsProvider = { settingsRepository.snapshot() }
        )
    }

    val browseRepository: AO3BrowseRepository by lazy {
        AO3BrowseRepository(client = ao3Client)
    }

    val backupRepository: BackupRepository by lazy {
        BackupRepository(
            database = database,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository
        )
    }

    val savedSearchRepository: SavedSearchRepository by lazy {
        SavedSearchRepository(database.savedSearchDao())
    }
}
