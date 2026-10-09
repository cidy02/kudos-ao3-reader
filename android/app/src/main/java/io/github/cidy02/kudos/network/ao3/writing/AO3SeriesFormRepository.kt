package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Each explicit load reads exactly one page. The screen owns the optional manage attempt. */
class AO3SeriesFormRepository(private val client: AO3AuthenticatedClient, val auth: AO3AuthRepository,
    private val parser: AO3SeriesFormParser = AO3SeriesFormParser(),
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default) {
    suspend fun loadForm(id: Long): AO3Result<AO3SeriesForm> = if (id <= 0) invalidID()
        else load(AO3SeriesFormUrls.edit(id)) { html, url -> parser.parse(html, url) }
    suspend fun loadManage(id: Long): AO3Result<List<AO3SeriesWorkRow>> = if (id <= 0) invalidID()
        else load(AO3SeriesFormUrls.manage(id)) { html, url -> parser.parseManage(html, url) }
    private fun invalidID() = AO3Result.Failure(AO3Error.Validation("Not a valid AO3 series URL."))

    private suspend fun <T> load(url: String, parse: (String, String) -> T): AO3Result<T> {
        if (!auth.state.value.isSignedIn) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val generation = auth.generation.value
        val response = client.getAuthenticated(url)
        currentCoroutineContext().ensureActive()
        if (generation != auth.generation.value) throw CancellationException()
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> try {
                val parsed = withContext(parseDispatcher) { parse(response.value.body, response.value.url) }
                if (generation != auth.generation.value) throw CancellationException()
                AO3Result.Success(parsed)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: AO3WorkFormParseException.LoginRequired) {
                auth.sessionDidExpire(generation)
                AO3Result.Failure(AO3Error.AuthenticationRequired)
            } catch (_: AO3WorkFormParseException.Overloaded) {
                AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, null))
            } catch (_: Exception) { AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's series form.")) }
        }
    }
}
