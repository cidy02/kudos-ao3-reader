package io.github.cidy02.kudos.app

import android.content.Context
import androidx.room.Room
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.data.preferences.kudosSettingsDataStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.reader.ReaderRepository
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository

class KudosAppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: KudosDatabase by lazy {
        Room.databaseBuilder(
            appContext,
            KudosDatabase::class.java,
            KudosDatabase.DatabaseName
        ).build()
    }

    val workFileStore: WorkFileStore by lazy {
        WorkFileStore(appContext.filesDir.toPath())
    }

    val ao3Client: OkHttpAO3Client by lazy {
        OkHttpAO3Client()
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

    val settingsRepository: SettingsRepository by lazy {
        SettingsRepository(appContext.kudosSettingsDataStore)
    }

    val libraryRepository: LibraryRepository by lazy {
        LibraryRepository(workRepository, settingsRepository.settings)
    }

    val readerRepository: ReaderRepository by lazy {
        ReaderRepository(
            workRepository = workRepository,
            fileStore = workFileStore,
            settingsProvider = { settingsRepository.snapshot() }
        )
    }
}
