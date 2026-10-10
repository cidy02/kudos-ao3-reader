package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3FormPostClient
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

interface AO3AuthenticatedClient {
    val sessionChanges: kotlinx.coroutines.flow.StateFlow<Int>? get() = null
    fun username(): String?
    fun sessionGeneration(): Int? = null

    /** Check the preparing session again at the shared client's dispatch boundary. */
    suspend fun postAuthenticatedInSession(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String>,
        generation: Int?
    ): AO3Result<AO3HttpResponse> {
        if (generation != sessionGeneration()) throw CancellationException()
        return postAuthenticated(url, formFields, headers)
    }

    suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse>

    suspend fun postAuthenticated(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String> = emptyMap()
    ): AO3Result<AO3HttpResponse>
}

class DefaultAO3AuthenticatedClient(
    private val getClient: AO3Client,
    private val postClient: AO3FormPostClient,
    private val authRepository: AO3AuthRepository
) : AO3AuthenticatedClient {
    override val sessionChanges: kotlinx.coroutines.flow.StateFlow<Int> get() = authRepository.generation
    override fun username(): String? = authRepository.username()
    override fun sessionGeneration(): Int = authRepository.generation.value

    override suspend fun postAuthenticatedInSession(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String>,
        generation: Int?
    ): AO3Result<AO3HttpResponse> {
        fun requireSession() {
            if (generation != sessionGeneration()) throw CancellationException()
        }
        requireSession()
        val authHeaders = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        requireSession()
        val response = postClient.postFormChecked(url, formFields, headers + authHeaders, ::requireSession)
        if (generation == sessionGeneration() && response is AO3Result.Failure &&
            response.error == AO3Error.AuthenticationRequired
        ) authRepository.sessionDidExpire(generation)
        return response
    }

    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        val generation = sessionGeneration()
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }

        val response = getClient.get(url, headers)
        if (generation != sessionGeneration()) throw CancellationException()
        if (response is AO3Result.Failure && response.error == AO3Error.AuthenticationRequired) {
            authRepository.sessionDidExpire(generation)
        }
        return response
    }

    override suspend fun postAuthenticated(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        // The session at the moment of the call. This used to copy the cookie and then wait
        // its turn in the request queue with no further check: a comment posted just before
        // signing out went out afterwards under the account that had been left, and a 401 for
        // it signed out whoever was signed in by then (audit A17-3). The fenced path checks
        // the session again after the wait, immediately before sending, and expires only its
        // own session.
        val generation = sessionGeneration()
        return try {
            postAuthenticatedInSession(url, formFields, headers, generation)
        } catch (cancelled: CancellationException) {
            // Our own fence, not the caller being cancelled: tell the caller plainly so its
            // screen does not wait for an answer that will not come.
            currentCoroutineContext().ensureActive()
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        }
    }
}
