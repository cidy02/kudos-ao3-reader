package io.github.cidy02.kudos.network.ao3

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

interface AO3Client {
    suspend fun get(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): AO3Result<AO3HttpResponse>

    suspend fun getBytes(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): AO3Result<AO3BinaryResponse> {
        return when (val result = get(url, headers)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> AO3Result.Success(
                AO3BinaryResponse(
                    url = result.value.url,
                    statusCode = result.value.statusCode,
                    headers = result.value.headers,
                    body = result.value.body.toByteArray()
                )
            )
        }
    }
}

class OkHttpAO3Client(
    private val okHttpClient: OkHttpClient,
    private val config: AO3NetworkConfig = AO3NetworkConfig(),
    private val coordinator: AO3RequestCoordinator = AO3RequestCoordinator(config),
    private val coalescer: AO3RequestCoalescer<AO3RequestKey, AO3Result<AO3HttpResponse>> =
        AO3RequestCoalescer(),
    private val retryPolicy: AO3RetryPolicy = AO3RetryPolicy(config),
    private val delay: AO3Delay = CoroutineAO3Delay
) : AO3Client {
    constructor(
        config: AO3NetworkConfig = AO3NetworkConfig()
    ) : this(
        okHttpClient = OkHttpClient.Builder()
            .callTimeout(config.callTimeoutSeconds, TimeUnit.SECONDS)
            .followRedirects(true)
            .build(),
        config = config
    )

    override suspend fun get(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        val key = try {
            AO3RequestKey.get(url, headers)
        } catch (error: IllegalArgumentException) {
            return AO3Result.Failure(AO3Error.Validation("Invalid AO3 URL: $url"))
        }

        return coalescer.coalesce(key) {
            executeWithRetry(
                method = AO3HttpMethod.GET,
                url = key.canonicalUrl,
                headers = headers
            )
        }
    }

    override suspend fun getBytes(
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> {
        val key = try {
            AO3RequestKey.get(url, headers)
        } catch (error: IllegalArgumentException) {
            return AO3Result.Failure(AO3Error.Validation("Invalid AO3 URL: $url"))
        }

        return executeBinaryWithRetry(
            method = AO3HttpMethod.GET,
            url = key.canonicalUrl,
            headers = headers
        )
    }

    private suspend fun executeWithRetry(
        method: AO3HttpMethod,
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        var retryNumber = 0
        while (true) {
            val result = coordinator.coordinate {
                performOnce(method, url, headers)
            }
            if (result is AO3Result.Success) return result

            val error = (result as AO3Result.Failure).error
            retryNumber += 1
            if (!retryPolicy.shouldRetry(method, error, retryNumber)) return result

            delay.delay(retryPolicy.retryDelayMillis(error, retryNumber))
        }
    }

    private suspend fun performOnce(
        method: AO3HttpMethod,
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        val request = buildRequest(method, url, headers)
        return try {
            val response = okHttpClient.newCall(request).await()
            withContext(Dispatchers.IO) {
                response.use { mapResponse(it, originalUrl = url) }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            AO3Result.Failure(
                AO3Error.Network(
                    message = error.message ?: "Network request failed.",
                    cause = error
                )
            )
        }
    }

    private suspend fun executeBinaryWithRetry(
        method: AO3HttpMethod,
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> {
        var retryNumber = 0
        while (true) {
            val result = coordinator.coordinate {
                performBinaryOnce(method, url, headers)
            }
            if (result is AO3Result.Success) return result

            val error = (result as AO3Result.Failure).error
            retryNumber += 1
            if (!retryPolicy.shouldRetry(method, error, retryNumber)) return result

            delay.delay(retryPolicy.retryDelayMillis(error, retryNumber))
        }
    }

    private suspend fun performBinaryOnce(
        method: AO3HttpMethod,
        url: String,
        headers: Map<String, String>
    ): AO3Result<AO3BinaryResponse> {
        val request = buildRequest(method, url, headers)
        return try {
            val response = okHttpClient.newCall(request).await()
            withContext(Dispatchers.IO) {
                response.use { mapBinaryResponse(it, originalUrl = url) }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: IOException) {
            AO3Result.Failure(
                AO3Error.Network(
                    message = error.message ?: "Network request failed.",
                    cause = error
                )
            )
        }
    }

    private fun buildRequest(
        method: AO3HttpMethod,
        url: String,
        headers: Map<String, String>
    ): Request {
        val builder = Request.Builder().url(url)
        headers.forEach { (name, value) ->
            builder.header(name, value)
        }
        builder.header("User-Agent", AO3UserAgent.VALUE)

        return when (method) {
            AO3HttpMethod.GET -> builder.get().build()
            AO3HttpMethod.POST,
            AO3HttpMethod.PUT,
            AO3HttpMethod.PATCH,
            AO3HttpMethod.DELETE -> error("$method is not implemented in Phase 4.")
        }
    }

    private fun mapResponse(
        response: Response,
        originalUrl: String
    ): AO3Result<AO3HttpResponse> {
        val body = response.body.string()
        val statusCode = response.code
        val retryAfterMillis = AO3RetryAfter.parseMillis(response.header("Retry-After"))
        val finalUrl = response.request.url.toString()

        if (
            AO3Constants.isLoginUrl(finalUrl) &&
            !AO3Constants.isLoginUrl(originalUrl)
        ) {
            return AO3Result.Failure(AO3Error.AuthenticationRequired)
        }

        if (AO3OverloadDetector.isOverloadPage(body)) {
            return AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis))
        }

        return when (statusCode) {
            in 200..299 -> AO3Result.Success(
                AO3HttpResponse(
                    url = finalUrl,
                    statusCode = statusCode,
                    headers = response.headers.toMultimap(),
                    body = body
                )
            )
            400 -> AO3Result.Failure(AO3Error.BadRequest)
            401 -> AO3Result.Failure(AO3Error.AuthenticationRequired)
            403 -> AO3Result.Failure(AO3Error.Forbidden)
            404 -> AO3Result.Failure(AO3Error.NotFound)
            429 -> AO3Result.Failure(AO3Error.RateLimited(retryAfterMillis))
            in 500..599 -> AO3Result.Failure(AO3Error.Server(statusCode))
            else -> AO3Result.Failure(AO3Error.Http(statusCode))
        }
    }

    private fun mapBinaryResponse(
        response: Response,
        originalUrl: String
    ): AO3Result<AO3BinaryResponse> {
        val bytes = response.body.bytes()
        val statusCode = response.code
        val retryAfterMillis = AO3RetryAfter.parseMillis(response.header("Retry-After"))
        val finalUrl = response.request.url.toString()

        if (
            AO3Constants.isLoginUrl(finalUrl) &&
            !AO3Constants.isLoginUrl(originalUrl)
        ) {
            return AO3Result.Failure(AO3Error.AuthenticationRequired)
        }

        val textPreview = bytes.decodeToString(endIndex = minOf(bytes.size, 8192))
        if (AO3OverloadDetector.isOverloadPage(textPreview)) {
            return AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis))
        }

        return when (statusCode) {
            in 200..299 -> AO3Result.Success(
                AO3BinaryResponse(
                    url = finalUrl,
                    statusCode = statusCode,
                    headers = response.headers.toMultimap(),
                    body = bytes
                )
            )
            400 -> AO3Result.Failure(AO3Error.BadRequest)
            401 -> AO3Result.Failure(AO3Error.AuthenticationRequired)
            403 -> AO3Result.Failure(AO3Error.Forbidden)
            404 -> AO3Result.Failure(AO3Error.NotFound)
            429 -> AO3Result.Failure(AO3Error.RateLimited(retryAfterMillis))
            in 500..599 -> AO3Result.Failure(AO3Error.Server(statusCode))
            else -> AO3Result.Failure(AO3Error.Http(statusCode))
        }
    }

    private suspend fun Call.await(): Response {
        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { cancel() }
            enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    if (continuation.isActive) {
                        continuation.resume(response)
                    } else {
                        response.close()
                    }
                }
            })
        }
    }
}
