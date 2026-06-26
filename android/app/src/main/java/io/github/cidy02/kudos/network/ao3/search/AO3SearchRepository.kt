package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3SearchRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val urlBuilder: AO3SearchUrlBuilder = AO3SearchUrlBuilder(),
    private val parser: AO3SearchParser = AO3SearchParser()
) {
    suspend fun search(
        filters: AO3SearchFilters,
        page: Int = 1
    ): AO3Result<AO3SearchPage> {
        val url = urlBuilder.buildSearchUrl(filters, page)
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
                    parser.parseSearchPage(html, page)
                }
            )
        } catch (error: AO3SearchParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3SearchParseException) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 search page could not be parsed."))
        }
    }
}
