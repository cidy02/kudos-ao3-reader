package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
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
    suspend fun getCollectionShow(slug: String): AO3Result<AO3CollectionShow> {
        val url = "${AO3Constants.BASE_URL}/collections/$slug/profile"
        return when (val result = ao3Client.get(url, authRepository.authHeaders())) {
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(collectionParser.parseCollectionShow(result.value.body, slug))
                } catch (e: Exception) {
                    AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse)
                }
            }
            is AO3Result.Failure -> result
        }
    }

    suspend fun getCollectionWorks(slug: String, page: Int): AO3Result<AO3SearchPage> {
        val url = "${AO3Constants.BASE_URL}/collections/$slug/works?page=$page"
        return when (val result = ao3Client.get(url, authRepository.authHeaders())) {
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(searchParser.parseSearchPage(result.value.body, page))
                } catch (e: Exception) {
                    AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse)
                }
            }
            is AO3Result.Failure -> result
        }
    }

    suspend fun getCollectionBookmarks(slug: String, page: Int): AO3Result<AO3SearchPage> {
        val url = "${AO3Constants.BASE_URL}/collections/$slug/bookmarks?page=$page"
        return when (val result = ao3Client.get(url, authRepository.authHeaders())) {
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(searchParser.parseWorksListPage(result.value.body, page, "li.bookmark.blurb"))
                } catch (e: Exception) {
                    AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse)
                }
            }
            is AO3Result.Failure -> result
        }
    }

    suspend fun getCollectionPeople(slug: String, page: Int): AO3Result<AO3CollectionPeoplePage> {
        val url = "${AO3Constants.BASE_URL}/collections/$slug/people?page=$page"
        return when (val result = ao3Client.get(url, authRepository.authHeaders())) {
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(collectionParser.parseCollectionPeoplePage(result.value.body, page))
                } catch (e: Exception) {
                    AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse)
                }
            }
            is AO3Result.Failure -> result
        }
    }
}
