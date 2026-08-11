package io.github.cidy02.kudos.network.ao3.series

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParseException
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Fetches every work listed on an AO3 series page (all pages). Series listings use
 * the same `li.work.blurb` markup as search, so parsing reuses [AO3SearchParser].
 * Mirrors Apple `AO3Client.seriesWorks(seriesURL:)`.
 */
class AO3SeriesRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val parser: AO3SearchParser = AO3SearchParser()
) {
    /**
     * Every work in a series across all of the series page's pages.
     * Empty pages or reaching [AO3SearchPage.totalPages] ends pagination.
     */
    suspend fun seriesWorks(seriesUrl: String): AO3Result<List<AO3WorkSummary>> {
        val all = mutableListOf<AO3WorkSummary>()
        var page = 1
        while (true) {
            when (val result = seriesPage(seriesUrl, page)) {
                is AO3Result.Failure -> return result
                is AO3Result.Success -> {
                    val pageResult = result.value
                    all += pageResult.works
                    if (pageResult.works.isEmpty() || page >= pageResult.totalPages) {
                        return AO3Result.Success(all)
                    }
                    page += 1
                }
            }
        }
    }

    /** One page of a series listing (for tests / incremental UI). */
    suspend fun seriesPage(seriesUrl: String, page: Int = 1): AO3Result<AO3SearchPage> {
        val url = AO3SeriesUrls.seriesPageUrl(seriesUrl, page)
            ?: return AO3Result.Failure(
                AO3Error.Validation("Not a valid AO3 series URL.")
            )
        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> parse(result.value.body, result.value.statusCode, page)
        }
    }

    private suspend fun parse(
        html: String,
        statusCode: Int,
        page: Int
    ): AO3Result<AO3SearchPage> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    // Series pages share search's work-blurb markup.
                    parser.parseSearchPage(html, page)
                }
            )
        } catch (error: AO3SearchParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3SearchParseException) {
            AO3Result.Failure(
                AO3Error.Parse(error.message ?: "AO3 series page could not be parsed.")
            )
        }
    }
}
