package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteOutcome
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3CommentRepository(
    private val publicClient: AO3Client,
    private val authenticatedClient: AO3AuthenticatedClient,
    private val parser: AO3CommentParser = AO3CommentParser(),
    private val formParser: AO3WriteFormParser = AO3WriteFormParser(),
    private val pseudStore: io.github.cidy02.kudos.auth.AO3PostingPseudStore? = null
) {
    /**
     * Loads one page of the comment thread. Prefer an authenticated GET when a
     * session exists so restricted works and the composer form are available
     * (public-only fails for many). [page] is 1-based; only pages past the first
     * add `?page=N` on the request URL (iOS `commentsPageURL`).
     */
    suspend fun loadThread(
        target: AO3CommentTarget,
        page: Int = 1
    ): AO3Result<AO3CommentThread> {
        val safePage = page.coerceAtLeast(1)
        val pageUrl = target.pageUrl(safePage)
        val authAttempt = authenticatedClient.getAuthenticated(pageUrl)
        val response = when (authAttempt) {
            is AO3Result.Success -> authAttempt.value
            is AO3Result.Failure -> {
                // Not signed in (or session expired): fall back to public HTML.
                if (authAttempt.error != AO3Error.AuthenticationRequired) {
                    // Still try public — may work for open works.
                }
                when (val public = publicClient.get(pageUrl)) {
                    is AO3Result.Failure -> return public
                    is AO3Result.Success -> public.value
                }
            }
        }
        return parseThread(response.body, response.url, target, response.statusCode, safePage)
    }

    /**
     * Posts a top-level comment or a reply.
     *
     * - Top-level ([parentCommentId] null): GET the work page for CSRF + default
     *   pseud, POST to the work/chapter comments endpoint (existing behavior).
     * - Reply ([parentCommentId] set): GET the parent comment's standalone thread
     *   page (`/comments/<id>`) for CSRF + pseud, POST to
     *   `/comments/<id>/comments` — mirrors iOS `postCommentReply`.
     */
    suspend fun submitComment(
        target: AO3CommentTarget,
        content: String,
        parentCommentId: Long? = null
    ): AO3Result<AO3WriteOutcome> {
        val text = content.trim()
        if (text.isEmpty()) return AO3Result.Failure(AO3Error.Validation("Write a comment first."))

        val replyParentId = parentCommentId?.takeIf { it > 0 }
        val csrfSourceUrl = if (replyParentId != null) {
            AO3CommentUrls.commentThreadUrl(replyParentId, isReply = true)
        } else {
            // Work page (view_adult) is enough for token/pseud — same as iOS workURL.
            AO3WriteUrls.workUrl(target.workId)
        }
        val page = when (val result = authenticatedClient.getAuthenticated(csrfSourceUrl)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val form = withContext(Dispatchers.Default) {
            parser.parseCommentForm(page.body, page.url, target)
        }
        val token = form?.authenticityToken
            ?: formParser.parseAuthenticityToken(page.body)
            ?: return AO3Result.Failure(
                AO3Error.Validation(
                    if (replyParentId != null) {
                        "AO3 did not provide a reply form for this comment. Are you signed in?"
                    } else {
                        "AO3 did not provide a comment form for this work. Are you signed in?"
                    }
                )
            )
        val submitUrl = if (replyParentId != null) {
            AO3CommentUrls.commentReplyEndpoint(replyParentId)
        } else {
            form?.actionUrl?.takeIf { it.isNotBlank() } ?: target.defaultSubmitUrl()
        }

        // Preference resolution: persisted > AO3 default.
        val preferredPseudId = if (pseudStore != null && form != null) {
            val username = authenticatedClient.username()
            val persisted = if (username != null) pseudStore.pseudName(username) else null
            form.availablePseuds.find { it.name.equals(persisted, true) }?.id
                ?: form.pseudId
        } else {
            form?.pseudId ?: formParser.parseDefaultPseudId(page.body)
        }

        val fields = buildList {
            add("authenticity_token" to token)
            add("comment[comment_content]" to text)
            if (!preferredPseudId.isNullOrBlank()) add("comment[pseud_id]" to preferredPseudId)
        }
        return when (val response = authenticatedClient.postAuthenticated(
            url = submitUrl,
            formFields = fields,
            headers = mapOf(
                "X-CSRF-Token" to token,
                "Referer" to csrfSourceUrl
            )
        )) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = formParser.writeErrorMessage(response.value.body)
                if (response.value.statusCode in 200..399 && error == null) {
                    // Persist choice on success.
                    if (preferredPseudId != null && form != null) {
                        val chosenName = form.availablePseuds.find { it.id == preferredPseudId }?.name
                        val username = authenticatedClient.username()
                        if (chosenName != null && username != null) {
                            pseudStore?.setPseudName(chosenName, username)
                        }
                    }
                    AO3Result.Success(
                        AO3WriteOutcome(
                            AO3WriteActionKind.Comment,
                            if (replyParentId != null) "Reply posted." else "Comment posted."
                        )
                    )
                } else {
                    AO3Result.Failure(
                        AO3Error.Validation(
                            error ?: if (replyParentId != null) {
                                "AO3 couldn't post the reply."
                            } else {
                                "AO3 couldn't post the comment."
                            }
                        )
                    )
                }
            }
        }
    }

    private suspend fun parseThread(
        html: String,
        finalUrl: String,
        target: AO3CommentTarget,
        statusCode: Int,
        page: Int
    ): AO3Result<AO3CommentThread> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseThread(html, finalUrl, target, page)
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
