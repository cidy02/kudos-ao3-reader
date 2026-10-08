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
    private val progressGate: ReaderProgressGate = ReaderProgressGate(),
    private val settingsMapper: ReaderSettingsMapper = ReaderSettingsMapper(),
    private val clock: () -> Instant = { Instant.now() },
    private val customFontsProvider: (suspend () -> List<CustomFont>)? = null,
    private val fontPathResolver: ((String) -> String?)? = null
) {
    suspend fun currentWork(workId: String): SavedWork? = workRepository.getWork(workId)

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
        var openedWork = workRepository.releaseHeldCopy(workId) ?: work
        if (settings.app.keepsWorksYouRead && !openedWork.isSaved) {
            openedWork = workRepository.setSaved(workId, true) ?: openedWork
        }
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

        // iOS `ReadiumSessionStamp.noteOpened`: Continue Reading dates only.
        // The stored fraction (including a macOS percent) stays put.
        val now = clock()
        val stamped = workRepository.upsert(
            openedWork.copy(
                lastReadDate = now,
                progressModifiedAt = now,
                lastModifiedAt = now,
                hiddenFromHistoryAt = null
            )
        )
        progressGate.seed(workId, stamped)

        return ReaderOpenResult.Success(
            work = stamped,
            epubPath = path,
            restoreTarget = progressMapper.restoreTarget(stamped),
            preferences = preferences
        )
    }

    /**
     * Navigator location. The open landing and sub-threshold noise return false
     * and must not be written. A later move returns true; persist it with
     * [persistLocation].
     */
    fun observeLocation(workId: String, progress: ReaderProgress): Boolean =
        progressGate.consider(workId, progress) != null

    /**
     * Mid-session write for a location [observeLocation] already accepted.
     * Updates the resume point and retires a macOS percent that the position
     * moved past. Does not bump Continue Reading order (iOS debounced locator).
     */
    suspend fun persistLocation(workId: String, progress: ReaderProgress): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        return workRepository.upsert(
            progressMapper.applyProgress(work, progress, clock(), shelfStamp = false)
        )
    }

    /**
     * Reader close / background. When this session has a position and the
     * locator did not move, this is iOS `noteUnchangedLocatorShelf`: dates
     * only, stored fraction unchanged. A move was already persisted.
     */
    suspend fun finishReading(workId: String): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        if (!progressGate.sessionMatches(workId) || !progressGate.hasSessionPosition) return work
        val now = clock()
        return workRepository.upsert(
            work.copy(
                lastReadDate = now,
                progressModifiedAt = now,
                lastModifiedAt = now,
                hiddenFromHistoryAt = null
            )
        )
    }

    /** Explicit progress write (shelf stamp). Prefer [persistLocation] from the reader. */
    suspend fun saveProgress(workId: String, progress: ReaderProgress): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        return workRepository.upsert(progressMapper.applyProgress(work, progress, clock()))
    }

    suspend fun setFinished(workId: String, finished: Boolean): SavedWork? {
        // Delegates to WorkRepository so free-EPUB-on-finish policy is one place
        // (Apple WorkLifecycle parity).
        return workRepository.setFinished(workId, finished)
    }

    /** iOS onReachedPublicationEnd: finish now, hold the copy only on close. */
    suspend fun finishAtPublicationEnd(workId: String): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        if (!work.isComplete || work.isFinished) return work
        val now = clock()
        return workRepository.upsert(work.copy(
            isFinished = true,
            lastReadDate = now,
            progressModifiedAt = now,
            lastModifiedAt = now
        ))
    }

    suspend fun close(workId: String): SavedWork? = workRepository.holdFinishedCopy(workId, clock())

    /**
     * Explicitly mark the EPUB file as gone (e.g. after a confirmed FileMissing).
     * Never called automatically; the saved-work record is preserved.
     */
    suspend fun markEpubMissing(workId: String): SavedWork? =
        workRepository.setHasEpub(workId, false)

    /**
     * Persists that kudos were successfully given on this work, so the icon
     * shows filled after a relaunch (Work Detail's kudos button does the
     * same upsert; the reader's own kudos button needs it too).
     */
    suspend fun markKudosGiven(workId: String): SavedWork? {
        val work = workRepository.getWork(workId) ?: return null
        if (work.hasGivenKudos) return work
        return workRepository.upsert(work.copy(hasGivenKudos = true, lastModifiedAt = clock()))
    }
}
