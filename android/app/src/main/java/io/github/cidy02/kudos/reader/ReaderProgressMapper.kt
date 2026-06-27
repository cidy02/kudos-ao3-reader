package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant

/**
 * Pure mapping between [SavedWork] persisted progress and the engine-agnostic
 * [ReaderProgress]/[ReaderRestoreTarget] types. Holds the cross-platform
 * restore/persist rules from READER_STATE_CONTRACT.md.
 */
class ReaderProgressMapper {

    /** Decide where to open, preferring a same-platform-compatible locator. */
    fun restoreTarget(work: SavedWork): ReaderRestoreTarget {
        ReaderLocatorCodec.decodeCompatibleLocator(work.readiumLocator)?.let {
            return ReaderRestoreTarget.Locator(it)
        }
        if (work.lastSpineIndex > 0 || work.lastScrollFraction > 0.0) {
            return ReaderRestoreTarget.Fallback(
                spineIndex = work.lastSpineIndex.coerceAtLeast(0),
                scrollFraction = work.lastScrollFraction.coerceIn(0.0, 1.0)
            )
        }
        return ReaderRestoreTarget.Beginning
    }

    /**
     * Apply a freshly captured [progress] onto [work]. Always refreshes the
     * cross-platform fallback fields and `lastReadDate`; only overwrites
     * `readiumLocator` when a new locator was captured. Never touches local user
     * state (favorite/finished/tags/collections).
     */
    fun applyProgress(work: SavedWork, progress: ReaderProgress, now: Instant): SavedWork {
        return work.copy(
            lastSpineIndex = progress.spineIndex.coerceAtLeast(0),
            lastScrollFraction = progress.scrollFraction.coerceIn(0.0, 1.0),
            readiumLocator = progress.locatorJson ?: work.readiumLocator,
            lastReadDate = now
        )
    }
}
