package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Delay
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.CoroutineAO3Delay
import io.github.cidy02.kudos.network.ao3.SystemAO3Clock
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.isActive

/**
 * Manual library availability sweep — port of Apple `WorkAvailabilitySweep`.
 *
 * Deliberately **not** scheduled periodically: AO3 has no change-feed, so a
 * full-library walk is one request per work. Politeness measures match iOS:
 * 7-day recheck skip, 1500 ms serial spacing, 150-work cap, oldest-checked
 * first, and cancellation that keeps work already done.
 */
class WorkAvailabilitySweep(
    private val workRepository: WorkRepository,
    private val tagsRepository: WorkTagsRepository,
    private val clock: AO3Clock = SystemAO3Clock,
    private val delay: AO3Delay = CoroutineAO3Delay
) {
    data class Summary(
        val checked: Int = 0,
        val stillAvailable: Int = 0,
        val nowUnavailable: Int = 0,
        /** Skipped because they were checked within [RECHECK_INTERVAL]. */
        val skippedRecent: Int = 0,
        /** Eligible but beyond this run's limit, or not reached before cancellation. */
        val remaining: Int = 0,
        val cancelled: Boolean = false
    )

    companion object {
        /** Don't re-ask about a work checked more recently than this. */
        val RECHECK_INTERVAL: Duration = Duration.ofDays(7)

        /**
         * Gap between requests. Spacing goes *before* each request after the first
         * so a cancelled sweep never leaves a pointless trailing sleep.
         */
        const val REQUEST_SPACING_MILLIS: Long = 1500L

        /** Ceiling for one run so a huge library cannot become an accidental marathon. */
        const val DEFAULT_LIMIT: Int = 150
    }

    /**
     * Runs the sweep. Never throws for per-work network failure: a work that
     * cannot be checked is left as it was. Cancellation stops cleanly and
     * preserves work already done.
     */
    suspend fun sweep(limit: Int = DEFAULT_LIMIT): Summary {
        val now = Instant.ofEpochMilli(clock.nowMillis())
        val recheckCutoff = now.minus(RECHECK_INTERVAL)

        val verifiable = workRepository.listSavedWorks().filter { work ->
            work.sourceUrl.isNotBlank() &&
                !work.ao3Unavailable &&
                WorkTags.ao3WorkIdFromUrl(work.sourceUrl) != null
        }

        val pending = verifiable.filter { work ->
            val last = work.lastAvailabilityCheck
            last == null || !last.isAfter(recheckCutoff)
        }
        val skippedRecent = verifiable.size - pending.size

        // null (never checked) sorts first: those are the works we know least about.
        val ordered = pending.sortedWith(
            compareBy(nullsFirst()) { it.lastAvailabilityCheck }
        )
        val batch = ordered.take(limit)
        var remaining = ordered.size - batch.size

        var checked = 0
        var stillAvailable = 0
        var nowUnavailable = 0
        var cancelled = false

        for ((index, work) in batch.withIndex()) {
            if (!coroutineContext.isActive) {
                cancelled = true
                remaining += batch.size - index
                break
            }
            if (index > 0) {
                try {
                    delay.delay(REQUEST_SPACING_MILLIS)
                } catch (_: CancellationException) {
                    cancelled = true
                    remaining += batch.size - index
                    break
                }
            }

            val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: continue
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
                        checked++
                        nowUnavailable++
                    }
                    // Inconclusive (timeout, 5xx, parse…): leave stamps alone.
                }
                is AO3Result.Success -> {
                    workRepository.upsert(work.copy(lastAvailabilityCheck = now))
                    checked++
                    stillAvailable++
                }
            }
        }

        return Summary(
            checked = checked,
            stillAvailable = stillAvailable,
            nowUnavailable = nowUnavailable,
            skippedRecent = skippedRecent,
            remaining = remaining,
            cancelled = cancelled
        )
    }
}
