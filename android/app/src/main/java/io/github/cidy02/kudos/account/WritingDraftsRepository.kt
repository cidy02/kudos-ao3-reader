package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsPage
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsParser
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsUrls
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** One foreground authenticated index GET; no enrichment, page walking, caching or writes. */
class WritingDraftsRepository(
    private val client: AO3AuthenticatedClient,
    val authRepository: AO3AuthRepository,
    private val parser: AO3DraftsParser = AO3DraftsParser(),
    // Compose tests pass Unconfined, as for AO3CollectionDetailRepository.
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default
) {
    suspend fun load(page: Int = 1): AO3Result<AO3DraftsPage> {
        if (!authRepository.state.value.isSignedIn) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val generation = authRepository.generation.value
        val username = authRepository.username() ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val url = AO3DraftsUrls.page(username, page) ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        if (generation != authRepository.generation.value) throw CancellationException()
        val response = client.getAuthenticated(url)
        currentCoroutineContext().ensureActive()
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> try {
                val parsed = withContext(parseDispatcher) { parser.parse(response.value.body, page, response.value.url) }
                if (generation != authRepository.generation.value) throw CancellationException()
                AO3Result.Success(parsed)
            } catch (error: CancellationException) {
                throw error
            } catch (error: AO3AccountParseException.LoginRequired) {
                authRepository.sessionDidExpire(generation)
                AO3Result.Failure(AO3Error.AuthenticationRequired)
            } catch (error: AO3AccountParseException.Overloaded) {
                AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, null))
            } catch (error: Exception) {
                AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3's page format wasn't what the app expected."))
            }
        }
    }
}
