package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import java.text.Normalizer
import java.util.Locale

/**
 * Normalization and search index matching for [SavedWork].
 * Port of Apple `WorkSearchIndex` (Services/WorkSearchIndex.swift).
 */
object WorkSearchIndex {
    /** Summary text beyond this limit contributes noise, not recall. */
    private const val SUMMARY_LIMIT = 600

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

    /** Generates the complete searchable text block for a work. */
    fun indexText(work: SavedWork): String {
        val parts = mutableListOf<String>()
        if (work.title.isNotBlank()) parts.add(work.title)
        if (work.author.isNotBlank()) parts.add(work.author)
        if (work.seriesTitle.isNotBlank()) parts.add(work.seriesTitle)
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

    /** Returns true if [work] matches every term in [terms]. */
    fun matches(work: SavedWork, terms: List<String>): Boolean {
        if (terms.isEmpty()) return true
        val index = indexText(work)
        return terms.all { index.contains(it) }
    }
}
