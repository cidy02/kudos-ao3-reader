package io.github.cidy02.kudos.network.ao3.comments

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * A disk copy of comment threads for reading without a connection.
 * Maps (viewer, workId, chapterId, page) to a JSON-serialized [AO3CommentThread].
 *
 * **Each viewer has their own copies, and a copy carries nothing that can act.** A thread read
 * while signed in can show a restricted work's comments, and it used to be stored with its
 * form's authenticity token and each comment's edit and delete addresses, under a name that
 * was only the work and the page: the next person on the device, or the same person signed
 * out, was handed it (audit A17-4; `docs/AO3_NETWORKING_POLICY.md`, comments).
 */
class CommentCache(private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }
    private val cacheDir: File get() = File(context.cacheDir, "comment_threads")

    private fun fileFor(target: AO3CommentTarget, page: Int, viewer: String?): File {
        val name = when (target) {
            is AO3CommentTarget.Work -> "work_${target.workId}_p${page}.json"
            is AO3CommentTarget.Chapter -> "work_${target.workId}_ch${target.chapterId}_p${page}.json"
        }
        return File(cacheDir, viewerKey(viewer) + "_" + name)
    }

    suspend fun load(target: AO3CommentTarget, page: Int, viewer: String?): AO3CommentThread? = withContext(Dispatchers.IO) {
        val file = fileFor(target, page, viewer)
        if (!file.exists()) return@withContext null
        runCatching {
            json.decodeFromString<AO3CommentThread>(file.readText())
        }.getOrNull()
    }

    suspend fun save(thread: AO3CommentThread, page: Int, viewer: String?) = withContext(Dispatchers.IO) {
        val file = fileFor(thread.target, page, viewer)
        runCatching {
            if (!cacheDir.exists()) cacheDir.mkdirs()
            // Copies written before viewers had their own names belong to nobody in particular.
            cacheDir.listFiles { f -> f.name.startsWith("work_") }?.forEach { it.delete() }
            file.writeText(json.encodeToString(readOnly(thread)))
        }
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        runCatching { cacheDir.deleteRecursively() }
    }

    companion object {
        /** What is safe to keep: the words, and nothing that posts, edits, deletes or replies. */
        internal fun readOnly(thread: AO3CommentThread): AO3CommentThread =
            thread.copy(form = null, comments = thread.comments.map(::readOnly))

        /** Replies too, all the way down: they kept their edit and delete addresses (audit A22-5). */
        private fun readOnly(comment: AO3Comment): AO3Comment = comment.copy(
            editPath = null, deletePath = null, canReply = false, replies = comment.replies.map(::readOnly)
        )

        internal fun viewerKey(viewer: String?): String {
            val name = viewer?.trim()?.lowercase().orEmpty()
            if (name.isEmpty()) return "anon"
            val digest = java.security.MessageDigest.getInstance("SHA-256").digest(name.toByteArray())
            return "u" + digest.take(8).joinToString("") { "%02x".format(it) }
        }
    }
}
