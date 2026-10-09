package io.github.cidy02.kudos.network.ao3.chapters

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Fetches a work's `/navigate` chapter index (iOS `AO3Client.chapterIndex`).
 *
 * Read **in the reader's session** when there is one (iOS does the same): a work
 * only registered users may see refuses the read without it, and the comments
 * screen then stayed on "All comments" (audit A28-4). One read, never repeated
 * without the session after a refusal.
 *
 * Cached per work **and per session** for the process lifetime: the page is small,
 * and the comments screen would otherwise re-fetch it every time the user switches
 * chapter scope; what one account was allowed to see is not served to the next.
 * ponytail: unbounded in-memory map, fine for a session's worth of works — give
 * it an LRU cap if a user ever opens thousands.
 */
class AO3ChapterIndexRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val authenticatedClient: AO3AuthenticatedClient? = null
) {
    private val cache = mutableMapOf<Pair<Long, Int?>, List<AO3ChapterRef>>()

    suspend fun chapters(workId: Long): AO3Result<List<AO3ChapterRef>> {
        val session = authenticatedClient?.takeIf { it.username() != null }
        val key = workId to session?.sessionGeneration()
        cache[key]?.let { return AO3Result.Success(it) }

        val url = AO3URLResolver.canonicalWorkUrl(workId).trimEnd('/') + "/navigate"
        return when (val response = if (session == null) client.get(url) else session.getAuthenticated(url)) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val parsed = withContext(Dispatchers.Default) {
                    AO3ChapterIndexParser.parse(response.value.body)
                }
                if (parsed.isNotEmpty()) cache[key] = parsed
                AO3Result.Success(parsed)
            }
        }
    }

    /**
     * Resolves a 1-based story-chapter position to its AO3 chapter, or null
     * when the index is unavailable or the work is single-chapter — callers fall
     * back to work-level comments, which show the same thread anyway.
     */
    suspend fun chapterForPosition(workId: Long, position: Int): AO3ChapterRef? {
        val chapters = (chapters(workId) as? AO3Result.Success)?.value ?: return null
        return chapters.firstOrNull { it.position == position }
    }
}
