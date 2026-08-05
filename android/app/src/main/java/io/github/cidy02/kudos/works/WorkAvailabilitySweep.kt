package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * Checks the whole library for works AO3 has deleted, so the Last Copy badge
 * reflects reality rather than only what an import happened to touch.
 *
 * Apple `WorkAvailabilitySweep` parity — politeness measures iOS already has and
 * this class previously didn't: one request at a time, [REQUEST_SPACING] apart;
 * works checked within [RECHECK_INTERVAL] are skipped; oldest-checked first, so
 * repeat runs cover the library over time instead of re-walking the same prefix; a
 * per-run [DEFAULT_LIMIT], with whatever it didn't reach reported rather than
 * silently dropped; cancellable between requests, keeping whatever it already did.
 */
class WorkAvailabilitySweep(
    private val workRepository: WorkRepository,
    private val tagsRepository: WorkTagsRepository,
    private val clock: () -> Instant = { Instant.now() }
) {
    data class Summary(
        val checked: Int = 0,
        val stillAvailable: Int = 0,
        val nowUnavailable: Int = 0,
        /** Skipped because they were checked within [RECHECK_INTERVAL]. */
        val skippedRecent: Int = 0,
        /** In scope but beyond this run's [DEFAULT_LIMIT], or not reached before cancellation. */
        val remaining: Int = 0,
        val cancelled: Boolean = false,
        /** No AO3 identity, so no site to ask — counted, never contacted. */
        val unverifiable: Int = 0
    )

    /** Every active library work with an AO3 identity — the rest can't be checked at all. */
    private suspend fun allAO3Works(): List<SavedWork> {
        return workRepository.listLibraryWorks().filter { !it.isDeleted && it.sourceUrl.isNotBlank() }
    }

    /** Works this sweep would actually contact AO3 about, oldest check first. */
    suspend fun pending(now: Instant = clock()): List<SavedWork> {
        return allAO3Works()
            .filter { work ->
                val last = work.lastAvailabilityCheck ?: return@filter true
                Duration.between(last, now) >= RECHECK_INTERVAL
            }
            .sortedBy { it.lastAvailabilityCheck ?: Instant.EPOCH }
    }

    /**
     * Runs the sweep. `progress` reports (completed, total) after each check.
     * Cooperative cancellation is checked between requests (never mid-request), so
     * a cancelled run keeps every result it already has.
     */
    suspend fun run(
        limit: Int = DEFAULT_LIMIT,
        spacing: Duration = REQUEST_SPACING,
        now: Instant = clock(),
        progress: suspend (completed: Int, total: Int) -> Unit = { _, _ -> }
    ): Summary {
        val all = workRepository.listLibraryWorks()
        val unverifiable = all.count { !it.isDeleted && it.sourceUrl.isBlank() }

        val queue = pending(now)
        val skippedRecent = allAO3Works().size - queue.size
        val batch = queue.take(limit)
        val remainingAfterLimit = queue.size - batch.size

        var checked = 0
        var stillAvailable = 0
        var nowUnavailable = 0
        var cancelled = false

        for ((index, work) in batch.withIndex()) {
            if (!coroutineContext.isActive) {
                cancelled = true
                break
            }
            if (index > 0) {
                delay(spacing.toMillis())
                if (!coroutineContext.isActive) {
                    cancelled = true
                    break
                }
            }

            val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
            if (workId == null) {
                // Has a sourceUrl but not a recognizable AO3 one — nothing to ask.
                checked++
                progress(checked, batch.size)
                continue
            }
            when (val result = tagsRepository.refreshTags(workId)) {
                is AO3Result.Failure -> {
                    if (result.error is AO3Error.NotFound) {
                        workRepository.upsert(
                            work.copy(
                                ao3Unavailable = true,
                                lastAvailabilityCheck = now,
                                lastModifiedAt = now
                            )
                        )
                        nowUnavailable++
                    }
                    // Any other failure (network, rate limit): leave lastAvailabilityCheck
                    // untouched so it's retried promptly, not treated as a clean result.
                }
                is AO3Result.Success -> {
                    workRepository.upsert(work.copy(lastAvailabilityCheck = now))
                    stillAvailable++
                }
            }
            checked++
            progress(checked, batch.size)
        }

        return Summary(
            checked = checked,
            stillAvailable = stillAvailable,
            nowUnavailable = nowUnavailable,
            skippedRecent = skippedRecent,
            remaining = remainingAfterLimit + (batch.size - checked),
            cancelled = cancelled,
            unverifiable = unverifiable
        )
    }

    /** Legacy entry point (WorkManager's background sweep): runs once, no progress. */
    suspend fun sweep(): Int = run().nowUnavailable

    companion object {
        /** Don't re-ask about a work checked more recently than this. */
        val RECHECK_INTERVAL: Duration = Duration.ofDays(7)

        /** Gap between requests — slower than a person clicking through pages. */
        val REQUEST_SPACING: Duration = Duration.ofMillis(1_500)

        /** Ceiling for one run; what's left over is reported and picked up next time. */
        const val DEFAULT_LIMIT = 150
    }
}
