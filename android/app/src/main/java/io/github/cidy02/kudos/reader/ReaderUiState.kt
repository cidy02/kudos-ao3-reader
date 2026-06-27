package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import java.nio.file.Path

sealed interface ReaderUiState {
    data object Loading : ReaderUiState

    data class Error(val error: ReaderError, val work: SavedWork?) : ReaderUiState

    data class Reading(
        val work: SavedWork,
        val epubPath: Path,
        val restoreTarget: ReaderRestoreTarget,
        val preferences: ReaderPreferences,
        val endOfWork: EndOfWorkActions,
        val finished: Boolean
    ) : ReaderUiState
}
