package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AccountListRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val authRepository: AO3AuthRepository,
    private val urls: AO3AccountUrls = AO3AccountUrls(),
    private val parser: AO3AccountParser = AO3AccountParser()
) {
    suspend fun load(type: AccountListType, page: Int = 1): AO3Result<AO3SearchPage> {
        val username = authRepository.username()
            ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val url = urls.url(type, username, page)
        val headers = when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }

        return when (val result = client.get(url, headers)) {
            is AO3Result.Failure -> {
                if (result.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire()
                result
            }
            is AO3Result.Success -> parse(type, result.value.body, result.value.url, result.value.statusCode, page)
        }
    }

    private suspend fun parse(
        type: AccountListType,
        html: String,
        finalUrl: String,
        statusCode: Int,
        page: Int
    ): AO3Result<AO3SearchPage> {
        return try {
            AO3Result.Success(
                withContext(Dispatchers.Default) {
                    parser.parseAccountList(html, page, type, finalUrl)
                }
            )
        } catch (error: AO3AccountParseException.LoginRequired) {
            authRepository.sessionDidExpire()
            AO3Result.Failure(AO3Error.AuthenticationRequired)
        } catch (error: AO3AccountParseException.Overloaded) {
            AO3Result.Failure(AO3Error.Overloaded(statusCode, retryAfterMillis = null))
        } catch (error: AO3AccountParseException) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 account page could not be parsed."))
        } catch (error: Exception) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 account page could not be parsed."))
        }
    }
}
