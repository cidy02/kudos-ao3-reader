package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsPage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPeoplePage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionShow
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionForm
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionNameAvailability
import io.github.cidy02.kudos.network.ao3.account.collectionNameFormatIsValid
import io.github.cidy02.kudos.network.ao3.account.reservedCollectionNames
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3CollectionDetailRepository(
    private val ao3Client: AO3Client,
    val authRepository: AO3AuthRepository,
    private val collectionParser: AO3CollectionParser = AO3CollectionParser(),
    private val searchParser: AO3SearchParser = AO3SearchParser()
) {
    suspend fun getCollectionForm(slug: String?): AO3Result<AO3CollectionForm> =
        fetch(AO3CollectionFormUrls.form(slug)) { AO3CollectionFormParser().parse(it, slug) }

    /** iOS availability probe: anonymous public GET; the shared client owns pacing, slots and retries. */
    suspend fun collectionNameAvailable(name: String): AO3CollectionNameAvailability {
        val trimmed = name.trim()
        if (!collectionNameFormatIsValid(trimmed)) return AO3CollectionNameAvailability.Invalid
        if (trimmed.lowercase() in reservedCollectionNames) return AO3CollectionNameAvailability.Taken
        return when (val result = ao3Client.get(AO3CollectionFormUrls.show(trimmed))) {
            is AO3Result.Success -> when (result.value.statusCode) {
                200 -> AO3CollectionNameAvailability.Taken
                404 -> AO3CollectionNameAvailability.Available
                else -> AO3CollectionNameAvailability.Unknown
            }
            is AO3Result.Failure -> if (result.error == AO3Error.NotFound) AO3CollectionNameAvailability.Available
                else AO3CollectionNameAvailability.Unknown
        }
    }

    suspend fun getCollectionShow(slug: String): AO3Result<AO3CollectionShow> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/profile") {
            collectionParser.parseCollectionShow(it, slug)
        }

    suspend fun getCollectionWorks(slug: String, page: Int): AO3Result<AO3SearchPage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/works?page=$page") {
            searchParser.parseSearchPage(it, page)
        }

    suspend fun getCollectionBookmarks(slug: String, page: Int): AO3Result<AO3SearchPage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/bookmarks?page=$page") {
            searchParser.parseWorksListPage(it, page, "li.bookmark.blurb")
        }

    suspend fun getCollectionPeople(slug: String, page: Int): AO3Result<AO3CollectionPeoplePage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/people?page=$page") {
            collectionParser.parseCollectionPeoplePage(it, page)
        }

    suspend fun getCollectionItems(
        slug: String,
        tab: AO3CollectionItemTab,
        page: Int
    ): AO3Result<AO3CollectionItemsPage> =
        fetch(AO3CollectionItemsUrls.page(slug, tab, page)) {
            AO3CollectionItemsParser().parse(it, slug, tab, page)
        }

    suspend fun getUserCollectionItems(username: String, tab: AO3CollectionItemTab, page: Int): AO3Result<AO3CollectionItemsPage> {
        val url = AO3CollectionItemsUrls.userPage(username, tab, page)
            ?: return AO3Result.Failure(AO3Error.Parse("AO3 didn't give a collection-items page for this account."))
        return fetch(url) { AO3CollectionItemsParser().parseUser(it, username, tab, page) }
    }

    /** Signed-in GET, as [AccountListRepository] does it; a parser throw becomes a parse error. */
    private suspend fun <T> fetch(url: String, parse: (String) -> T): AO3Result<T> {
        val generation = authRepository.generation.value
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val result = ao3Client.get(url, headers)
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (result) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire(generation)
                result
            }
            is AO3Result.Success -> try {
                AO3Result.Success(withContext(Dispatchers.Default) {
                    parse(result.value.body)
                })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                AO3Result.Failure(AO3Error.Parse(e.message ?: "Could not read the collection page."))
            }
        }
    }
}
