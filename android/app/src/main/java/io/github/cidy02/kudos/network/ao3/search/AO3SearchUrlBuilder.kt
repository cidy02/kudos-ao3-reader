package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants

class AO3SearchUrlBuilder {
    /** The Search tab's endpoint: AO3's `/works/search`. */
    fun buildSearchUrl(filters: AO3SearchFilters, page: Int = 1): String {
        return AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath(AO3Constants.SEARCH_PATH)
            .also { appendWorkSearchParams(it, filters, page) }
            .build()
            .toString()
    }

    /**
     * Browse's endpoint: AO3's own works list for a tag.
     *
     * Same works as searching `work_search[fandom_names]` (142,327 both ways,
     * measured) and the same filters — the tag page's *visible* sidebar offers
     * fewer fields, but it is the same `WorkSearchForm` server-side and honours
     * everything this emits (verified live 2026-08-06: rating_ids, word_count,
     * single_chapter, revised_at, hits, character_names, title, creators,
     * sort_column, complete and excluded_tag_names each measurably changed the
     * count, and `work_search[query]` negation works too).
     *
     * What it buys is the heading: "1 - 20 of 142,327 Works in Naruto (Anime &
     * Manga)" where `/works/search` answers only "142,327 Found", so the results
     * card's subject and range come from AO3 instead of being derived.
     *
     * Returns null when the fandom is blank.
     */
    fun buildFandomWorksUrl(fandom: String, filters: AO3SearchFilters, page: Int = 1): String? {
        val segment = tagPathSegment(fandom) ?: return null
        return AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("tags")
            .addPathSegment(segment)
            .addPathSegment("works")
            .also { appendWorkSearchParams(it, filters, page) }
            .build()
            .toString()
    }

    /**
     * AO3 writes a handful of characters as `*x*` escapes inside a tag's URL path
     * rather than percent-encoding them — `&` becomes `*a*`, so
     * "Naruto (Anime & Manga)" is `/tags/Naruto%20(Anime%20*a*%20Manga)/works`.
     * Percent-encoding of the rest is left to OkHttp's `addPathSegment`.
     */
    fun tagPathSegment(tag: String): String? {
        val trimmed = tag.trim()
        if (trimmed.isEmpty()) return null
        var escaped = trimmed
        for ((from, to) in listOf("/" to "*s*", "&" to "*a*", "." to "*d*", "?" to "*q*", "#" to "*h*")) {
            escaped = escaped.replace(from, to)
        }
        return escaped
    }

    /**
     * Every `work_search[...]` query item for a filter set, plus `page`. Shared by
     * both endpoints so the two screens cannot drift into answering different
     * questions about the same fandom.
     */
    private fun appendWorkSearchParams(
        builder: okhttp3.HttpUrl.Builder,
        filters: AO3SearchFilters,
        page: Int
    ) {
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
        // AO3's own exclusion field. Not on the search *form*, but it is in
        // `WorkSearchForm::ATTRIBUTES` and the endpoint honours it — see
        // AO3SearchFilters.excludedTagNames for why this beats `-"tag"` in the query.
        add("work_search[excluded_tag_names]", filters.excludedTagNames)
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
    }

    fun wordCountExpression(filters: AO3SearchFilters): String? {
        // Pass the trimmed values through verbatim to mirror Apple (which trims and
        // forwards the raw strings). This preserves inputs like "10,000" that a
        // numeric coercion would silently drop, keeping the AO3 query identical
        // across platforms. Blank sides are treated as absent.
        val from = filters.wordsFrom.trim().takeIf { it.isNotEmpty() }
        val to = filters.wordsTo.trim().takeIf { it.isNotEmpty() }
        return when {
            from != null && to != null -> "$from-$to"
            from != null -> "> $from"
            to != null -> "< $to"
            else -> null
        }
    }
}
