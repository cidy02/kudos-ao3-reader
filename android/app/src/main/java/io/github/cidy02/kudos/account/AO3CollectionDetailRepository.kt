package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPeoplePage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionShow
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.auth.AO3AuthRepository

class AO3CollectionDetailRepository(
    private val ao3Client: AO3Client,
    private val authRepository: AO3AuthRepository,
    private val collectionParser: AO3CollectionParser = AO3CollectionParser(),
    private val searchParser: AO3SearchParser = AO3SearchParser()
) {
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

    /** Signed-in GET, as [AccountListRepository] does it; a parser throw becomes a parse error. */
    private suspend fun <T> fetch(url: String, parse: (String) -> T): AO3Result<T> {
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        return when (val result = ao3Client.get(url, headers)) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire()
                result
            }
            is AO3Result.Success -> try {
                AO3Result.Success(parse(result.value.body))
            } catch (e: Exception) {
                AO3Result.Failure(AO3Error.Parse(e.message ?: "Could not read the collection page."))
            }
        }
    }
}
