package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Requested form GETs and one optional first-page picker read. No writes or read-ahead. */
class AO3WorkFormRepository(
    private val client: AO3AuthenticatedClient,
    private val authRepository: AO3AuthRepository,
    private val parser: AO3WorkFormParser = AO3WorkFormParser(),
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default
) {
    suspend fun loadNewWorkForm(): AO3Result<AO3WorkForm> = load(AO3WorkFormUrls.newWork())
    suspend fun loadWorkForm(workID: Long): AO3Result<AO3WorkForm> = load(AO3WorkFormUrls.editWork(workID))

    suspend fun loadCollectionOffers(): AO3Result<List<AO3CollectionOffer>> {
        if (!authRepository.state.value.isSignedIn) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val username = authRepository.username()?.let(::trimWritingTag)?.takeIf { it.isNotEmpty() }
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val generation = authRepository.generation.value
        fun requireSession() {
            if (generation != authRepository.generation.value) throw CancellationException()
        }
        requireSession()
        val response = client.getAuthenticated(AO3AccountUrls().collectionsUrl(username))
        currentCoroutineContext().ensureActive()
        requireSession()
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> try {
                val offers = withContext(parseDispatcher) {
                    AO3AccountParser().parseCollections(response.value.body, response.value.url).map {
                        AO3CollectionOffer(it.name, it.title, AO3CollectionAccess(!it.isClosed, it.isModerated,
                            it.isUnrevealed, it.isAnonymous))
                    }
                }
                currentCoroutineContext().ensureActive()
                requireSession()
                AO3Result.Success(offers)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: AO3AccountParseException.LoginRequired) {
                requireSession()
                authRepository.sessionDidExpire(generation)
                AO3Result.Failure(AO3Error.AuthenticationRequired)
            } catch (_: AO3AccountParseException.Overloaded) {
                requireSession()
                AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, null))
            } catch (_: Exception) {
                requireSession()
                AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's collections."))
            }
        }
    }

    private suspend fun load(url: String): AO3Result<AO3WorkForm> {
        if (!authRepository.state.value.isSignedIn) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val generation = authRepository.generation.value
        fun requireSession() {
            if (generation != authRepository.generation.value) throw CancellationException()
        }
        requireSession()
        val response = client.getAuthenticated(url)
        currentCoroutineContext().ensureActive()
        requireSession()
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> try {
                val parsed = withContext(parseDispatcher) { parser.parse(response.value.body, response.value.url) }
                currentCoroutineContext().ensureActive()
                requireSession()
                AO3Result.Success(parsed)
            } catch (error: CancellationException) {
                throw error
            } catch (error: AO3WorkFormParseException.LoginRequired) {
                requireSession()
                authRepository.sessionDidExpire(generation)
                AO3Result.Failure(AO3Error.AuthenticationRequired)
            } catch (error: AO3WorkFormParseException.Overloaded) {
                requireSession()
                AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, null))
            } catch (error: Exception) {
                requireSession()
                AO3Result.Failure(AO3Error.Parse(error.message ?: "Couldn't read AO3's work form."))
            }
        }
    }
}
