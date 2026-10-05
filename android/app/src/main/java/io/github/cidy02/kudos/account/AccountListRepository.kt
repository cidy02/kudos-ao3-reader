package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionsIndexPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsPage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

class AccountListRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    val authRepository: AO3AuthRepository,
    val settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    private val urls: AO3AccountUrls = AO3AccountUrls(),
    private val parser: AO3AccountParser = AO3AccountParser(),
    val countsCache: AO3AccountListCountsCache? = null
) {
    suspend fun load(type: AccountListType, page: Int = 1): AO3Result<AO3SearchPage> {
        val generation = authRepository.generation.value
        val username = authRepository.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val url = urls.url(type, username, page)
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }

        val response = client.get(url, headers)
        currentCoroutineContext().ensureActive()
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (val result = response) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire(generation)
                result
            }
            is AO3Result.Success -> {
                val parsed = parse(type, result.value.body, result.value.url, result.value.statusCode, page, generation)
                if (parsed is AO3Result.Success && generation != authRepository.generation.value) {
                    throw CancellationException()
                }
                if (parsed is AO3Result.Success) {
                    countsCache?.put(
                        type,
                        username,
                        AO3AccountListCountsCache.Count(
                            itemsOnPage = parsed.value.works.size,
                            totalPages = parsed.value.totalPages
                        )
                    )
                }
                parsed
            }
        }
    }

    /** One foreground account-index GET, with the same auth and paced client as Works. */
    suspend fun loadNamedSubscriptions(
        scope: AO3NamedSubscriptionsScope,
        page: Int = 1
    ): AO3Result<AO3NamedSubscriptionsPage> {
        if (!authRepository.state.value.isSignedIn) {
            return AO3Result.Failure(AO3Error.AuthenticationRequired)
        }
        val generation = authRepository.generation.value
        val username = authRepository.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val url = urls.namedSubscriptionsUrl(username, scope, page)
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        if (generation != authRepository.generation.value) throw CancellationException()
        val response = client.get(url, headers)
        currentCoroutineContext().ensureActive()
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (response) {
            is AO3Result.Failure -> {
                if (response.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire(generation)
                response
            }
            is AO3Result.Success -> try {
                val parsed = withContext(Dispatchers.Default) {
                    parser.parseNamedSubscriptions(response.value.body, scope, page, response.value.url)
                }
                if (generation != authRepository.generation.value) throw CancellationException()
                AO3Result.Success(parsed)
            } catch (error: AO3AccountParseException.LoginRequired) {
                authRepository.sessionDidExpire(generation)
                AO3Result.Failure(AO3Error.AuthenticationRequired)
            } catch (error: AO3AccountParseException.Overloaded) {
                AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, retryAfterMillis = null))
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 subscriptions page could not be parsed."))
            }
        }
    }

    /**
     * Authenticated collections index for the signed-in user
     * (`/users/<username>/collections`).
     */
    suspend fun loadCollections(page: Int = 1): AO3Result<List<AO3Collection>> =
        when (val result = loadCollectionsIndex(page)) {
            is AO3Result.Success -> AO3Result.Success(result.value.collections)
            is AO3Result.Failure -> result
        }

    /** Same single request as loadCollections, retaining the index's pagination. */
    suspend fun loadCollectionsIndex(page: Int = 1): AO3Result<AO3CollectionsIndexPage> {
        val generation = authRepository.generation.value
        val username = authRepository.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val url = urls.collectionsUrl(username, page)
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        if (generation != authRepository.generation.value) throw CancellationException()
        currentCoroutineContext().ensureActive()
        // The shared client coalesces GETs in its own scope. Keep this page's
        // waiter until that single request finishes, even after cancellation,
        // so joining a retired crawl cannot overlap it with a replacement page.
        // Cancellation still discards this result and prevents every later page.
        val result = withContext(NonCancellable) { client.get(url, headers) }
        currentCoroutineContext().ensureActive()
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (result) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.AuthenticationRequired) {
                    authRepository.sessionDidExpire(generation)
                }
                result
            }
            is AO3Result.Success -> parseCollectionsPage(
                html = result.value.body,
                finalUrl = result.value.url,
                statusCode = result.value.statusCode,
                page = page,
                generation = generation
            )
        }
    }

    private suspend fun parse(
        type: AccountListType,
        html: String,
        finalUrl: String,
        statusCode: Int,
        page: Int,
        generation: Int
    ): AO3Result<AO3SearchPage> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseAccountList(html, page, type, finalUrl)
                }
            )
        } catch (error: AO3AccountParseException.LoginRequired) {
            authRepository.sessionDidExpire(generation)
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        } catch (error: AO3AccountParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: CancellationException) {
            throw error
        } catch (error: AO3AccountParseException) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 account page could not be parsed."))
        } catch (error: Exception) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 account page could not be parsed."))
        }
    }

    private suspend fun parseCollectionsPage(
        html: String,
        finalUrl: String,
        statusCode: Int,
        page: Int,
        generation: Int
    ): AO3Result<AO3CollectionsIndexPage> {
        return try {
            val index = withContext(Dispatchers.Default) {
                parser.parseCollectionsIndex(html, page, finalUrl)
            }
            if (generation != authRepository.generation.value) throw CancellationException()
            AO3Result.Success(index)
        } catch (error: AO3AccountParseException.LoginRequired) {
            authRepository.sessionDidExpire(generation)
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        } catch (error: AO3AccountParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3AccountParseException) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 collections page could not be parsed."))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 collections page could not be parsed."))
        }
    }
}
