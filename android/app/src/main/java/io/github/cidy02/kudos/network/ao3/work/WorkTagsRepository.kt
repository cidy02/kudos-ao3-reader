package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Background data layer for work tag updates and 404/availability detection.
 * Port of iOS `WorkTagsRepository`.
 */
class WorkTagsRepository(
    private val client: AO3Client = OkHttpAO3Client(),
    private val parser: AO3WorkMetadataParser = AO3WorkMetadataParser()
) {
    /**
     * Re-fetches a work's front page to get the latest tags and availability.
     * Returns the updated metadata or a 404 error if the work is gone.
     */
    suspend fun refreshTags(workId: Long): AO3Result<AO3WorkMetadata> {
        val url = WorkTags.ao3WorkUrl(workId)
        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> {
                if (result.value.statusCode == 404) {
                    AO3Result.Failure(AO3Error.NotFound)
                } else {
                    runParse { parser.parse(result.value.body) }
                }
            }
        }
    }

    private suspend fun <T> runParse(block: () -> T): AO3Result<T> {
        return try {
            AO3Result.Success(withContext(Dispatchers.Default) { block() })
        } catch (error: Exception) {
            AO3Result.Failure(AO3Error.Parse(error.message ?: "Failed to parse work tags."))
        }
    }
}
