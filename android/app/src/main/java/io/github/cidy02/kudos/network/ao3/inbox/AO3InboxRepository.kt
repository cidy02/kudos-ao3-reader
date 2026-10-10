package io.github.cidy02.kudos.network.ao3.inbox

import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Authenticated GET/parse for `/users/<username>/inbox` and CSRF-safe bulk
 * POSTs against the form already scraped from the loaded page.
 *
 * Mirrors iOS `AO3Client+Inbox` + `AO3InboxActions`: bulk writes do **not**
 * re-GET for a token — they reuse the just-displayed form.
 */
class AO3InboxRepository(
    private val client: AO3AuthenticatedClient,
    private val parser: AO3InboxParser = AO3InboxParser(),
    private val formParser: AO3WriteFormParser = AO3WriteFormParser(),
    private val pageCache: AO3PageCache = AO3PageCache.shared
) {
    val sessionChanges: kotlinx.coroutines.flow.StateFlow<Int> = client.sessionChanges ?: kotlinx.coroutines.flow.MutableStateFlow(0)
    fun viewerScope() = AO3PageCache.scope(client)

    /**
     * Loads one Inbox page. When [filterForm] + [filterValues] are provided,
     * uses AO3's own filter GET URL; otherwise the plain paginated inbox URL.
     */
    suspend fun load(
        page: Int = 1,
        filterForm: AO3InboxFilterForm? = null,
        filterValues: Map<String, String> = emptyMap(),
        bypassCache: Boolean = false
    ): AO3Result<AO3InboxPage> {
        val username = client.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)

        val url = when {
            filterForm != null -> filterForm.url(filterValues, page)
                ?: AO3InboxParser.inboxUrl(username, page)
            else -> AO3InboxParser.inboxUrl(username, page)
        } ?: return AO3Result.Failure(AO3Error.Validation("Couldn't build the AO3 Inbox URL."))

        return pageCache.read(url, AO3PageCache.Kind.Inbox, client, bypassCache,
            fetch = { client.getAuthenticated(url) },
            parse = { parsePage(it.body, page, it.url, it.statusCode) })
    }

    /**
     * Submits one AO3 mass-edit action. Fail-closed: missing/partial form
     * parameters refuse the write rather than guessing fields.
     */
    suspend fun performBulkAction(
        action: AO3InboxBulkAction,
        form: AO3InboxBulkForm,
        items: List<AO3InboxItem>,
        referer: String
    ): AO3Result<String> {
        if (client.username() == null) {
            return AO3Result.Failure(AO3Error.AuthenticationRequired)
        }
        if (!form.htmlMethod.equals("post", ignoreCase = true)) {
            return AO3Result.Failure(
                AO3Error.Validation("AO3's Inbox form no longer supports this native action.")
            )
        }
        val parameters = form.parameters(items, action)
            ?: return AO3Result.Failure(
                AO3Error.Validation("Couldn't prepare AO3's Inbox action. Reload and try again.")
            )

        val viewer = AO3PageCache.scope(client)
        return when (
            val response = client.postAuthenticated(
                url = form.actionUrl,
                formFields = parameters,
                headers = mapOf(
                    "X-CSRF-Token" to form.csrfToken,
                    "Referer" to referer
                )
            )
        ) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = formParser.commentWriteFailure(
                    response.value.statusCode, response.value.body, "AO3 couldn't update your Inbox."
                )
                if (error == null) {
                    if (AO3PageCache.scope(client) == viewer) {
                        AO3InboxParser.inboxUrl(viewer.viewer ?: "", 1)?.let {
                            pageCache.removePages(java.net.URI(it).path, viewer)
                            if (form.actionUrl != referer) {
                                pageCache.remove(AO3PageCache.Key(form.actionUrl, viewer, AO3PageCache.Kind.Inbox))
                            }
                        }
                    }
                    AO3Result.Success(action.successMessage)
                } else {
                    AO3Result.Failure(AO3Error.Validation(error))
                }
            }
        }
    }

    private suspend fun parsePage(
        html: String,
        page: Int,
        finalUrl: String,
        statusCode: Int
    ): AO3Result<AO3InboxPage> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseInboxPage(html, page, finalUrl)
                }
            )
        } catch (_: AO3InboxParseException.LoginRequired) {
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        } catch (_: AO3InboxParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3InboxParseException) {
            AO3Result.Failure(
                AO3Error.Parse(error.message ?: "AO3 Inbox page could not be parsed.")
            )
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            AO3Result.Failure(
                AO3Error.Parse(error.message ?: "AO3 Inbox page could not be parsed.")
            )
        }
    }
}
