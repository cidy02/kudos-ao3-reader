package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Constants

data class AO3WorkSummary(
    val id: Long,
    val title: String,
    val authors: List<String>,
    val fandoms: List<String>,
    val rating: String,
    val warnings: List<String>,
    val categories: List<String>,
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val freeforms: List<String> = emptyList(),
    val summary: String = "",
    val language: String = "",
    val wordCount: Int? = null,
    val chapters: String = "",
    val kudos: Int? = null,
    val comments: Int? = null,
    val hits: Int? = null,
    val bookmarks: Int? = null,
    val seriesTitle: String? = null,
    val seriesPosition: Int? = null,
    val seriesUrl: String? = null,
    val isComplete: Boolean? = null,
    val isRestricted: Boolean = false,
    val updatedDate: String = "",
    val publishedDate: String? = null
) {
    val workUrl: String
        get() = "${AO3Constants.BASE_URL}/works/$id"

    val authorText: String
        get() = authors.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: "Anonymous"
}

data class AO3SearchPage(
    val works: List<AO3WorkSummary>,
    val currentPage: Int,
    val totalPages: Int
)
