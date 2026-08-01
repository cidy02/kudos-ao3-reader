package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3CommentRepository(
    private val publicClient: AO3Client,
    private val authenticatedClient: AO3AuthenticatedClient,
    private val parser: AO3CommentParser = AO3CommentParser(),
    private val formParser: AO3WriteFormParser = AO3WriteFormParser()
) {
    /**
     * Loads the comment thread. Prefer an authenticated GET when a session exists so
     * restricted works and the composer form are available (public-only fails for many).
     */
    suspend fun loadThread(target: AO3CommentTarget): AO3Result<AO3CommentThread> {
        val authAttempt = authenticatedClient.getAuthenticated(target.pageUrl())
        val page = when (authAttempt) {
            is AO3Result.Success -> authAttempt.value
            is AO3Result.Failure -> {
                // Not signed in (or session expired): fall back to public HTML.
                if (authAttempt.error != AO3Error.AuthenticationRequired) {
                    // Still try public — may work for open works.
                }
                when (val public = publicClient.get(target.pageUrl())) {
                    is AO3Result.Failure -> return public
                    is AO3Result.Success -> public.value
                }
            }
        }
        return parseThread(page.body, page.url, target, page.statusCode)
    }

    /**
     * Posts a comment. Mirrors Apple [AO3AuthService.postComment]: GET the work page
     * for CSRF + default pseud, POST to the comments endpoint (not the show_comments URL).
     */
    suspend fun submitComment(
        target: AO3CommentTarget,
        content: String
    ): AO3Result<AO3WriteOutcome> {
        val text = content.trim()
        if (text.isEmpty()) return AO3Result.Failure(AO3Error.Validation("Write a comment first."))

        // Work page (view_adult) is enough for token/pseud — same as iOS workURL.
        val workPageUrl = io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls.workUrl(target.workId)
        val page = when (val result = authenticatedClient.getAuthenticated(workPageUrl)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val form = withContext(Dispatchers.Default) {
            parser.parseCommentForm(page.body, page.url, target)
        }
        val token = form?.authenticityToken
            ?: formParser.parseAuthenticityToken(page.body)
            ?: return AO3Result.Failure(
                AO3Error.Validation("AO3 did not provide a comment form for this work. Are you signed in?")
            )
        val submitUrl = form?.actionUrl?.takeIf { it.isNotBlank() } ?: target.defaultSubmitUrl()
        val pseudId = form?.pseudId ?: formParser.parseDefaultPseudId(page.body)

        val fields = buildList {
            add("authenticity_token" to token)
            add("comment[comment_content]" to text)
            if (!pseudId.isNullOrBlank()) add("comment[pseud_id]" to pseudId)
        }
        return when (val response = authenticatedClient.postAuthenticated(
            url = submitUrl,
            formFields = fields,
            headers = mapOf(
                "X-CSRF-Token" to token,
                "Referer" to workPageUrl
            )
        )) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = formParser.writeErrorMessage(response.value.body)
                if (response.value.statusCode in 200..399 && error == null) {
                    AO3Result.Success(AO3WriteOutcome(AO3WriteActionKind.Comment, "Comment posted."))
                } else {
                    AO3Result.Failure(AO3Error.Validation(error ?: "AO3 couldn't post the comment."))
                }
            }
        }
    }

    private suspend fun parseThread(
        html: String,
        finalUrl: String,
        target: AO3CommentTarget,
        statusCode: Int
    ): AO3Result<AO3CommentThread> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseThread(html, finalUrl, target)
                }
            )
        } catch (error: AO3CommentParseException.LoginRequired) {
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        } catch (error: AO3CommentParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: Exception) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 comments could not be parsed."))
        }
    }
}
