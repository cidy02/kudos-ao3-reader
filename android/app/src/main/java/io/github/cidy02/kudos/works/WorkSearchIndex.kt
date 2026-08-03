package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import java.text.Normalizer
import java.util.Locale
import kotlinx.coroutines.delay

/**
 * Normalization and search index for [SavedWork].
 * Port of Apple `WorkSearchIndex` (Services/WorkSearchIndex.swift).
 *
 * The index is derived state: excluded from backup, rebuilt on schema bump via
 * [rebuildIfNeeded], and recomputed on every upsert that changes searchable fields.
 */
object WorkSearchIndex {
    /**
     * Bump when [indexText] composition changes so existing records rebuild.
     * 0 is reserved for "never indexed".
     * v2: series title + user tags (parity with iOS v2).
     */
    const val CURRENT_VERSION = 2

    /** Summary text beyond this limit contributes noise, not recall. */
    private const val SUMMARY_LIMIT = 600

    /** Launch-rebuild pacing (iOS sliceBudget / sliceBreather / saveInterval). */
    private const val SLICE_BUDGET_MS = 5L
    private const val SLICE_BREATHER_MS = 2L
    private const val SAVE_INTERVAL = 250

    /**
     * Normalizes text for matching: lowercased, whitespace-trimmed, and diacritic-insensitive.
     */
    fun normalize(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ""
        val normalized = Normalizer.normalize(trimmed, Normalizer.Form.NFD)
        return normalized.replace(Regex("\\p{InCombiningDiacriticalMarks}+"), "")
            .lowercase(Locale.ROOT)
    }

    /** Splits a query into normalized terms for AND matching across fields. */
    fun terms(query: String): List<String> {
        return normalize(query)
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
    }

    /**
     * Generates the complete searchable text block for a work.
     * [userTags] are the user's organizational tags (iOS `SavedWork.tags`).
     */
    fun indexText(work: SavedWork, userTags: List<String> = emptyList()): String {
        val parts = mutableListOf<String>()
        if (work.title.isNotBlank()) parts.add(work.title)
        if (work.author.isNotBlank()) parts.add(work.author)
        if (work.seriesTitle.isNotBlank()) parts.add(work.seriesTitle)
        parts.addAll(userTags.filter { it.isNotBlank() })
        parts.addAll(work.workFandoms)
        parts.addAll(work.workRelationships)
        parts.addAll(work.workCharacters)
        parts.addAll(work.workFreeforms)
        parts.addAll(work.workWarnings)
        parts.addAll(work.workCategories)

        val categorized = (work.workFandoms + work.workRelationships + work.workCharacters +
            work.workFreeforms + work.workWarnings + work.workCategories)
            .map { normalize(it) }
            .toSet()

        parts.addAll(work.workTags.filter { normalize(it) !in categorized })
        if (work.rating.isNotBlank()) parts.add(work.rating)
        if (work.language.isNotBlank()) parts.add(work.language)
        parts.add(if (work.isComplete) "complete" else "wip in progress")
        if (work.summary.isNotBlank()) {
            val stripped = work.summary.replace(Regex("<[^>]*>"), "")
            parts.add(stripped.take(SUMMARY_LIMIT))
        }
        return normalize(parts.joinToString("\n"))
    }

    /**
     * Returns [work] with [SavedWork.searchText] / [SavedWork.searchIndexVersion] filled.
     * Does **not** bump `lastModifiedAt` — the index is derived state.
     */
    fun reindex(work: SavedWork, userTags: List<String> = emptyList()): SavedWork {
        return work.copy(
            searchText = indexText(work, userTags),
            searchIndexVersion = CURRENT_VERSION
        )
    }

    /**
     * True if [work] matches every term (AND).
     *
     * Prefer persisted [SavedWork.searchText] when current. [userTags] and
     * [extraTerms] (e.g. collection names) are always appended so library
     * search still finds membership-only tokens.
     */
    fun matches(
        work: SavedWork,
        terms: List<String>,
        userTags: List<String> = emptyList(),
        extraTerms: List<String> = emptyList()
    ): Boolean {
        if (terms.isEmpty()) return true
        val base = if (work.searchIndexVersion == CURRENT_VERSION && work.searchText.isNotEmpty()) {
            work.searchText
        } else {
            indexText(work, userTags)
        }
        val haystack = if (userTags.isEmpty() && extraTerms.isEmpty()) {
            base
        } else {
            // Re-include userTags when recomputing wasn't done; extras always needed.
            val extras = buildList {
                if (work.searchIndexVersion != CURRENT_VERSION || work.searchText.isEmpty()) {
                    // already in base via indexText
                } else {
                    addAll(userTags)
                }
                addAll(extraTerms)
            }
            if (extras.isEmpty()) base else normalize(base + "\n" + extras.joinToString("\n"))
        }
        return terms.all { haystack.contains(it) }
    }

    /**
     * Reindexes every work whose stamp doesn't match [CURRENT_VERSION].
     * Paced so large libraries don't stall. Returns count rebuilt.
     */
    suspend fun rebuildIfNeeded(
        loadStale: suspend (currentVersion: Int) -> List<SavedWork>,
        userTagsFor: suspend (workId: String) -> List<String>,
        save: suspend (List<SavedWork>) -> Unit
    ): Int {
        val stale = loadStale(CURRENT_VERSION)
        if (stale.isEmpty()) return 0
        val pending = mutableListOf<SavedWork>()
        var sinceSave = 0
        var sliceStart = System.nanoTime()
        for (work in stale) {
            val tags = userTagsFor(work.id)
            pending.add(reindex(work, tags))
            sinceSave++
            if (sinceSave >= SAVE_INTERVAL) {
                save(pending.toList())
                pending.clear()
                sinceSave = 0
            }
            val elapsedMs = (System.nanoTime() - sliceStart) / 1_000_000L
            if (elapsedMs > SLICE_BUDGET_MS) {
                delay(SLICE_BREATHER_MS)
                sliceStart = System.nanoTime()
            }
        }
        if (pending.isNotEmpty()) {
            save(pending)
        }
        return stale.size
    }
}
