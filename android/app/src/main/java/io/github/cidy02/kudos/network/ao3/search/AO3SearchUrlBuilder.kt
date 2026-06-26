package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants

class AO3SearchUrlBuilder {
    fun buildSearchUrl(filters: AO3SearchFilters, page: Int = 1): String {
        val builder = AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath(AO3Constants.SEARCH_PATH)

        fun add(name: String, value: String?) {
            val trimmed = value?.trim()
            if (!trimmed.isNullOrEmpty()) {
                builder.addQueryParameter(name, trimmed)
            }
        }

        add("work_search[query]", filters.searchQuery)
        add("work_search[fandom_names]", filters.fandom)
        add("work_search[character_names]", filters.characters)
        add("work_search[relationship_names]", filters.relationships)
        add("work_search[freeform_names]", filters.additionalTags)
        add("work_search[rating_ids]", filters.structuredRatingId)

        AO3Warning.entries
            .filter(filters.warnings::contains)
            .forEach { builder.addQueryParameter("work_search[archive_warning_ids][]", it.ao3Id) }

        AO3Category.entries
            .filter(filters.categories::contains)
            .forEach { builder.addQueryParameter("work_search[category_ids][]", it.ao3Id) }

        add("work_search[crossover]", filters.crossover.ao3Value)
        add("work_search[complete]", filters.completion.ao3Value)
        add("work_search[word_count]", wordCountExpression(filters))
        add("work_search[revised_at]", filters.updated.ao3Value)
        add("work_search[language_id]", filters.language.code)
        add("work_search[sort_column]", filters.sort.sortColumn)
        builder.addQueryParameter("page", page.coerceAtLeast(1).toString())

        return builder.build().toString()
    }

    fun wordCountExpression(filters: AO3SearchFilters): String? {
        val from = positiveInt(filters.wordsFrom)
        val to = positiveInt(filters.wordsTo)
        return when {
            from != null && to != null -> "$from-$to"
            from != null -> "> $from"
            to != null -> "< $to"
            else -> null
        }
    }

    private fun positiveInt(value: String): Int? {
        return value.trim().toIntOrNull()?.takeIf { it > 0 }
    }
}
