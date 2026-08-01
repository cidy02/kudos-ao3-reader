package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParseException
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Loads an author's works via AO3 work search (`work_search[creators]`).
 * Reuses the search page parser (same `li.work.blurb` markup).
 */
class AO3AuthorWorksRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val parser: AO3SearchParser = AO3SearchParser()
) {
    suspend fun worksForAuthor(author: String, page: Int = 1): AO3Result<AO3SearchPage> {
        val url = AO3AuthorUrls.worksSearchUrl(author, page)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
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
            AO3Result.Failure(
                AO3Error.Parse(error.message ?: "AO3 author works page could not be parsed.")
            )
        }
    }
}
