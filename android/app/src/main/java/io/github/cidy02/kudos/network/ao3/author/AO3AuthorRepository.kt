package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParseException
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

class AO3AuthorRepository(
    private val publicClient: AO3Client = OkHttpAO3Client(),
    private val authenticatedClient: AO3AuthenticatedClient? = null,
    private val parser: AO3AuthorParser = AO3AuthorParser(),
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default,
    private val pageCache: AO3PageCache = AO3PageCache.shared
) {
    val sessionChanges: kotlinx.coroutines.flow.StateFlow<Int> = authenticatedClient?.sessionChanges ?: kotlinx.coroutines.flow.MutableStateFlow(0)

    suspend fun loadDashboard(route: AO3AuthorRoute, bypassCache: Boolean = false): AO3Result<AO3AuthorHeader> {
        val url = route.dashboardUrl
        return cached(url, AO3PageCache.Kind.Dashboard, bypassCache) { parser.parseDashboard(it, route) }
    }

    suspend fun loadAbout(route: AO3AuthorRoute, bypassCache: Boolean = false): AO3Result<AO3AuthorAbout> {
        val url = route.profileUrl
        return cached(url, AO3PageCache.Kind.About, bypassCache) { parser.parseAbout(it, route) }
    }

    suspend fun loadWorks(
        route: AO3AuthorRoute,
        page: Int = 1,
        scope: AO3AuthorWorksScope = AO3AuthorWorksScope.Works,
        sort: AO3AuthorWorksSort = AO3AuthorWorksSort(),
        bypassCache: Boolean = false
    ): AO3Result<AO3SearchPage> {
        val url = AO3AuthorUrls.userWorksUrl(route.username, page, route.pseud, scope, sort)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return cached(url, AO3PageCache.Kind.Works, bypassCache) { parser.parseWorksPage(it, page) }
    }

    suspend fun loadFandomWorks(
        fandom: AO3AuthorFandom,
        page: Int = 1,
        sort: AO3AuthorWorksSort = AO3AuthorWorksSort(),
        bypassCache: Boolean = false
    ): AO3Result<AO3SearchPage> {
        val url = AO3AuthorUrls.fandomWorksUrl(fandom.url, page, sort)
            ?: return AO3Result.Failure(AO3Error.Validation("No fandom selected."))
        return cached(url, AO3PageCache.Kind.Works, bypassCache) { parser.parseWorksPage(it, page) }
    }

    suspend fun loadSeries(route: AO3AuthorRoute, page: Int = 1, bypassCache: Boolean = false): AO3Result<AO3AuthorSeriesPage> {
        val url = AO3AuthorUrls.userSeriesUrl(route.username, page, route.pseud)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return cached(url, AO3PageCache.Kind.AuthorSeries, bypassCache) { parser.parseSeriesPage(it, page) }
    }

    suspend fun loadBookmarks(route: AO3AuthorRoute, page: Int = 1, bypassCache: Boolean = false): AO3Result<AO3AuthorBookmarksPage> {
        val url = AO3AuthorUrls.userBookmarksUrl(route.username, page, route.pseud)
            ?: return AO3Result.Failure(AO3Error.Validation("No author selected."))
        return cached(url, AO3PageCache.Kind.Bookmarks, bypassCache) { parser.parseBookmarksPage(it, page) }
    }

    private suspend fun <T> cached(
        url: String, kind: AO3PageCache.Kind, bypassCache: Boolean, parse: (String) -> T
    ): AO3Result<T> = pageCache.read(url, kind, authenticatedClient, bypassCache,
        fetch = {
            val auth = authenticatedClient?.takeIf { it.username() != null }
            if (auth == null) publicClient.get(url) else auth.getAuthenticated(url)
        },
        parse = { AO3Result.Success(it.body).mapParse(parse) })

    private suspend fun <T> AO3Result<String>.mapParse(
        block: (String) -> T
    ): AO3Result<T> {
        return when (this) {
            is AO3Result.Failure -> this
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(withContext(parseDispatcher) { block(value) })
                } catch (e: CancellationException) {
                    throw e
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

}
