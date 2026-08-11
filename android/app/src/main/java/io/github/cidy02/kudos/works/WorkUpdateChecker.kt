package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import java.time.Duration
import java.time.Instant

/**
 * Polls AO3 for new chapters on the user's in-progress works, feeding Home's
 * "Recently Updated". Polite by design: only **WIP** works (complete works can't
 * gain chapters), serial (through the already-paced AO3 client), and throttled
 * so opening Home re-checks each work at most every few hours.
 *
 * Apple `WorkUpdateChecker` parity.
 */
class WorkUpdateChecker(
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository,
    private val clock: () -> Instant = { Instant.now() }
) {
    /**
     * Re-checks the live AO3 chapter count for each eligible work, updating its
     * stored `chapters` (so `hasUpdate` reflects reality) and baselining
     * `knownChapterCount` on first sight. Failures are kept silent and retried later.
     */
    suspend fun checkForUpdates(among: List<SavedWork> = emptyList()) {
        val works = among.ifEmpty { workRepository.listSavedWorks() }
        val due = works.filter { shouldCheck(it, clock()) }
        if (due.isEmpty()) return

        val now = clock()
        for (work in due) {
            val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: continue
            when (val result = metadataRepository.fetch(workId)) {
                is AO3Result.Failure -> {
                    // Network / parse / locked page — keep what we have, but still
                    // stamp the check time so a failing work backs off for MinInterval
                    // like a successful one, instead of retrying on every Home open.
                    workRepository.upsert(work.copy(lastUpdateCheck = now))
                }
                is AO3Result.Success -> {
                    val chapters = result.value.chapters
                    if (chapters.isBlank()) {
                        // Fetched fine but nothing usable came back (e.g. a locked or
                        // restricted work) — still stamp the check, same reasoning as
                        // the Failure branch above.
                        workRepository.upsert(work.copy(lastUpdateCheck = now))
                    } else {
                        workRepository.upsert(applyChapterUpdate(work, chapters, now))
                    }
                }
            }
        }
    }

    companion object {
        /** Don't re-poll a work more often than this (Apple: 6 hours). */
        val MinInterval: Duration = Duration.ofHours(6)

        fun shouldCheck(work: SavedWork, now: Instant = Instant.now()): Boolean {
            if (work.isComplete) return false
            if (work.sourceUrl.isBlank()) return false
            val last = work.lastUpdateCheck ?: return true
            return Duration.between(last, now) >= MinInterval
        }

        /**
         * Apply a freshly scraped chapters string: update `chapters`, baseline
         * `knownChapterCount` when null/0, stamp `lastUpdateCheck`.
         */
        fun applyChapterUpdate(
            work: SavedWork,
            chapters: String,
            now: Instant
        ): SavedWork {
            val withChapters = work.copy(chapters = chapters)
            val known = work.knownChapterCount
            val baselinedKnown = if (known == null || known == 0) {
                withChapters.postedChapterCount
            } else {
                known
            }
            return withChapters.copy(
                knownChapterCount = baselinedKnown,
                lastUpdateCheck = now
            )
        }
    }
}
