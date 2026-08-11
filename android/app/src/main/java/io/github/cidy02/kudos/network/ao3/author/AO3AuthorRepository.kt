package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParseException
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3AuthorRepository(
    private val publicClient: AO3Client = OkHttpAO3Client(),
    private val authenticatedClient: AO3AuthenticatedClient? = null,
    private val parser: AO3AuthorParser = AO3AuthorParser()
) {
    suspend fun loadDashboard(route: AO3AuthorRoute): AO3Result<AO3AuthorHeader> {
        val url = route.dashboardUrl
        return getHtml(url).mapParse { parser.parseDashboard(it, route) }
    }

    suspend fun loadAbout(route: AO3AuthorRoute): AO3Result<AO3AuthorAbout> {
        val url = route.profileUrl
        return getHtml(url).mapParse { parser.parseAbout(it, route) }
    }

    suspend fun loadWorks(route: AO3AuthorRoute, page: Int = 1): AO3Result<AO3SearchPage> {
        val url = AO3AuthorUrls.userWorksUrl(route.username, page, route.pseud)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return getHtml(url).mapParse { parser.parseWorksPage(it, page) }
    }

    suspend fun loadSeries(route: AO3AuthorRoute, page: Int = 1): AO3Result<AO3AuthorSeriesPage> {
        val url = AO3AuthorUrls.userSeriesUrl(route.username, page, route.pseud)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return getHtml(url).mapParse { parser.parseSeriesPage(it, page) }
    }

    suspend fun loadBookmarks(route: AO3AuthorRoute, page: Int = 1): AO3Result<AO3AuthorBookmarksPage> {
        val url = AO3AuthorUrls.userBookmarksUrl(route.username, page, route.pseud)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return getHtml(url).mapParse { parser.parseBookmarksPage(it, page) }
    }

    private suspend fun getHtml(url: String): AO3Result<String> {
        val auth = authenticatedClient
        if (auth != null) {
            return when (val result = auth.getAuthenticated(url)) {
                is AO3Result.Failure -> {
                    // Fall back to public for private-profile soft failures.
                    publicClient.get(url).map { it.body }
                }
                is AO3Result.Success -> AO3Result.Success(result.value.body)
            }
        }
        return publicClient.get(url).map { it.body }
    }

    private suspend fun <T> AO3Result<String>.mapParse(
        block: (String) -> T
    ): AO3Result<T> {
        return when (this) {
            is AO3Result.Failure -> this
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(withContext(Dispatchers.Default) { block(value) })
                } catch (e: AO3AuthorParseException) {
                    AO3Result.Failure(AO3Error.Parse(e.message ?: "Author page parse failed."))
                } catch (e: AO3SearchParseException.Overloaded) {
                    AO3Result.Failure(AO3Error.Overloaded(0, null))
                } catch (e: AO3SearchParseException) {
                    AO3Result.Failure(AO3Error.Parse(e.message ?: "Author works parse failed."))
                } catch (e: Exception) {
                    AO3Result.Failure(AO3Error.Parse(e.message ?: "Author page parse failed."))
                }
            }
        }
    }

    private inline fun <T, R> AO3Result<T>.map(transform: (T) -> R): AO3Result<R> {
        return when (this) {
            is AO3Result.Failure -> this
            is AO3Result.Success -> AO3Result.Success(transform(value))
        }
    }
}
