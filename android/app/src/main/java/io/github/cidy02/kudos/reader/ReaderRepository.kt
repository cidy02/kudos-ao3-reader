package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.files.CustomFontRepository
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
 * the repository is unit-testable without a real settings store). Production wiring
 * uses [io.github.cidy02.kudos.data.preferences.SettingsRepository.snapshot] so
 * [open] injects the latest saved `readerFontPt` / theme into [ReaderOpenResult.Success.preferences]
 * via [ReaderSettingsMapper] — the single preference source for the reader (no
 * parallel in-memory preference store).
 */
class ReaderRepository(
    private val workRepository: WorkRepository,
    private val fileStore: WorkFileStore,
    private val settingsProvider: suspend () -> KudosSettings,
    private val customFontRepository: CustomFontRepository? = null,
    private val progressMapper: ReaderProgressMapper = ReaderProgressMapper(),
    private val settingsMapper: ReaderSettingsMapper = ReaderSettingsMapper(),
    private val clock: () -> Instant = { Instant.now() },
    private val customFontsProvider: (suspend () -> List<CustomFont>)? = null,
    private val fontPathResolver: ((String) -> String?)? = null
) {
    /**
     * Resolve a work for reading. On success, [ReaderOpenResult.Success.preferences]
     * is always mapped from the current [settingsProvider] snapshot (DataStore in prod).
     */
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
        val customFonts = customFontsProvider?.invoke()
            ?: customFontRepository?.listImported()
            ?: emptyList()
        val pathResolver = fontPathResolver
            ?: customFontRepository?.let { repo ->
                { fileName ->
                    val fontPath = runCatching { repo.fontPath(fileName) }.getOrNull()
                    if (fontPath != null && java.nio.file.Files.isRegularFile(fontPath)) fontPath.toAbsolutePath().toString() else null
                }
            }
            ?: { fileName ->
                val fontPath = runCatching { fileStore.fontPath(fileName) }.getOrNull()
                if (fontPath != null && java.nio.file.Files.isRegularFile(fontPath)) fontPath.toAbsolutePath().toString() else null
            }

        val preferences = settingsMapper.map(
            reader = settings.reader,
            app = settings.app,
            customFonts = customFonts,
            fontPathResolver = pathResolver
        )

        return ReaderOpenResult.Success(
            work = work,
            epubPath = path,
            restoreTarget = progressMapper.restoreTarget(work),
            preferences = preferences
        )
    }

    /** Persist captured progress; always refreshes fallback fields + lastReadDate. */
    suspend fun saveProgress(workId: String, progress: ReaderProgress): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        return workRepository.upsert(progressMapper.applyProgress(work, progress, clock()))
    }

    suspend fun setFinished(workId: String, finished: Boolean): SavedWork? {
        // Delegates to WorkRepository so free-EPUB-on-finish policy is one place
        // (Apple WorkLifecycle parity).
        return workRepository.setFinished(workId, finished)
    }

    /**
     * Explicitly mark the EPUB file as gone (e.g. after a confirmed FileMissing).
     * Never called automatically; the saved-work record is preserved.
     */
    suspend fun markEpubMissing(workId: String): SavedWork? =
        workRepository.setHasEpub(workId, false)
}
