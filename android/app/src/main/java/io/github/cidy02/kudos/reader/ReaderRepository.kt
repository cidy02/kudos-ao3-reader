package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.works.WorkRepository
import java.time.Instant

/**
 * App-owned reader data layer. Resolves a [SavedWork] to a readable EPUB file +
 * restore target + preferences, and persists progress while preserving all local
 * user state. Knows nothing about Readium types.
 *
 * Settings come from a suspending [settingsProvider] (decoupled from DataStore so
 * the repository is unit-testable without a real settings store).
 */
class ReaderRepository(
    private val workRepository: WorkRepository,
    private val fileStore: WorkFileStore,
    private val settingsProvider: suspend () -> KudosSettings,
    private val progressMapper: ReaderProgressMapper = ReaderProgressMapper(),
    private val settingsMapper: ReaderSettingsMapper = ReaderSettingsMapper(),
    private val clock: () -> Instant = { Instant.now() }
) {
    suspend fun open(workId: String): ReaderOpenResult {
        val work = workRepository.getWork(workId)
            ?: return ReaderOpenResult.Failure(null, ReaderError.WorkNotFound)
        if (!work.hasEpub) return ReaderOpenResult.Failure(work, ReaderError.NotDownloaded)
        if (!fileStore.workEpubExists(workId)) {
            return ReaderOpenResult.Failure(work, ReaderError.FileMissing)
        }
        val path = runCatching { fileStore.workEpubPath(workId) }.getOrNull()
            ?: return ReaderOpenResult.Failure(work, ReaderError.OpenFailed("Invalid work file path."))

        val settings = settingsProvider()
        return ReaderOpenResult.Success(
            work = work,
            epubPath = path,
            restoreTarget = progressMapper.restoreTarget(work),
            preferences = settingsMapper.map(settings.reader, settings.app)
        )
    }

    /** Persist captured progress; always refreshes fallback fields + lastReadDate. */
    suspend fun saveProgress(workId: String, progress: ReaderProgress): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        return workRepository.upsert(progressMapper.applyProgress(work, progress, clock()))
    }

    suspend fun setFinished(workId: String, finished: Boolean): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        if (work.isFinished == finished) return work
        return workRepository.upsert(work.copy(isFinished = finished))
    }

    /**
     * Explicitly mark the EPUB file as gone (e.g. after a confirmed FileMissing).
     * Never called automatically; the saved-work record is preserved.
     */
    suspend fun markEpubMissing(workId: String): SavedWork? =
        workRepository.setHasEpub(workId, false)
}
