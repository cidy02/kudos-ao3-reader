package io.github.cidy02.kudos.network.ao3.inbox

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
    private val formParser: AO3WriteFormParser = AO3WriteFormParser()
) {
    /**
     * Loads one Inbox page. When [filterForm] + [filterValues] are provided,
     * uses AO3's own filter GET URL; otherwise the plain paginated inbox URL.
     */
    suspend fun load(
        page: Int = 1,
        filterForm: AO3InboxFilterForm? = null,
        filterValues: Map<String, String> = emptyMap()
    ): AO3Result<AO3InboxPage> {
        val username = client.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)

        val url = when {
            filterForm != null -> filterForm.url(filterValues, page)
                ?: AO3InboxParser.inboxUrl(username, page)
            else -> AO3InboxParser.inboxUrl(username, page)
        } ?: return AO3Result.Failure(AO3Error.Validation("Couldn't build the AO3 Inbox URL."))

        return when (val result = client.getAuthenticated(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> parsePage(
                html = result.value.body,
                page = page,
                finalUrl = result.value.url,
                statusCode = result.value.statusCode
            )
        }
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
                val error = formParser.writeErrorMessage(response.value.body)
                if (response.value.statusCode in 200..399 && error == null) {
                    AO3Result.Success(action.successMessage)
                } else {
                    AO3Result.Failure(
                        AO3Error.Validation(error ?: "AO3 couldn't update your Inbox.")
                    )
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
        } catch (error: Exception) {
            AO3Result.Failure(
                AO3Error.Parse(error.message ?: "AO3 Inbox page could not be parsed.")
            )
        }
    }
}
