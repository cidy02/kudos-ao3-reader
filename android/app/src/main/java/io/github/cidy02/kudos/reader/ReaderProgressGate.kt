package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Duration
import java.time.Instant
import kotlin.math.abs

/**
 * Decides which navigator reports are worth a database write.
 *
 * Port of iOS `ReadiumProgressPersistence`: the stored locator is the seed, so
 * the same string on open stays quiet, and the first *different* locator is a
 * real place (written immediately, because the interval has not started). A
 * later move inside the two-second window arms one trailing write. An empty
 * locator is not a place, even when it carries a spine index or a progression.
 */
class ReaderProgressGate {
    var workId: String? = null
        private set

    /** Latest navigator progress. An empty locator does not replace it. */
    var latestProgress: ReaderProgress? = null
        private set

    val latestLocatorString: String?
        get() = latestProgress?.locatorJson?.takeIf { it.isNotEmpty() }

    /**
     * True once this session has a locator (the seed counts). iOS
     * `hasSessionPosition`: open/close still refresh Continue Reading.
     */
    val hasSessionPosition: Boolean
        get() = latestLocatorString != null

    /** Fires with the progress to store. Invoked synchronously from [note]. */
    var onDebouncedWrite: ((ReaderProgress) -> Unit)? = null

    /** Trailing-edge timer. Production supplies a main-thread scheduler. */
    var scheduler: TrailingWriteScheduler = TrailingWriteScheduler.None

    /** Clock used when a trailing write actually fires. */
    var clock: () -> Instant = { Instant.now() }

    private var lastPersistedString: String? = null
    private var lastPersistedProgression: Double? = null
    private var lastPersistAt: Instant? = null
    private var latestTotalProgression: Double? = null

    fun seed(workId: String, work: SavedWork) {
        this.workId = workId
        val seeded = work.readiumLocator?.takeIf { it.isNotEmpty() }
        latestProgress = seeded?.let {
            ReaderProgress(
                spineIndex = work.lastSpineIndex,
                scrollFraction = work.lastScrollFraction,
                locatorJson = it,
                totalProgression = null
            )
        }
        lastPersistedString = seeded
        latestTotalProgression = null
        lastPersistedProgression = null
        lastPersistAt = null
        scheduler.cancel()
    }

    /**
     * A navigator location. May invoke [onDebouncedWrite] before returning, or
     * arm a trailing write for the remainder of [MIN_PERSIST_INTERVAL_MS].
     */
    fun note(workId: String, progress: ReaderProgress, at: Instant): NoteOutcome {
        if (this.workId != null && this.workId != workId) return NoteOutcome.IGNORED
        record(progress)
        val ready = locatorForDebouncedWrite(at)
        if (ready != null) {
            emitDebounced(ready, at)
            return NoteOutcome.WRITTEN
        }
        // Noise must not cancel a trailing write that is waiting on an earlier settle.
        if (isMeaningfullyChanged()) {
            scheduleTrailingWrite(from = at)
            return NoteOutcome.TRAILING
        }
        return NoteOutcome.IGNORED
    }

    /** Ordinary streamed update, or null while the window is open or the move is noise. */
    fun locatorForDebouncedWrite(at: Instant): ReaderProgress? {
        val latest = latestProgress ?: return null
        if (latestLocatorString == null) return null
        val lastAt = lastPersistAt
        if (lastAt != null && Duration.between(lastAt, at).toMillis() < MIN_PERSIST_INTERVAL_MS) {
            return null
        }
        if (!isMeaningfullyChanged()) return null
        return latest
    }

    /** Flush point: the latest locator when it differs from disk. The window does not apply. */
    fun locatorForFlush(): ReaderProgress? {
        val latest = latestProgress ?: return null
        if (latestLocatorString == null) return null
        if (latestLocatorString == lastPersistedString) return null
        return latest
    }

    fun markPersisted(progress: ReaderProgress, at: Instant) {
        val locator = progress.locatorJson?.takeIf { it.isNotEmpty() } ?: return
        lastPersistedString = locator
        val explicit = finiteProgression(progress.totalProgression)
        lastPersistedProgression = when {
            explicit != null -> explicit
            locator == latestLocatorString -> latestTotalProgression
            else -> lastPersistedProgression
        }
        lastPersistAt = at
        scheduler.cancel()
    }

    fun cancelTrailing() {
        scheduler.cancel()
    }

    fun sessionMatches(workId: String): Boolean = this.workId == workId

    private fun record(progress: ReaderProgress) {
        val locator = progress.locatorJson ?: return
        if (locator.isEmpty()) return
        latestTotalProgression = finiteProgression(progress.totalProgression)
        latestProgress = progress
    }

    private fun isMeaningfullyChanged(): Boolean {
        val latest = latestLocatorString ?: return false
        val latestP = latestTotalProgression
        val lastP = lastPersistedProgression
        // Both sides have a progression: the locator string changes on every
        // settle, so only a delta against the last *persisted* progression counts.
        if (latestP != null && lastP != null) {
            return abs(latestP - lastP) >= MIN_DELTA
        }
        return latest != lastPersistedString
    }

    private fun emitDebounced(progress: ReaderProgress, at: Instant) {
        markPersisted(progress, at)
        onDebouncedWrite?.invoke(progress)
    }

    private fun scheduleTrailingWrite(from: Instant) {
        val remaining = if (lastPersistAt != null) {
            val elapsed = Duration.between(lastPersistAt, from).toMillis()
            (MIN_PERSIST_INTERVAL_MS - elapsed).coerceAtLeast(0)
        } else {
            MIN_PERSIST_INTERVAL_MS
        }
        scheduler.schedule(remaining) {
            val writeAt = clock()
            val ready = locatorForDebouncedWrite(writeAt) ?: return@schedule
            emitDebounced(ready, writeAt)
        }
    }

    private fun finiteProgression(value: Double?): Double? =
        value?.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0)

    companion object {
        /** iOS `ReadiumProgressPersistence.minPersistInterval` (2 seconds). */
        const val MIN_PERSIST_INTERVAL_MS = 2_000L

        /** iOS `ReadiumProgressPersistence.minProgressionDelta`. */
        const val MIN_DELTA = 0.001
    }
}

enum class NoteOutcome {
    IGNORED,
    WRITTEN,
    TRAILING
}

/** Replaces any pending trailing write. [None] drops it until the next flush. */
interface TrailingWriteScheduler {
    fun schedule(delayMillis: Long, block: () -> Unit)
    fun cancel()

    object None : TrailingWriteScheduler {
        override fun schedule(delayMillis: Long, block: () -> Unit) = Unit
        override fun cancel() = Unit
    }
}
