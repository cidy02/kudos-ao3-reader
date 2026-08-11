package io.github.cidy02.kudos.network.ao3.chapters

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Fetches a work's `/navigate` chapter index (iOS `AO3Client.chapterIndex`).
 *
 * Cached per work for the process lifetime: the page is small, and the comments
 * screen would otherwise re-fetch it every time the user switches chapter scope.
 * ponytail: unbounded in-memory map, fine for a session's worth of works — give
 * it an LRU cap if a user ever opens thousands.
 */
class AO3ChapterIndexRepository(
    private val client: AO3Client = OkHttpAO3Client()
) {
    private val cache = mutableMapOf<Long, List<AO3ChapterRef>>()

    suspend fun chapters(workId: Long): AO3Result<List<AO3ChapterRef>> {
        cache[workId]?.let { return AO3Result.Success(it) }

        val url = AO3URLResolver.canonicalWorkUrl(workId).trimEnd('/') + "/navigate"
        return when (val response = client.get(url)) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val parsed = withContext(Dispatchers.Default) {
                    AO3ChapterIndexParser.parse(response.value.body)
                }
                if (parsed.isNotEmpty()) cache[workId] = parsed
                AO3Result.Success(parsed)
            }
        }
    }

    /**
     * Resolves a 1-based story-chapter position to its AO3 chapter id, or null
     * when the index is unavailable or the work is single-chapter — callers fall
     * back to work-level comments, which show the same thread anyway.
     */
    suspend fun chapterIdForPosition(workId: Long, position: Int): Long? {
        val chapters = (chapters(workId) as? AO3Result.Success)?.value ?: return null
        return chapters.firstOrNull { it.position == position }?.chapterId
    }
}
