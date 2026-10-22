package io.github.cidy02.kudos.network.ao3.comments

import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.currentCoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.isOffline
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
    private val pseudStore: io.github.cidy02.kudos.auth.AO3PostingPseudStore? = null,
    private val cache: CommentCache? = null
) {
    /**
     * Loads one page of the comment thread. Prefer an authenticated GET when a
     * session exists so restricted works and the composer form are available
     * (public-only fails for many). [page] is 1-based; only pages past the first
     * add `?page=N` on the request URL (iOS `commentsPageURL`).
     */
    suspend fun loadThread(
        target: AO3CommentTarget,
        page: Int = 1,
        focusedCommentId: Long? = null,
        /**
         * False for a read the reader did not open as a comments page (the Inbox looking up a
         * work's authors): its answer is used once and not kept for offline reading.
         */
        useCache: Boolean = true
    ): AO3Result<AO3CommentThread> {
        val safePage = page.coerceAtLeast(1)
        val pageUrl = if (focusedCommentId != null) {
            AO3CommentUrls.commentThreadUrl(focusedCommentId)
        } else {
            target.pageUrl(safePage)
        }
        val viewer = authenticatedClient.username()
        val authAttempt = authenticatedClient.getAuthenticated(pageUrl)
        val response = when (authAttempt) {
            is AO3Result.Success -> authAttempt.value
            is AO3Result.Failure -> {
                // Signed out, the page is read publicly. Signed in, it is read as the account or
                // not at all, as iOS: a public copy has no Reply or Edit, and asking again without
                // the session is a second request for one tap (A59).
                val public = if (viewer != null) authAttempt else publicClient.get(pageUrl)
                when (public) {
                    is AO3Result.Failure -> {
                        // Only when AO3 could not be reached, and only this viewer's own copy:
                        // a refusal ("log in", "not found") is AO3's answer, not a reason to
                        // show what someone else was allowed to see (audit A17-4).
                        if (useCache && public.error is AO3Error.Network && focusedCommentId == null) {
                            // Marked as a kept copy, so the screen says it is one and from when.
                            cache?.load(target, safePage, viewer)?.let {
                                return AO3Result.Success(it.copy(fetchedAt = it.fetchedAt ?: 0L,
                                    keptWhileOffline = public.error.isOffline()), isStale = true)
                            }
                        }
                        return public
                    }
                    is AO3Result.Success -> {
                        public.value
                    }
                }
            }
        }
        val thread = parseThread(response.body, response.url, target, response.statusCode, safePage,
            isStandaloneThread = focusedCommentId != null)
        // Only a work's or chapter's own page is kept. One comment's thread (an Inbox row) is
        // a different page: stored under the work's page 1 it became that page offline
        // (audit A22-2).
        if (useCache && thread is AO3Result.Success && focusedCommentId == null) {
            cache?.save(thread.value.copy(fetchedAt = System.currentTimeMillis()), safePage, viewer)
        }
        return thread
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
        parentCommentId: Long? = null,
        onFormPrepared: (Boolean) -> Unit = {}
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
        val session = authenticatedClient.sessionGeneration()
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

        val commentableId = replyParentId ?: target.workId
        onFormPrepared(org.jsoup.Jsoup.parse(page.body).selectFirst(
            "#add_comment_placeholder form#comment_for_$commentableId p.notice, " +
                "#add_comment_reply_placeholder_$commentableId form#comment_for_$commentableId p.notice"
        ) != null)
        val fields = buildList {
            add("authenticity_token" to token)
            add("comment[comment_content]" to text)
            if (!preferredPseudId.isNullOrBlank()) add("comment[pseud_id]" to preferredPseudId)
        }
        return when (val response = postInSession(
            session, submitUrl, fields,
            mapOf(
                "X-CSRF-Token" to token,
                "Referer" to csrfSourceUrl
            )
        )) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = formParser.commentWriteFailure(
                    response.value.statusCode, response.value.body,
                    if (replyParentId != null) "Couldn't post reply." else "Couldn't post comment."
                )
                if (error == null) {
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
                            "Posted." // iOS's one word for a comment and for a reply
                        )
                    )
                } else {
                    AO3Result.Failure(AO3Error.Validation(error))
                }
            }
        }
    }

    /** Authenticated evidence only: no public fallback, cache, polling, or POST. */
    suspend fun verifySubmission(
        key: CommentSubmissionKey, entry: CommentSubmissionStore.Entry, expectedGeneration: Int
    ): AO3Result<CommentVerification> {
        fun sameReader() = authenticatedClient.sessionGeneration() == expectedGeneration &&
            authenticatedClient.username() == key.identity
        if (!sameReader()) return AO3Result.Success(CommentVerification.Unknown)
        var authenticationFailure: AO3Result.Failure? = null
        val target = AO3CommentTarget.Work(key.workId)
        suspend fun read(page: Int, parent: Long?): AO3CommentThread? {
            if (!sameReader()) return null
            val url = parent?.let { AO3CommentUrls.commentThreadUrl(it) } ?: target.pageUrl(page)
            val response = when (val result = authenticatedClient.getAuthenticated(url)) {
                is AO3Result.Success -> result
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) authenticationFailure = result
                    return null
                }
            }
            if (!sameReader()) return null
            return (parseThread(response.value.body, response.value.url, target, response.value.statusCode,
                page, parent != null) as? AO3Result.Success)?.value
        }
        val first = read(1, key.parentId) ?: return authenticationFailure ?: AO3Result.Success(CommentVerification.Unknown)
        val page = if (key.parentId == null && first.totalPages > 1) {
            read(first.totalPages, null) ?: return authenticationFailure ?: AO3Result.Success(CommentVerification.Unknown)
        } else first
        if (!sameReader()) return AO3Result.Success(CommentVerification.Unknown)
        return AO3Result.Success(commentVerification(page, key, entry))
    }

    suspend fun editComment(path: String, content: String): AO3Result<AO3WriteOutcome> {
        val text = content.trim()
        if (text.isEmpty()) return AO3Result.Failure(AO3Error.Validation("Comment cannot be empty."))
        val url = AO3WriteUrls.absoluteUrl(path) ?: return AO3Result.Failure(AO3Error.BadRequest)
        val session = authenticatedClient.sessionGeneration()
        val page = when (val result = authenticatedClient.getAuthenticated(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val token = formParser.parseAuthenticityToken(page.body) ?: return AO3Result.Failure(AO3Error.BadRequest)
        
        val fields = listOf(
            "_method" to "put",
            "authenticity_token" to token,
            "comment[comment_content]" to text
        )
        // The form is read at /comments/<id>/edit; the update goes to /comments/<id>, as iOS's
        // `commentThreadURL`. It was sent back to the form's address, and failed (A50 F11).
        val updateUrl = url.substringBefore('?').removeSuffix("/").removeSuffix("/edit")
        return when (val response = postInSession(session, updateUrl, fields, mapOf("X-CSRF-Token" to token, "Referer" to url))) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = formParser.commentWriteFailure(
                    response.value.statusCode, response.value.body, "Couldn't update comment."
                )
                if (error == null) {
                    AO3Result.Success(AO3WriteOutcome(AO3WriteActionKind.Comment, "Comment updated."))
                } else {
                    AO3Result.Failure(AO3Error.Validation(error))
                }
            }
        }
    }

    /**
     * Deleted at the comment itself, `/comments/<id>` with `_method=delete`, as iOS. AO3's Delete
     * link is a confirmation page (`/comments/delete_comment?id=`), and posting to it deleted
     * nothing (A51 F2); it still decides whether Delete is offered.
     */
    suspend fun deleteComment(commentId: Long): AO3Result<Unit> {
        val url = runCatching { AO3CommentUrls.commentThreadUrl(commentId) }.getOrNull()
            ?: return AO3Result.Failure(AO3Error.BadRequest)
        val session = authenticatedClient.sessionGeneration()
        val page = when (val result = authenticatedClient.getAuthenticated(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val token = formParser.parseAuthenticityToken(page.body) ?: return AO3Result.Failure(AO3Error.BadRequest)
        
        val fields = listOf("_method" to "delete", "authenticity_token" to token)
        return when (val response = postInSession(session, url, fields, mapOf("X-CSRF-Token" to token, "Referer" to url))) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                // otwarchive reports a failed delete as `flash[:comment_error]` on a redirected
                // 200: the body was never read, so that said "Comment deleted." (audit A17-1).
                val error = formParser.commentWriteFailure(
                    response.value.statusCode, response.value.body, "Couldn't delete comment."
                )
                if (error == null) AO3Result.Success(Unit) else AO3Result.Failure(AO3Error.Validation(error))
            }
        }
    }

    private suspend fun parseThread(
        html: String,
        finalUrl: String,
        target: AO3CommentTarget,
        statusCode: Int,
        page: Int,
        isStandaloneThread: Boolean
    ): AO3Result<AO3CommentThread> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseThread(html, finalUrl, target, page, isStandaloneThread)
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

    /**
     * Sent only in the session its form was read in, as iOS's `requireSessionGeneration`: a
     * sign-out or another account between the form and the send sent the first reader's
     * comment under the second's cookie (A50 F10).
     */
    private suspend fun postInSession(
        session: Int?,
        url: String,
        fields: List<Pair<String, String>>,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = try {
        authenticatedClient.postAuthenticatedInSession(url, fields, headers, session)
    } catch (fenced: CancellationException) {
        currentCoroutineContext().ensureActive()
        AO3Result.Failure(AO3Error.AuthenticationRequired)
    }
}
