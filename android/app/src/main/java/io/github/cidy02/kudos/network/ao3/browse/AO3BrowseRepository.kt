package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Clock
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.SystemAO3Clock
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Read-only AO3 Browse data layer. Fetches the media index and per-category fandom
 * lists through the Phase 4 polite client, and delegates fandom work lists to the
 * Phase 5 search repository (a fandom list = a search filtered by `fandom_names`).
 * Never mutates local Library state. When [cache] is given, a category's fandom
 * list is served from disk while fresh (mirrors iOS `FandomCatalogCache`'s
 * stale-while-revalidate intent) instead of re-scraping AO3's `/media/<name>/fandoms`
 * pages — some run to thousands of fandoms — on every Browse open.
 */
class AO3BrowseRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val parser: AO3BrowseParser = AO3BrowseParser(),
    private val searchRepository: AO3SearchRepository = AO3SearchRepository(client),
    private val cache: FandomCatalogCache? = null,
    private val clock: AO3Clock = SystemAO3Clock
) {
    suspend fun categories(): AO3Result<List<AO3MediaCategory>> {
        return when (val result = client.get(AO3BrowseUrls.mediaIndexUrl())) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> runParse(result.value.statusCode) {
                parser.parseMediaCategories(result.value.body)
            }
        }
    }

    suspend fun fandoms(category: AO3MediaCategory): AO3Result<List<AO3Fandom>> {
        val cached = cache?.load()
        val entry = cached?.get(category.name)
        val now = Instant.ofEpochMilli(clock.nowMillis())
        if (entry != null && !FandomCatalogCache.isStale(entry, now)) {
            return AO3Result.Success(entry.fandoms)
        }
        val url = AO3BrowseUrls.resolveAo3Url(category.fandomsPath)
            ?: return AO3Result.Failure(
                AO3Error.Validation("This category has no native AO3 fandom index.")
            )
        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> runParse(result.value.statusCode) {
                parser.parseFandomList(result.value.body)
            }.also { parsed ->
                if (cache != null && parsed is AO3Result.Success) {
                    val newEntry = FandomCatalogCache.Entry(parsed.value, clock.nowMillis())
                    cache.save((cached ?: emptyMap()) + (category.name to newEntry))
                }
            }
        }
    }

    /**
     * A fandom's works, from AO3's own tag listing rather than `/works/search`.
     *
     * Same works and the same filters (see [AO3SearchUrlBuilder.buildFandomWorksUrl]),
     * but the tag page states its own "1 - 20 of N Works in <fandom>" heading, so the
     * results card shows AO3's figures instead of ones derived here.
     *
     * `filters.fandom` is left set rather than cleared as redundant: the path already
     * scopes to this tag, so `fandom_names` can only re-select the same works
     * (verified — the count is unchanged with it present), whereas clearing it would
     * *widen* the results if that field ever held more than this one fandom.
     */
    suspend fun worksForFandom(
        fandomName: String,
        page: Int = 1,
        filters: AO3SearchFilters? = null
    ): AO3Result<AO3SearchPage> {
        val trimmed = fandomName.trim()
        if (trimmed.isEmpty()) {
            return AO3Result.Failure(AO3Error.Validation("No fandom selected."))
        }
        val searchFilters = (filters ?: browseBaseline()).copy(fandom = trimmed)
        return searchRepository.searchTagWorks(trimmed, searchFilters, page)
    }

    companion object {
        /**
         * Browse's starting filters. Date Updated, not the app-wide RELEVANCE
         * default: AO3's tag listing has no relevance ordering at all — its sort menu
         * runs Creator … Bookmarks and it sorts by `revised_at` unless told otherwise
         * (verified live). RELEVANCE sends no `sort_column`, so the screen would show
         * date-ordered results while claiming "Best Match".
         */
        fun browseBaseline(): AO3SearchFilters =
            AO3SearchFilters(sort = AO3SearchSort.DATE_UPDATED)
    }

    private suspend fun <T> runParse(statusCode: Int, block: () -> T): AO3Result<T> {
        return try {
            AO3Result.Success(withContext(Dispatchers.Default) { block() })
        } catch (error: AO3BrowseParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3BrowseParseException) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 Browse page could not be parsed."))
        }
    }
}
