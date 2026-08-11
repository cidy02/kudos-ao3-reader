package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Fills in work cards that AO3's own listing left bare.
 *
 * The subscriptions page is the case this exists for: AO3 lists nothing there but
 * each work's title, id and author, so `parseSubscriptionsPage` can only build a
 * sparse [AO3WorkSummary] and those cards render with no tags, no stats and no
 * summary while every other list in the app shows them.
 *
 * **One work at a time, on demand, never as a batch.** Filling a 20-work page
 * eagerly would mean 20 work-page fetches before anything could be shown, each
 * taking a politeness slot — the list would sit empty for as long as that took, and
 * scrolling past a work you didn't care about would still have cost a request. Rows
 * ask for their own metadata as they appear and the card fills in behind them.
 *
 * Results are memoised for the process lifetime so paging back never re-fetches.
 * Nothing is persisted — this is presentation detail for a screen the user is
 * looking at, not library data.
 */
class AO3SparseWorkEnricher(
    private val repository: AO3WorkMetadataRepository,
    private val scope: CoroutineScope
) {
    private val mutex = Mutex()
    /** Successful lookups. Absent means "not fetched yet". */
    private val enriched = mutableMapOf<Long, AO3WorkSummary>()
    /**
     * Ids whose fetch failed, so a work that 404s (deleted, or locked to registered
     * users) is not retried on every scroll — the sparse card stands.
     */
    private val failed = mutableSetOf<Long>()
    /** In-flight fetches, so two rows appearing together share one request. */
    private val inFlight = mutableMapOf<Long, Deferred<AO3WorkMetadata?>>()

    /**
     * A fuller version of [work], or null when there is nothing to add or the fetch
     * failed. Returns immediately for a work that already has its metadata.
     */
    suspend fun enrich(work: AO3WorkSummary): AO3WorkSummary? {
        if (!isSparse(work)) return null

        val pending = mutex.withLock {
            enriched[work.id]?.let { return it }
            if (work.id in failed) return null
            inFlight.getOrPut(work.id) {
                scope.async {
                    when (val result = repository.fetch(work.id)) {
                        is AO3Result.Success -> result.value
                        is AO3Result.Failure -> null
                    }
                }
            }
        }

        val metadata = pending.await()
        return mutex.withLock {
            inFlight.remove(work.id)
            // Re-check: another caller may have completed the same fetch while this
            // one awaited, and two rows must not disagree about the same work.
            enriched[work.id]?.let { return@withLock it }
            if (metadata == null || metadata.isEmpty) {
                failed += work.id
                return@withLock null
            }
            val merged = work.copy(
                fandoms = metadata.fandoms,
                rating = metadata.rating,
                warnings = metadata.warnings,
                categories = metadata.categories,
                relationships = metadata.relationships,
                characters = metadata.characters,
                freeforms = metadata.freeforms,
                language = metadata.language,
                wordCount = metadata.words,
                chapters = metadata.chapters,
                kudos = metadata.kudos,
                comments = metadata.comments,
                hits = metadata.hits
            )
            enriched[work.id] = merged
            merged
        }
    }

    companion object {
        /**
         * Whether a summary is missing the fields a card renders.
         *
         * Deliberately not "any field is empty": a real work can legitimately have no
         * fandom listed. What marks a *subscription* blurb is that AO3 gave the
         * listing no stats block at all, so rating, chapters and fandoms are blank
         * together — a combination a parsed search blurb never produces.
         */
        fun isSparse(work: AO3WorkSummary): Boolean =
            work.rating.isBlank() && work.chapters.isBlank() && work.fandoms.isEmpty()
    }
}
