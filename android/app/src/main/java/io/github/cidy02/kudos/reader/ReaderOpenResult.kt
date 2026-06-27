package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import java.nio.file.Path

/** Outcome of resolving a work for reading (file + restore target + prefs). */
sealed interface ReaderOpenResult {
    data class Success(
        val work: SavedWork,
        val epubPath: Path,
        val restoreTarget: ReaderRestoreTarget,
        val preferences: ReaderPreferences
    ) : ReaderOpenResult

    data class Failure(val work: SavedWork?, val error: ReaderError) : ReaderOpenResult
}
