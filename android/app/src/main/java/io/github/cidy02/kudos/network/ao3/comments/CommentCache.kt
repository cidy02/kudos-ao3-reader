package io.github.cidy02.kudos.network.ao3.comments

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Basic stale-while-revalidate disk cache for comment threads.
 * Maps (workId, chapterId, page) to a JSON-serialized [AO3CommentThread].
 */
class CommentCache(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val cacheDir: File get() = File(context.cacheDir, "comment_threads")

    private fun fileFor(target: AO3CommentTarget, page: Int): File {
        val name = when (target) {
            is AO3CommentTarget.Work -> "work_${target.workId}_p${page}.json"
            is AO3CommentTarget.Chapter -> "work_${target.workId}_ch${target.chapterId}_p${page}.json"
        }
        return File(cacheDir, name)
    }

    suspend fun load(target: AO3CommentTarget, page: Int): AO3CommentThread? = withContext(Dispatchers.IO) {
        val file = fileFor(target, page)
        if (!file.exists()) return@withContext null
        runCatching {
            json.decodeFromString<AO3CommentThread>(file.readText())
        }.getOrNull()
    }

    suspend fun save(thread: AO3CommentThread, page: Int) = withContext(Dispatchers.IO) {
        val file = fileFor(thread.target, page)
        runCatching {
            if (!cacheDir.exists()) cacheDir.mkdirs()
            file.writeText(json.encodeToString(thread))
        }
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        runCatching { cacheDir.deleteRecursively() }
    }
}
