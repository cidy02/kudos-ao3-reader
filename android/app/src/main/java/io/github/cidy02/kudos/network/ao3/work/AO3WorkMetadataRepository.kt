package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

open class AO3WorkMetadataRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val urlBuilder: AO3DownloadUrlBuilder = AO3DownloadUrlBuilder(),
    private val parser: AO3WorkMetadataParser = AO3WorkMetadataParser()
) {
    open suspend fun fetch(workId: Long): AO3Result<AO3WorkMetadata> {
        return when (val result = client.get(urlBuilder.workMetadataUrl(workId))) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> {
                try {
                    AO3Result.Success(withContext(Dispatchers.Default) { parser.parse(result.value.body) })
                } catch (error: AO3WorkMetadataParseException.Overloaded) {
                    AO3Result.Failure(AO3Error.Overloaded(result.value.statusCode, null))
                } catch (error: Exception) {
                    AO3Result.Failure(AO3Error.Parse(error.message ?: "AO3 work metadata could not be parsed."))
                }
            }
        }
    }
}
