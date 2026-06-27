package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3WriteRepository(
    private val client: AO3AuthenticatedClient,
    private val parser: AO3WriteFormParser = AO3WriteFormParser()
) {
    suspend fun giveKudos(workId: Long): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()

        val response = client.postAuthenticated(
            url = AO3WriteUrls.kudosEndpoint(),
            formFields = listOf(
                "authenticity_token" to token,
                "kudo[commentable_id]" to workId.toString(),
                "kudo[commentable_type]" to "Work"
            ),
            headers = mapOf(
                "X-CSRF-Token" to token,
                "Referer" to workUrl,
                "X-Requested-With" to "XMLHttpRequest",
                "Accept" to "text/javascript, application/javascript, */*"
            )
        )
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val body = response.value.body
                when {
                    response.value.statusCode in 200..299 -> success(AO3WriteActionKind.Kudos, "Kudos left.")
                    response.value.statusCode == 422 && parser.alreadyKudosed(body) ->
                        success(AO3WriteActionKind.Kudos, "You've already left kudos here.")
                    else -> rejected(body, "AO3 didn't accept the kudos.")
                }
            }
        }
    }

    suspend fun toggleSubscribe(workId: Long): AO3Result<AO3WriteOutcome> {
        val username = client.username() ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val state = withContext(Dispatchers.Default) { parser.parseSubscription(html) }

        return if (state.isSubscribed) {
            val unsubscribeUrl = state.unsubscribePath?.let(AO3WriteUrls::absoluteUrl)
                ?: return AO3Result.Failure(AO3Error.Validation("Couldn't find AO3's unsubscribe form."))
            val response = client.postAuthenticated(
                url = unsubscribeUrl,
                formFields = listOf("_method" to "delete", "authenticity_token" to token),
                headers = writeHeaders(token, workUrl)
            )
            response.toOutcome(AO3WriteActionKind.Unsubscribe, "Unsubscribed.", "Couldn't unsubscribe.")
        } else {
            val response = client.postAuthenticated(
                url = AO3WriteUrls.subscriptionsEndpoint(username),
                formFields = listOf(
                    "authenticity_token" to token,
                    "subscription[subscribable_id]" to workId.toString(),
                    "subscription[subscribable_type]" to "Work"
                ),
                headers = writeHeaders(token, workUrl)
            )
            when (response) {
                is AO3Result.Failure -> response
                is AO3Result.Success -> {
                    if (response.value.body.contains("already subscribed", ignoreCase = true)) {
                        success(AO3WriteActionKind.Subscribe, "You're already subscribed.")
                    } else {
                        response.toOutcome(AO3WriteActionKind.Subscribe, "Subscribed.", "Couldn't subscribe.")
                    }
                }
            }
        }
    }

    suspend fun markForLater(workId: Long): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val response = client.postAuthenticated(
            url = AO3WriteUrls.markForLaterEndpoint(workId),
            formFields = listOf("authenticity_token" to token),
            headers = writeHeaders(token, workUrl)
        )
        return response.toOutcome(AO3WriteActionKind.MarkForLater, "Marked for later.", "Couldn't mark for later.")
    }

    suspend fun createBookmark(workId: Long, input: AO3BookmarkInput): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val fields = buildList {
            add("authenticity_token" to token)
            add("bookmark[bookmarker_notes]" to input.notes)
            add("bookmark[tag_string]" to input.tags)
            add("bookmark[collection_names]" to "")
            add("bookmark[private]" to if (input.isPrivate) "1" else "0")
            add("bookmark[rec]" to if (input.isRecommendation) "1" else "0")
            parser.parseDefaultPseudId(html, field = "bookmark[pseud_id]")?.let {
                add("bookmark[pseud_id]" to it)
            }
        }
        val response = client.postAuthenticated(
            url = AO3WriteUrls.bookmarksEndpoint(workId),
            formFields = fields,
            headers = writeHeaders(token, workUrl)
        )
        return response.toOutcome(AO3WriteActionKind.Bookmark, "Bookmarked.", "Couldn't bookmark this work.")
    }

    private suspend fun parseToken(html: String): String? {
        return withContext(Dispatchers.Default) { parser.parseAuthenticityToken(html) }
    }

    private fun AO3Result<AO3HttpResponse>.toOutcome(
        kind: AO3WriteActionKind,
        successMessage: String,
        fallbackError: String
    ): AO3Result<AO3WriteOutcome> {
        return when (this) {
            is AO3Result.Failure -> this
            is AO3Result.Success -> {
                if (value.statusCode in 200..399 && parser.writeErrorMessage(value.body) == null) {
                    success(kind, successMessage)
                } else {
                    rejected(value.body, fallbackError)
                }
            }
        }
    }

    private fun writeHeaders(token: String, referer: String): Map<String, String> {
        return mapOf(
            "X-CSRF-Token" to token,
            "Referer" to referer
        )
    }

    private fun success(kind: AO3WriteActionKind, message: String): AO3Result.Success<AO3WriteOutcome> {
        return AO3Result.Success(AO3WriteOutcome(kind, message))
    }

    private fun rejected(html: String, fallback: String): AO3Result.Failure {
        return AO3Result.Failure(AO3Error.Validation(parser.writeErrorMessage(html) ?: fallback))
    }

    private fun missingToken(): AO3Result.Failure {
        return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the AO3 request. Open the work on AO3 and try there."))
    }
}
