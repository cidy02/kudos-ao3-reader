package io.github.cidy02.kudos.network.ao3.browse

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Read-only AO3 Browse data layer. Fetches the media index and per-category fandom
 * lists through the Phase 4 polite client, and delegates fandom work lists to the
 * Phase 5 search repository (a fandom list = a search filtered by `fandom_names`).
 * Never mutates local Library state.
 */
class AO3BrowseRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val parser: AO3BrowseParser = AO3BrowseParser(),
    private val searchRepository: AO3SearchRepository = AO3SearchRepository(client)
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
        val url = AO3BrowseUrls.resolveAo3Url(category.fandomsPath)
            ?: return AO3Result.Failure(
                AO3Error.Validation("This category has no native AO3 fandom index.")
            )
        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> runParse(result.value.statusCode) {
                parser.parseFandomList(result.value.body)
            }
        }
    }

    /** A fandom's works, via the Phase 5 search path (`work_search[fandom_names]`). */
    suspend fun worksForFandom(
        fandomName: String,
        page: Int = 1,
        sort: AO3SearchSort = AO3SearchSort.RELEVANCE
    ): AO3Result<AO3SearchPage> {
        val trimmed = fandomName.trim()
        if (trimmed.isEmpty()) {
            return AO3Result.Failure(AO3Error.Validation("No fandom selected."))
        }
        return searchRepository.search(AO3SearchFilters(fandom = trimmed, sort = sort), page)
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
