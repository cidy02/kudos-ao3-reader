package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readiumProgress
import io.github.cidy02.kudos.core.model.totalProgressionIn
import java.time.Instant
import kotlin.math.abs

/**
 * Pure mapping between [SavedWork] persisted progress and the engine-agnostic
 * [ReaderProgress]/[ReaderRestoreTarget] types.
 *
 * Open position matches iOS Readium (`ReadiumReaderView.openBook`): a compatible
 * locator, otherwise the start of `lastSpineIndex` when it is past the first
 * spine item. `legacyReaderProgress` is display-only, and the intra-chapter
 * scroll fraction is not recovered (`ReadiumBook.open`).
 */
class ReaderProgressMapper {

    /** Decide where to open, preferring a same-platform-compatible locator. */
    fun restoreTarget(work: SavedWork): ReaderRestoreTarget {
        ReaderLocatorCodec.decodeCompatibleLocator(work.readiumLocator)?.let {
            return ReaderRestoreTarget.Locator(it)
        }
        if (work.lastSpineIndex > 0) {
            return ReaderRestoreTarget.Fallback(
                spineIndex = work.lastSpineIndex,
                scrollFraction = 0.0
            )
        }
        return ReaderRestoreTarget.Beginning
    }

    /**
     * Apply a captured [progress] onto [work]. Refreshes the cross-platform
     * fallback fields and overwrites `readiumLocator` only when a new locator
     * was captured.
     *
     * A new locator retires `legacyReaderProgress` unless its whole-book
     * progression is within [ReaderProgressGate.MIN_DELTA] of the previous
     * Readium progression (iOS `applyDebouncedReadiumLocator`: a re-reported
     * spot is not a read). [shelfStamp] is the open/flush stamp
     * (`markProgressModified`): Continue Reading dates, and reading again
     * clears `hiddenFromHistoryAt`. A mid-session write leaves those alone.
     * Never touches favorite/finished/tags/collections.
     */
    fun applyProgress(
        work: SavedWork,
        progress: ReaderProgress,
        now: Instant,
        shelfStamp: Boolean = true
    ): SavedWork {
        val wroteLocator = !progress.locatorJson.isNullOrBlank()
        val before = work.readiumProgress
        val after = if (wroteLocator) {
            totalProgressionIn(progress.locatorJson) ?: progress.totalProgression
        } else {
            before
        }
        val keepLegacy = !wroteLocator || (
            before != null && after != null &&
                abs(after - before) < ReaderProgressGate.MIN_DELTA
            )
        return work.copy(
            lastSpineIndex = progress.spineIndex.coerceAtLeast(0),
            lastScrollFraction = progress.scrollFraction.coerceIn(0.0, 1.0),
            readiumLocator = progress.locatorJson ?: work.readiumLocator,
            legacyReaderProgress = if (keepLegacy) work.legacyReaderProgress else null,
            lastReadDate = if (shelfStamp) now else work.lastReadDate,
            progressModifiedAt = now,
            lastModifiedAt = if (shelfStamp) now else work.lastModifiedAt,
            hiddenFromHistoryAt = if (shelfStamp) null else work.hiddenFromHistoryAt
        )
    }
}
