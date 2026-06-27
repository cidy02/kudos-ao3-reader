package io.github.cidy02.kudos.network.ao3.browse

/**
 * One of AO3's media categories (e.g. "TV Shows"), scraped from `/media`, with its
 * featured fandoms and a link to the category's full fandom index
 * (`/media/<name>/fandoms`). Mirrors Apple's `AO3MediaCategory`.
 */
data class AO3MediaCategory(
    val name: String,
    /** Relative or absolute href to the category's full fandom index page. */
    val fandomsPath: String,
    val featuredFandoms: List<String> = emptyList()
)

/**
 * A fandom (canonical AO3 tag name) plus its work count when the index exposes it.
 * The work list for a fandom is fetched via the Phase 5 search infrastructure
 * (`work_search[fandom_names]`), so no `/tags/<name>/works` URL escaping is needed.
 */
data class AO3Fandom(
    val name: String,
    val workCount: Int? = null
)
