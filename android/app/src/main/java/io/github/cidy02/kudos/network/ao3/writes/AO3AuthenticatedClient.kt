package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3FormPostClient
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.CancellationException

interface AO3AuthenticatedClient {
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
        val authHeaders = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }

        return postClient.postForm(
            url = url,
            formFields = formFields,
            headers = headers + authHeaders
        ).expireSessionIfNeeded()
    }

    private suspend fun AO3Result<AO3HttpResponse>.expireSessionIfNeeded(): AO3Result<AO3HttpResponse> {
        if (this is AO3Result.Failure && error == AO3Error.AuthenticationRequired) {
            authRepository.sessionDidExpire()
        }
        return this
    }
}
