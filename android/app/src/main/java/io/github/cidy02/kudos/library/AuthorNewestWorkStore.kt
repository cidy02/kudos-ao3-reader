package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.StateFlow

/**
 * iOS `AuthorNewestWorkStore`: each favorite author's newest work, for Favorites › Authors.
 *
 * The one owner-approved read of a page per author (AO3_NETWORKING_POLICY, "Favorites Authors
 * newest work"): only once the reader has opened that list, one author after another through the
 * paced client, stopped when the reader leaves, and kept in memory for the session so the list
 * can be left and reopened without asking AO3 again.
 *
 * [newestFirstPage] is the author's works, newest posted first. AO3's own default is Date
 * Updated, where an old work edited yesterday outranks one posted last week.
 */
class AuthorNewestWorkStore(
    private val sessionScope: () -> String,
    /** Ticks when the session changes, so a screen can ask again for the new reader. */
    val sessionChanges: StateFlow<Int>,
    private val now: () -> Long = System::currentTimeMillis,
    private val newestFirstPage: suspend (username: String) -> AO3Result<AO3SearchPage>
) {
    /** A kept answer. No work is an answer too: this author has nothing a reader can see. */
    class Answer(val work: AO3WorkSummary?)
    private class Entry(val answer: Answer, val fetchedAt: Long)
    private val entries = mutableMapOf<String, Entry>()

    private fun key(username: String, scope: String) = "$scope|${username.lowercase()}"

    /** The answer for the present session, while it is fresh; null when AO3 has not been asked. */
    @Synchronized
    fun cached(username: String, scope: String = sessionScope()): Answer? =
        entries[key(username, scope)]?.takeIf { now() - it.fetchedAt < TTL_MILLIS }?.answer

    @Synchronized
    private fun store(work: AO3WorkSummary?, username: String, scope: String) {
        // One session's answers at a time: another account's do not outlive it.
        entries.keys.retainAll { it.startsWith("$scope|") }
        entries[key(username, scope)] = Entry(Answer(work), now())
    }

    /** False when a failure that would meet the next author too ended the round. */
    private suspend fun fetchAndStore(username: String, scope: String): Boolean {
        val result = newestFirstPage(username)
        if (sessionScope() != scope) return false
        return when (result) {
            is AO3Result.Success -> true.also { store(result.value.works.firstOrNull(), username, scope) }
            // No such page: a byline renamed or deleted. That is an answer (nothing to show),
            // and must not stall every author behind it for the session.
            is AO3Result.Failure -> (result.error == AO3Error.NotFound || result.error is AO3Error.Validation)
                .also { gone -> if (gone) store(null, username, scope) }
        }
    }

    /**
     * Asks for every author not yet answered, in the order given, one at a time. Stops at the
     * first offline, overloaded or unreadable answer: it would meet the next author too, and
     * going on would only multiply requests against an unwell AO3. An answer already kept
     * costs no request, so a second round resumes where the first one stopped.
     *
     * True only when every author has an answer: "With new work" never filters a partial list.
     */
    suspend fun prefetch(usernames: List<String>): Boolean {
        val scope = sessionScope()
        val distinct = usernames.distinctBy { it.lowercase() }
        for (username in distinct) {
            currentCoroutineContext().ensureActive()
            if (cached(username, scope) != null) continue
            if (!fetchAndStore(username, scope)) return false
        }
        return sessionScope() == scope && distinct.all { cached(it, scope) != null }
    }

    companion object {
        /** Long enough to scroll and return for nothing, short enough to see today's post. */
        const val TTL_MILLIS = 30 * 60 * 1000L
    }
}

/** iOS `FavoriteAuthorQuickFilter`: the Authors list's own rail. */
enum class FavoriteAuthorQuickFilter(val id: String, val title: String) {
    All("all", "All"), WithNewWork("withNewWork", "With new work");

    /**
     * Authors whose newest work the reader has not opened. A row without an account, or without
     * an answer, does not match: that would turn something unknown into a claim.
     */
    fun apply(
        rows: List<ReadingAffinities.Row>,
        newestWork: (String) -> AuthorNewestWorkStore.Answer?,
        readWorkIds: Set<Long>
    ): List<ReadingAffinities.Row> = if (this == All) rows else rows.filter { row ->
        val work = row.username?.let(newestWork)?.work
        work != null && work.id !in readWorkIds
    }

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: All
    }
}
