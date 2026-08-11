package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import java.nio.file.Path

/**
 * Outcome of resolving a work for reading (file + restore target + prefs).
 *
 * On [Success], [Success.preferences] is the mapped DataStore/settings snapshot
 * from [ReaderRepository.open] — the ViewModel must pass these through into
 * [ReaderUiState.Reading] unchanged as the initial display preferences.
 */
sealed interface ReaderOpenResult {
    data class Success(
        val work: SavedWork,
        val epubPath: Path,
        val restoreTarget: ReaderRestoreTarget,
        val preferences: ReaderPreferences
    ) : ReaderOpenResult

    data class Failure(val work: SavedWork?, val error: ReaderError) : ReaderOpenResult
}
