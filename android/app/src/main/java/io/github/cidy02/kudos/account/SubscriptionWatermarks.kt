package io.github.cidy02.kudos.account

import android.content.Context
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.json.JSONObject

/**
 * What the reader had already seen the last time they looked at their AO3
 * subscriptions or Marked for Later list.
 * Mirrors iOS `SubscriptionWatermarks` (Services/SubscriptionWatermarks.swift).
 */
data class SubscriptionWatermark(
    val postedChapterCount: Int,
    val seenAt: Long = System.currentTimeMillis()
)

object SubscriptionWatermarks {
    const val NAMESPACE_SUBSCRIPTIONS = "ao3.subscriptions.watermarks"
    const val NAMESPACE_MARKED_FOR_LATER = "ao3.markedForLater.watermarks"
    private const val PREFS_NAME = "ao3_subscription_watermarks"
    private const val ENTRY_LIMIT = 512

    fun load(context: Context, namespace: String): Map<Long, SubscriptionWatermark> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jsonString = prefs.getString(namespace, null) ?: return emptyMap()
        return try {
            val json = JSONObject(jsonString)
            val result = mutableMapOf<Long, SubscriptionWatermark>()
            for (key in json.keys()) {
                val workId = key.toLongOrNull() ?: continue
                val obj = json.getJSONObject(key)
                val count = obj.getInt("count")
                val seenAt = obj.optLong("seenAt", System.currentTimeMillis())
                result[workId] = SubscriptionWatermark(postedChapterCount = count, seenAt = seenAt)
            }
            result
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun save(context: Context, namespace: String, watermarks: Map<Long, SubscriptionWatermark>) {
        val bounded = if (watermarks.size > ENTRY_LIMIT) {
            watermarks.entries
                .sortedByDescending { it.value.seenAt }
                .take(ENTRY_LIMIT)
                .associate { it.key to it.value }
        } else {
            watermarks
        }

        val json = JSONObject()
        for ((id, watermark) in bounded) {
            val obj = JSONObject()
            obj.put("count", watermark.postedChapterCount)
            obj.put("seenAt", watermark.seenAt)
            json.put(id.toString(), obj)
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(namespace, json.toString()).apply()
    }

    fun newChapterCount(work: AO3WorkSummary, watermarks: Map<Long, SubscriptionWatermark>): Int {
        val seen = watermarks[work.id] ?: return 0
        val posted = parsePostedCount(work.chapters)
        return maxOf(0, posted - seen.postedChapterCount)
    }

    fun baseline(
        context: Context,
        namespace: String,
        works: List<AO3WorkSummary>
    ): Map<Long, SubscriptionWatermark> {
        val current = load(context, namespace).toMutableMap()
        var changed = false
        for (work in works) {
            if (work.id !in current) {
                val posted = parsePostedCount(work.chapters)
                current[work.id] = SubscriptionWatermark(postedChapterCount = posted)
                changed = true
            }
        }
        if (changed) {
            save(context, namespace, current)
        }
        return current
    }

    fun markAllSeen(
        context: Context,
        namespace: String,
        works: List<AO3WorkSummary>
    ): Map<Long, SubscriptionWatermark> {
        val current = load(context, namespace).toMutableMap()
        for (work in works) {
            val posted = parsePostedCount(work.chapters)
            current[work.id] = SubscriptionWatermark(postedChapterCount = posted)
        }
        save(context, namespace, current)
        return current
    }

    private fun parsePostedCount(chapters: String): Int {
        return chapters.substringBefore('/').trim().toIntOrNull() ?: 0
    }
}
